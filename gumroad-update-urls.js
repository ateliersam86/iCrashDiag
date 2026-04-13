#!/usr/bin/env node
/**
 * Injects your Gumroad product URL into all 4 places in the codebase.
 *
 * Usage:
 *   node gumroad-update-urls.js https://yourname.gumroad.com/l/icrashdiag
 */

const fs = require("fs");
const path = require("path");

const newURL = process.argv[2];
if (!newURL || !newURL.includes("gumroad.com")) {
  console.error("Usage: node gumroad-update-urls.js https://yourname.gumroad.com/l/icrashdiag");
  process.exit(1);
}

const PLACEHOLDER = "https://ateliersam.gumroad.com/l/icrashdiag";

const FILES = [
  "iCrashDiag/Views/License/LicenseGateView.swift",
  "iCrashDiag/Views/Settings/SettingsView.swift",
  "website/index.html",
];

let totalReplaced = 0;

for (const relPath of FILES) {
  const filePath = path.join(__dirname, relPath);
  if (!fs.existsSync(filePath)) {
    console.log(`⚠️  Not found: ${relPath}`);
    continue;
  }
  const before = fs.readFileSync(filePath, "utf8");
  const after = before.split(PLACEHOLDER).join(newURL);
  const count = (before.match(new RegExp(PLACEHOLDER.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g")) || []).length;

  if (count > 0) {
    fs.writeFileSync(filePath, after, "utf8");
    console.log(`✓  ${relPath} — ${count} replacement(s)`);
    totalReplaced += count;
  } else {
    console.log(`—  ${relPath} — already up to date`);
  }
}

console.log(`\n✅  Done. ${totalReplaced} total replacement(s).`);
console.log(`   Gumroad URL: ${newURL}`);
console.log("\nNext: swift build — then deploy your worker + publish the Gumroad product.");
