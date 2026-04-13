#!/usr/bin/env node
/**
 * iCrashDiag — Gumroad product setup (via Cloudflare Worker)
 *
 * Le redirect URI est ton CF Worker — fonctionne depuis n'importe quelle machine.
 *
 * ÉTAPES :
 *   1. Va sur https://gumroad.com/oauth/applications → "Create application"
 *        Name        : iCrashDiag Setup
 *        Redirect URI: https://icrashdiag-license.sam-muselet.workers.dev/oauth/callback
 *
 *   2. Copie Application ID et Secret ci-dessous (ou passe-les en env vars)
 *
 *   3. Deploy le worker : cd license-worker && wrangler deploy
 *
 *   4. Lance ce script : node gumroad-setup.js
 */

const https = require("https");
const { execSync } = require("child_process");

const CLIENT_ID     = process.env.GUMROAD_CLIENT_ID     || "PASTE_YOUR_APPLICATION_ID";
const CLIENT_SECRET = process.env.GUMROAD_CLIENT_SECRET || "PASTE_YOUR_APPLICATION_SECRET";

const REDIRECT_URI  = "https://icrashdiag-license.sam-muselet.workers.dev/oauth/callback";
const WORKER_URL    = "https://icrashdiag-license.sam-muselet.workers.dev";
const SCOPE         = "edit_products view_profile";

function post(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = JSON.stringify(body);
    const req = https.request({
      hostname: u.hostname,
      path: u.pathname,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(data),
        ...headers,
      },
    }, res => {
      let raw = "";
      res.on("data", c => (raw += c));
      res.on("end", () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); }
        catch { reject(new Error("Invalid JSON: " + raw)); }
      });
    });
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}

const readline = require("readline").createInterface({
  input: process.stdin,
  output: process.stdout,
});
const ask = q => new Promise(r => readline.question(q, r));

async function main() {
  if (CLIENT_ID === "PASTE_YOUR_APPLICATION_ID") {
    console.log("\n❌  Remplis CLIENT_ID et CLIENT_SECRET dans le script.");
    console.log("   → https://gumroad.com/oauth/applications\n");
    process.exit(1);
  }

  const authURL = `https://gumroad.com/oauth/authorize?client_id=${encodeURIComponent(CLIENT_ID)}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&scope=${encodeURIComponent(SCOPE)}&response_type=code`;

  console.log("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("  iCrashDiag — Gumroad Setup");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  console.log("1️⃣   Ouverture de la page d'autorisation Gumroad…");
  console.log("   Si ça ne s'ouvre pas, visite :\n  ", authURL, "\n");

  try { execSync(`open "${authURL}"`); }
  catch { try { execSync(`xdg-open "${authURL}"`); } catch {} }

  console.log("2️⃣   Clique 'Authorize' sur la page Gumroad.");
  console.log("   Le Worker va recevoir le code automatiquement.\n");

  await ask("   Appuie sur Entrée une fois que tu as autorisé… ");

  console.log("\n3️⃣   Création du produit via le Worker…");

  const res = await post(`${WORKER_URL}/oauth/create-product`, {
    client_id:     CLIENT_ID,
    client_secret: CLIENT_SECRET,
  });

  if (res.body.warning) {
    console.log("\n⚠️  ", res.body.warning);
    console.log("   Crée le produit manuellement sur https://gumroad.com/products/new");
    console.log("   Puis : node gumroad-update-urls.js TON_URL\n");
    readline.close();
    return;
  }

  if (!res.body.success) {
    console.error("\n❌  Erreur :", JSON.stringify(res.body, null, 2));
    readline.close();
    process.exit(1);
  }

  const { permalink, product_id, name } = res.body;

  console.log("\n✅  Produit créé !");
  console.log("   Nom        :", name);
  console.log("   ID         :", product_id);
  console.log("   URL        :", permalink);
  console.log("\n4️⃣   Injection de l'URL dans le code…");

  // Inject URLs directly
  const { execSync: exec } = require("child_process");
  try {
    exec(`node ${__dirname}/gumroad-update-urls.js "${permalink}"`, { stdio: "inherit" });
  } catch {
    console.log(`   Fais-le manuellement : node gumroad-update-urls.js "${permalink}"`);
  }

  console.log("\n5️⃣   Prochaines étapes :");
  console.log("   → Va sur Gumroad, ajoute le fichier .app au produit, puis publie-le.");
  console.log("   → swift build");
  console.log("   → wrangler deploy (dans license-worker/)\n");

  readline.close();
}

main().catch(err => {
  console.error("❌ Erreur:", err.message);
  process.exit(1);
});
