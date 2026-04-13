export interface Env {
  LICENSES: KVNamespace;
  COMMUNITY?: KVNamespace;
  GUMROAD_SECRET: string;
  REVOKE_SECRET: string;
  GUMROAD_CLIENT_ID?: string;
  GUMROAD_CLIENT_SECRET?: string;
}

interface LicenseRecord {
  key: string;
  deviceId: string;
  activatedAt: string;
  lastValidatedAt: string;
  revoked: boolean;
  email?: string;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Content-Type": "application/json",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: CORS_HEADERS,
  });
}

function normalizeKey(key: string): string {
  return key.trim().toUpperCase().replace(/[^A-Z0-9\-]/g, "");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/activate" && request.method === "POST") {
      return handleActivate(request, env);
    }
    if (url.pathname === "/validate" && request.method === "POST") {
      return handleValidate(request, env);
    }
    if (url.pathname === "/revoke" && request.method === "POST") {
      return handleRevoke(request, env);
    }
    if (url.pathname === "/health" && request.method === "GET") {
      return json({ status: "ok", ts: new Date().toISOString() });
    }

    // Gumroad OAuth setup endpoints (temporary, used once to create the product)
    if (url.pathname === "/oauth/callback" && request.method === "GET") {
      return handleOAuthCallback(url, env);
    }
    if (url.pathname === "/oauth/create-product" && request.method === "POST") {
      return handleCreateProduct(request, env);
    }
    if (url.pathname === "/oauth/update-product" && request.method === "POST") {
      return handleUpdateProduct(request, env);
    }
    if (url.pathname === "/oauth/list-products" && request.method === "GET") {
      return handleListProducts(env);
    }
    if (url.pathname === "/oauth/republish" && request.method === "POST") {
      return handleRepublish(env);
    }

    // Community endpoints
    if (url.pathname === "/submit-unknown" && request.method === "POST") {
      return handleSubmitUnknown(request, env);
    }
    if (url.pathname === "/share" && request.method === "POST") {
      return handleCreateShare(request, env);
    }
    if (url.pathname.startsWith("/share/") && request.method === "GET") {
      const shareId = url.pathname.slice(7);
      const accept = request.headers.get("Accept") ?? "";
      if (accept.includes("text/html")) {
        return handleViewShare(shareId, env);
      }
      return handleGetShare(shareId, env);
    }
    if (url.pathname.startsWith("/view/") && request.method === "GET") {
      const shareId = url.pathname.slice(6);
      return handleViewShare(shareId, env);
    }
    if (url.pathname === "/feedback" && request.method === "POST") {
      return handleFeedback(request, env);
    }

    return json({ error: "Not found" }, 404);
  },
};

async function handleActivate(request: Request, env: Env): Promise<Response> {
  let body: { licenseKey?: string; deviceId?: string; email?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const { licenseKey, deviceId, email } = body;
  if (!licenseKey || !deviceId) {
    return json({ error: "licenseKey and deviceId are required" }, 400);
  }

  const key = normalizeKey(licenseKey);
  if (key.length < 8) {
    return json({ error: "Invalid license key format" }, 400);
  }

  // Check if already activated for a DIFFERENT device
  const existing = await env.LICENSES.get(key, { type: "json" }) as LicenseRecord | null;

  if (existing) {
    if (existing.revoked) {
      return json({ error: "License has been revoked", valid: false }, 403);
    }
    if (existing.deviceId !== deviceId) {
      return json({
        error: "License already activated on another device",
        valid: false,
      }, 409);
    }
    // Same device — refresh
    const updated: LicenseRecord = {
      ...existing,
      lastValidatedAt: new Date().toISOString(),
    };
    await env.LICENSES.put(key, JSON.stringify(updated));
    return json({ valid: true, activated: true, email: existing.email });
  }

  // New activation — verify against Gumroad if secret configured
  if (env.GUMROAD_SECRET) {
    const valid = await verifyGumroad(key, env.GUMROAD_SECRET);
    if (!valid) {
      return json({ error: "License key not found or invalid", valid: false }, 402);
    }
  }

  const record: LicenseRecord = {
    key,
    deviceId,
    activatedAt: new Date().toISOString(),
    lastValidatedAt: new Date().toISOString(),
    revoked: false,
    email: email ?? undefined,
  };

  await env.LICENSES.put(key, JSON.stringify(record));
  return json({ valid: true, activated: true, email });
}

async function handleValidate(request: Request, env: Env): Promise<Response> {
  let body: { licenseKey?: string; deviceId?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const { licenseKey, deviceId } = body;
  if (!licenseKey || !deviceId) {
    return json({ error: "licenseKey and deviceId are required" }, 400);
  }

  const key = normalizeKey(licenseKey);
  const record = await env.LICENSES.get(key, { type: "json" }) as LicenseRecord | null;

  if (!record) {
    return json({ valid: false, error: "License not found" }, 404);
  }
  if (record.revoked) {
    return json({ valid: false, error: "License revoked" }, 403);
  }
  if (record.deviceId !== deviceId) {
    return json({ valid: false, error: "Device mismatch" }, 403);
  }

  // Update last validated timestamp
  const updated: LicenseRecord = {
    ...record,
    lastValidatedAt: new Date().toISOString(),
  };
  await env.LICENSES.put(key, JSON.stringify(updated));

  return json({ valid: true, email: record.email });
}

async function handleRevoke(request: Request, env: Env): Promise<Response> {
  // Require Authorization: Bearer <REVOKE_SECRET>
  const auth = request.headers.get("Authorization") ?? "";
  if (!env.REVOKE_SECRET || auth !== `Bearer ${env.REVOKE_SECRET}`) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { licenseKey?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const { licenseKey } = body;
  if (!licenseKey) {
    return json({ error: "licenseKey is required" }, 400);
  }

  const key = normalizeKey(licenseKey);
  const record = await env.LICENSES.get(key, { type: "json" }) as LicenseRecord | null;

  if (!record) {
    return json({ error: "License not found" }, 404);
  }

  const revoked: LicenseRecord = { ...record, revoked: true };
  await env.LICENSES.put(key, JSON.stringify(revoked));

  return json({ revoked: true, key });
}

// ─── Community: Submit Unknown Pattern ────────────────────────────────────────

interface UnknownSubmission {
  id: string;
  submittedAt: string;
  category: string;
  osVersion: string;
  deviceModel: string;
  panicKeywords: string[];
  rawSnippet?: string;  // first 500 chars of panic string, anonymized
  confidence: number;
}

async function handleSubmitUnknown(request: Request, env: Env): Promise<Response> {
  if (!env.COMMUNITY) return json({ error: "Community features not configured" }, 503);

  let body: Partial<UnknownSubmission>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { category, osVersion, deviceModel, panicKeywords, rawSnippet, confidence } = body;
  if (!category || !osVersion) return json({ error: "category and osVersion required" }, 400);

  const id = crypto.randomUUID();
  const record: UnknownSubmission = {
    id,
    submittedAt: new Date().toISOString(),
    category: String(category),
    osVersion: String(osVersion),
    deviceModel: String(deviceModel ?? "unknown"),
    panicKeywords: Array.isArray(panicKeywords) ? panicKeywords.slice(0, 20) : [],
    rawSnippet: typeof rawSnippet === "string" ? rawSnippet.slice(0, 500) : undefined,
    confidence: Number(confidence ?? 0),
  };

  // Store with 90-day TTL; list under "unknown:{id}"
  await env.COMMUNITY.put(`unknown:${id}`, JSON.stringify(record), {
    expirationTtl: 60 * 60 * 24 * 90,
  });

  return json({ submitted: true, id });
}

// ─── Community: Share Link ─────────────────────────────────────────────────────

interface ShareRecord {
  id: string;
  createdAt: string;
  mode: "full" | "diagnosisOnly";
  data: Record<string, unknown>;
}

async function handleCreateShare(request: Request, env: Env): Promise<Response> {
  if (!env.COMMUNITY) return json({ error: "Community features not configured" }, 503);

  let body: { mode?: string; data?: Record<string, unknown> };
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { mode, data } = body;
  if (!mode || !data) return json({ error: "mode and data required" }, 400);
  if (mode !== "full" && mode !== "diagnosisOnly") {
    return json({ error: "mode must be 'full' or 'diagnosisOnly'" }, 400);
  }

  const id = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
  const record: ShareRecord = {
    id,
    createdAt: new Date().toISOString(),
    mode: mode as "full" | "diagnosisOnly",
    data,
  };

  // 30-day TTL
  await env.COMMUNITY.put(`share:${id}`, JSON.stringify(record), {
    expirationTtl: 60 * 60 * 24 * 30,
  });

  return json({ id, url: `https://icrashdiag-license.sam-muselet.workers.dev/share/${id}` });
}

async function handleViewShare(shareId: string, env: Env): Promise<Response> {
  if (!env.COMMUNITY) {
    return new Response("<h1>Community features not configured</h1>", { status: 503, headers: { "Content-Type": "text/html" } });
  }
  if (!/^[a-f0-9]{12}$/.test(shareId)) {
    return new Response(sharePageHtml("Invalid link", null), { status: 400, headers: { "Content-Type": "text/html" } });
  }
  const raw = await env.COMMUNITY.get(`share:${shareId}`);
  if (!raw) {
    return new Response(sharePageHtml("Link not found or expired", null), { status: 404, headers: { "Content-Type": "text/html" } });
  }
  const record = JSON.parse(raw) as ShareRecord;
  return new Response(sharePageHtml(null, record), { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function sharePageHtml(error: string | null, record: ShareRecord | null): string {
  const d = record?.data as Record<string, unknown> | undefined;
  const diag = d?.diagnosis as Record<string, unknown> | undefined;
  const probabilities = (diag?.probabilities as Array<{cause: string; percent: number}>) ?? [];
  const repairSteps = (diag?.repairSteps as string[]) ?? [];
  const isHardwareSev = diag?.severity === "hardware" || diag?.severity === "critical";

  const body = error
    ? `<div class="card"><p class="error">${error}</p><p class="sub">This link may have expired (links are valid for 30 days).</p></div>`
    : `
    <div class="card">
      <div class="badge ${record!.mode === 'full' ? 'badge-full' : 'badge-diag'}">
        ${record!.mode === 'full' ? '📄 Full data' : '🔒 Diagnosis only'}
      </div>

      ${diag ? `
      <div class="verdict ${isHardwareSev ? 'verdict-hw' : 'verdict-sw'}">
        <span class="verdict-icon">${isHardwareSev ? '🔧' : '✅'}</span>
        <div>
          <div class="verdict-title">${diag.title as string}</div>
          <div class="verdict-sub">${diag.component as string} · ${diag.confidencePercent as number}% confidence · ${(diag.severity as string).toUpperCase()}</div>
        </div>
      </div>

      ${probabilities.length > 0 ? `
      <div class="section-title">Probable causes</div>
      ${probabilities.map(p => `
        <div class="prob-row">
          <div class="prob-bar-wrap"><div class="prob-bar" style="width:${p.percent}%"></div></div>
          <span class="prob-pct">${p.percent}%</span>
          <span class="prob-label">${p.cause}</span>
        </div>`).join('')}` : ''}

      ${repairSteps.length > 0 ? `
      <div class="section-title" style="margin-top:20px">Repair steps</div>
      <ol class="repair-list">${repairSteps.map(s => `<li>${s}</li>`).join('')}</ol>` : ''}
      ` : '<p class="sub">No diagnosis available for this crash.</p>'}

      <div class="meta">
        Category: <b>${d?.category as string ?? '—'}</b> ·
        iOS: <b>${d?.osVersion as string ?? '—'}</b> ·
        Device: <b>${(d?.deviceModel ?? d?.deviceFamily) as string ?? '—'}</b>
        ${record!.mode === 'full' && d?.panicString ? `<details><summary>Raw panic string</summary><pre>${(d.panicString as string).slice(0, 800)}</pre></details>` : ''}
      </div>
    </div>
    <div class="footer">
      Shared via <a href="https://icrashdiag.pages.dev">iCrashDiag</a> · iPhone crash log analyzer for macOS
      · Link expires 30 days after creation
    </div>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>${diag ? `${diag.title as string} — iCrashDiag` : 'iCrashDiag Shared Report'}</title>
  <meta property="og:title" content="${diag ? diag.title as string : 'iPhone Crash Report'}"/>
  <meta property="og:description" content="${diag ? `${diag.confidencePercent as number}% confidence · ${diag.component as string}` : 'Shared via iCrashDiag'}"/>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0a0c10;color:#e2e8f0;min-height:100vh;padding:24px 16px}
    .wrap{max-width:600px;margin:0 auto}
    .logo{display:flex;align-items:center;gap:10px;margin-bottom:24px;color:#f97316;font-weight:700;font-size:18px}
    .card{background:#111318;border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:24px;margin-bottom:16px}
    .badge{display:inline-block;font-size:12px;padding:3px 10px;border-radius:20px;margin-bottom:16px;font-weight:600}
    .badge-full{background:rgba(99,102,241,.15);color:#a5b4fc}
    .badge-diag{background:rgba(249,115,22,.12);color:#fb923c}
    .verdict{display:flex;align-items:flex-start;gap:14px;padding:14px;border-radius:10px;margin-bottom:18px}
    .verdict-hw{background:rgba(249,115,22,.1);border:1px solid rgba(249,115,22,.25)}
    .verdict-sw{background:rgba(34,197,94,.08);border:1px solid rgba(34,197,94,.2)}
    .verdict-icon{font-size:24px;flex-shrink:0;margin-top:2px}
    .verdict-title{font-size:16px;font-weight:700;margin-bottom:3px}
    .verdict-sub{font-size:12px;color:#94a3b8}
    .section-title{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#64748b;margin:16px 0 8px}
    .prob-row{display:flex;align-items:center;gap:8px;margin-bottom:6px;font-size:13px}
    .prob-bar-wrap{width:80px;height:4px;background:rgba(255,255,255,.08);border-radius:2px;flex-shrink:0}
    .prob-bar{height:4px;background:#f97316;border-radius:2px}
    .prob-pct{width:32px;text-align:right;color:#94a3b8;font-size:12px;font-variant-numeric:tabular-nums;flex-shrink:0}
    .prob-label{color:#cbd5e1}
    .repair-list{padding-left:20px;color:#cbd5e1;font-size:13px;line-height:1.7}
    .meta{font-size:12px;color:#64748b;margin-top:20px;padding-top:14px;border-top:1px solid rgba(255,255,255,.06);line-height:1.8}
    .meta details{margin-top:8px}
    .meta summary{cursor:pointer;color:#94a3b8}
    .meta pre{margin-top:8px;background:#0d0f14;padding:10px;border-radius:6px;font-size:11px;overflow-x:auto;white-space:pre-wrap;color:#94a3b8;border:1px solid rgba(255,255,255,.06)}
    .error{color:#f87171;font-weight:600;font-size:16px;margin-bottom:8px}
    .sub{color:#64748b;font-size:13px}
    .footer{text-align:center;font-size:12px;color:#334155;padding:8px 0 24px}
    .footer a{color:#f97316;text-decoration:none}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="logo">🩺 iCrashDiag</div>
    ${body}
  </div>
</body>
</html>`;
}

async function handleGetShare(shareId: string, env: Env): Promise<Response> {
  if (!env.COMMUNITY) return json({ error: "Community features not configured" }, 503);

  if (!/^[a-f0-9]{12}$/.test(shareId)) return json({ error: "Invalid share ID" }, 400);

  const raw = await env.COMMUNITY.get(`share:${shareId}`);
  if (!raw) return json({ error: "Share not found or expired" }, 404);

  const record = JSON.parse(raw) as ShareRecord;
  return json(record);
}

// ─── Community: Feedback ───────────────────────────────────────────────────────

async function handleFeedback(request: Request, env: Env): Promise<Response> {
  if (!env.COMMUNITY) return json({ error: "Community features not configured" }, 503);

  let body: { patternId?: string; helpful?: boolean; osVersion?: string; deviceModel?: string };
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { patternId, helpful, osVersion, deviceModel } = body;
  if (!patternId || typeof helpful !== "boolean") {
    return json({ error: "patternId and helpful (boolean) required" }, 400);
  }

  // Aggregate tally: read existing record and increment
  const tallyKey = `feedback:${patternId}`;
  const existing = await env.COMMUNITY.get(tallyKey, { type: "json" }) as
    { helpful: number; notHelpful: number } | null;

  const tally = existing ?? { helpful: 0, notHelpful: 0 };
  if (helpful) tally.helpful++; else tally.notHelpful++;

  await env.COMMUNITY.put(tallyKey, JSON.stringify(tally));

  // Also store individual submission for analysis (60-day TTL)
  const fbId = crypto.randomUUID();
  await env.COMMUNITY.put(`fb:${patternId}:${fbId}`, JSON.stringify({
    helpful, osVersion, deviceModel, ts: new Date().toISOString(),
  }), { expirationTtl: 60 * 60 * 24 * 60 });

  return json({ received: true, tally });
}

// ─── Gumroad OAuth Setup (one-time product creation) ─────────────────────────

async function exchangeCodeForToken(code: string, clientId: string, clientSecret: string): Promise<string | null> {
  const REDIRECT_URI = "https://icrashdiag-license.sam-muselet.workers.dev/oauth/callback";
  const res = await fetch("https://api.gumroad.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, client_id: clientId, client_secret: clientSecret, redirect_uri: REDIRECT_URI, grant_type: "authorization_code" }),
  });
  const raw = await res.text();
  try {
    const data = JSON.parse(raw) as { access_token?: string };
    return data.access_token ?? null;
  } catch { return null; }
}

async function handleOAuthCallback(url: URL, env: Env): Promise<Response> {
  const code = url.searchParams.get("code");
  const error = url.searchParams.get("error");

  if (error || !code) {
    return new Response(setupPage("❌ Authorization failed", `Error: ${error ?? "no code received"}`), {
      headers: { "Content-Type": "text/html" },
    });
  }

  // Try to immediately exchange code for token if credentials are available
  if (env.GUMROAD_CLIENT_ID && env.GUMROAD_CLIENT_SECRET) {
    const token = await exchangeCodeForToken(code, env.GUMROAD_CLIENT_ID, env.GUMROAD_CLIENT_SECRET);
    if (token) {
      // Save token permanently — no more OAuth needed
      await env.LICENSES.put("__gumroad_token__", token);
      return new Response(setupPage("✅ Authorized & token saved", `
        <p>Access token saved permanently. You can now call <code>/oauth/update-product</code> anytime without re-authorizing.</p>
        <pre>curl -X POST https://icrashdiag-license.sam-muselet.workers.dev/oauth/update-product \\
  -H "Content-Type: application/json" -d '{}'</pre>
      `), { headers: { "Content-Type": "text/html" } });
    }
  }

  // Fallback: store code with 5-minute TTL
  await env.LICENSES.put("__oauth_code__", code, { expirationTtl: 300 });
  return new Response(setupPage("✅ Authorization received", `
    <p>Code stored (valid 5 min). Call <code>/oauth/update-product</code> now.</p>
  `), { headers: { "Content-Type": "text/html" } });
}

async function handleCreateProduct(request: Request, env: Env): Promise<Response> {
  let body: { client_id?: string; client_secret?: string };
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const clientId     = body.client_id     ?? env.GUMROAD_CLIENT_ID;
  const clientSecret = body.client_secret ?? env.GUMROAD_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    return json({ error: "client_id and client_secret required" }, 400);
  }

  // Retrieve stored OAuth code
  const code = await env.LICENSES.get("__oauth_code__");
  if (!code) {
    return json({ error: "No OAuth code found. Complete the authorization flow first by visiting the Gumroad authorize URL." }, 400);
  }

  const REDIRECT_URI = "https://icrashdiag-license.sam-muselet.workers.dev/oauth/callback";

  // Exchange code for access token
  const tokenRes = await fetch("https://api.gumroad.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id:     clientId,
      client_secret: clientSecret,
      redirect_uri:  REDIRECT_URI,
      grant_type:    "authorization_code",
    }),
  });

  const tokenData = await tokenRes.json() as { access_token?: string; error?: string };
  if (!tokenData.access_token) {
    return json({ error: "Token exchange failed", detail: tokenData }, 400);
  }

  const token = tokenData.access_token;

  // Delete used code
  await env.LICENSES.delete("__oauth_code__");

  // Create the product
  const productRes = await fetch("https://api.gumroad.com/v2/products", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      name:              "iCrashDiag Pro",
      price:             "999",
      description:       "iPhone crash log analyzer for macOS. 267-pattern offline knowledge base. Unlimited logs, PDF/Markdown export, crash share links. No subscription — one-time payment.",
      custom_permalink:  "icrashdiag",
      published:         "false",
    }),
  });

  const productData = await productRes.json() as { success?: boolean; product?: Record<string, unknown>; message?: string };

  if (productRes.status === 404) {
    // Endpoint not yet live for this account — return token so user can try manually
    return json({
      warning: "POST /v2/products returned 404 — endpoint may not be enabled yet for your account.",
      access_token: token,
      next: "Create product at https://gumroad.com/products/new then run: node gumroad-update-urls.js YOUR_URL",
    });
  }

  if (!productData.success) {
    return json({ error: "Product creation failed", detail: productData }, 400);
  }

  const product = productData.product!;
  const permalink = (product.short_url ?? product.url ?? "https://ateliersam.gumroad.com/l/icrashdiag") as string;

  return json({
    success: true,
    product_id: product.id,
    name: product.name,
    permalink,
    next: `Run this to inject the URL into your codebase:\n  node gumroad-update-urls.js "${permalink}"`,
  });
}

const GUMROAD_DESCRIPTION = `<p><strong>iCrashDiag</strong> reads your iPhone crash logs (.ips files) and tells you exactly what broke — hardware failure, memory pressure, watchdog timeout, or app crash — in plain English.</p>

<p>Drop a crash log. Get a verdict in seconds. No internet required, no data ever leaves your Mac.</p>

<hr>

<h2>✅ What you get with Pro</h2>
<ul>
  <li><strong>Unlimited crash logs</strong> — analyze as many files as you want (free tier: 10 files)</li>
  <li><strong>267-pattern offline knowledge base</strong> — kernel panics, jetsam, watchdog, NAND failures, and more</li>
  <li><strong>Export to PDF &amp; Markdown</strong> — share reports with clients or your repair shop</li>
  <li><strong>Crash share links</strong> — generate a shareable link with diagnosis or full data</li>
  <li><strong>Session history</strong> — all your past analyses, searchable and persistent</li>
  <li><strong>macOS native</strong> — built with SwiftUI, runs on Apple Silicon and Intel</li>
</ul>

<hr>

<h2>🔧 Who is this for?</h2>
<ul>
  <li>iOS repair technicians who need to understand what failed before opening a device</li>
  <li>Apple device resellers evaluating iPhone condition</li>
  <li>iOS developers debugging crashes in the field</li>
  <li>Power users who want to understand why their iPhone crashed</li>
</ul>

<hr>

<h2>🔒 Privacy first</h2>
<p>100% offline analysis. No account required. No telemetry. Your crash logs never leave your Mac.</p>

<hr>

<p><em>One-time payment · No subscription · 30-day money-back guarantee</em></p>`;

async function handleRepublish(env: Env): Promise<Response> {
  const token = await env.LICENSES.get("__gumroad_token__");
  if (!token) return json({ error: "No token saved. Authorize first." }, 400);

  const steps: string[] = [];

  // Step 1: Delete the draft product
  const deleteRes = await fetch("https://api.gumroad.com/v2/products/C9Ji8b_NlmTXmW6yThyM_A==", {
    method: "DELETE",
    headers: { "Authorization": `Bearer ${token}` },
  });
  steps.push(`DELETE status: ${deleteRes.status}`);

  // Step 2: Create a new published product
  const params = new URLSearchParams();
  params.append("name", "iCrashDiag Pro");
  params.append("price", "999");
  params.append("description", GUMROAD_DESCRIPTION);
  params.append("custom_permalink", "icrashdiag");
  params.append("published", "true");

  const createRes = await fetch("https://api.gumroad.com/v2/products", {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  const raw = await createRes.text();
  steps.push(`POST status: ${createRes.status}`);

  let data: { success?: boolean; product?: Record<string, unknown>; message?: string };
  try { data = JSON.parse(raw); } catch { return json({ error: "Not JSON", raw: raw.slice(0, 200), steps }, 400); }

  if (!data.success) return json({ error: "Product creation failed", detail: data, steps }, 400);
  return json({ success: true, steps, product: data.product });
}

async function handleListProducts(env: Env): Promise<Response> {
  const token = await env.LICENSES.get("__gumroad_token__");
  if (!token) return json({ error: "No token saved. Authorize first." }, 400);
  const res = await fetch("https://api.gumroad.com/v2/products", {
    headers: { "Authorization": `Bearer ${token}` },
  });
  const raw = await res.text();
  try {
    const data = JSON.parse(raw) as { products?: Array<{ id: string; name: string; short_url: string; published: boolean }> };
    return json({ products: data.products ?? [] });
  } catch { return json({ error: "Not JSON", raw: raw.slice(0, 300) }, 400); }
}

async function handleUpdateProduct(request: Request, env: Env): Promise<Response> {
  try {
    let body: { client_id?: string; client_secret?: string };
    try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

    const clientId     = body.client_id     ?? env.GUMROAD_CLIENT_ID;
    const clientSecret = body.client_secret ?? env.GUMROAD_CLIENT_SECRET;
    if (!clientId || !clientSecret) return json({ error: "client_id and client_secret required" }, 400);

    // Use saved token if available, otherwise exchange code
    let token = await env.LICENSES.get("__gumroad_token__");
    if (!token) {
      const code = await env.LICENSES.get("__oauth_code__");
      if (!code) return json({ error: "No token or OAuth code found. Authorize at /oauth/authorize first." }, 400);
      const exchanged = await exchangeCodeForToken(code, clientId!, clientSecret!);
      if (!exchanged) return json({ error: "Token exchange failed" }, 400);
      token = exchanged;
      await env.LICENSES.put("__gumroad_token__", token);
      await env.LICENSES.delete("__oauth_code__");
    }

    // Try multiple ID formats for Gumroad PUT
    const productId = "C9Ji8b_NlmTXmW6yThyM_A==";
    const params = new URLSearchParams();
    params.append("name", "iCrashDiag Pro");
    params.append("price", "999");
    params.append("description", GUMROAD_DESCRIPTION);
    params.append("published", "true");
    params.append("access_token", token);

    // Try 1: raw ID
    // Try 2: encoded ID
    // Try 3: permalink slug
    const candidates = [
      `https://api.gumroad.com/v2/products/${productId}`,
      `https://api.gumroad.com/v2/products/${encodeURIComponent(productId)}`,
      `https://api.gumroad.com/v2/products/icrashdiag`,
    ];

    const results: Array<{ url: string; status: number; body: string }> = [];
    for (const url of candidates) {
      const r = await fetch(url, {
        method: "PUT",
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: params.toString(),
      });
      const raw = await r.text();
      results.push({ url, status: r.status, body: raw.slice(0, 200) });
      if (r.status === 200) {
        let d: { success?: boolean; product?: Record<string, unknown> };
        try { d = JSON.parse(raw); } catch { continue; }
        if (d.success) return json({ success: true, product: d.product });
      }
    }
    return json({ error: "All PUT attempts failed", results });
  } catch (e: unknown) {
    return json({ error: "Worker exception", message: (e as Error).message }, 500);
  }
}

function setupPage(title: string, body: string): string {
  return `<!DOCTYPE html><html><head><meta charset="UTF-8"/><title>${title}</title>
  <style>body{font-family:-apple-system,sans-serif;background:#0a0c10;color:#e2e8f0;padding:40px;max-width:700px;margin:0 auto}
  h2{color:#F97316}pre{background:#111318;border:1px solid rgba(255,255,255,.1);padding:16px;border-radius:8px;overflow-x:auto;font-size:13px;color:#94a3b8}</style>
  </head><body><h2>${title}</h2>${body}</body></html>`;
}

// ─── Gumroad ──────────────────────────────────────────────────────────────────

async function verifyGumroad(licenseKey: string, productPermalink: string): Promise<boolean> {
  try {
    const resp = await fetch("https://api.gumroad.com/v2/licenses/verify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        product_permalink: productPermalink,
        license_key: licenseKey,
      }),
    });
    const data = await resp.json() as { success?: boolean };
    return data.success === true;
  } catch {
    // If Gumroad is unreachable, allow activation (fail open)
    return true;
  }
}
