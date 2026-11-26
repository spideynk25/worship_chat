#!/usr/bin/env node
/**
 * Fetches recent crash, error, and performance reports from Firestore
 * `diagnostics_reports` using the local notify Firebase Admin SDK & key.
 *
 * Usage:
 *   node scripts/fetch_diagnostics.js [--limit 20] [--unresolved] [--kind crash|performance|error]
 */
const path = require("path");

const admin = require(path.resolve(
  __dirname,
  "../../notify/node_modules/firebase-admin"
));
const serviceAccount = require(path.resolve(
  __dirname,
  "../../notify/serviceAccountKey.json"
));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

function parseArg(flag, fallback = null) {
  const idx = process.argv.indexOf(flag);
  if (idx >= 0 && idx + 1 < process.argv.length) {
    return process.argv[idx + 1];
  }
  return fallback;
}

async function main() {
  const limit = Number(parseArg("--limit", "25")) || 25;
  const onlyUnresolved = process.argv.includes("--unresolved");
  const filterKind = parseArg("--kind");

  let query = admin
    .firestore()
    .collection("diagnostics_reports")
    .orderBy("timestampMs", "desc")
    .limit(limit);

  const snap = await query.get();
  const rows = snap.docs
    .map((d) => d.data())
    .filter((r) => {
      if (onlyUnresolved && r.isResolved === true) return false;
      if (filterKind && r.kind !== filterKind) return false;
      return true;
    });

  if (rows.length === 0) {
    console.log("No matching diagnostic reports found in Firestore.");
    return;
  }

  console.log(`Found ${rows.length} report(s):\n`);
  for (const r of rows) {
    console.log(
      `[${String(r.kind || "error").toUpperCase()}] ${r.title || "Untitled"} (${r.appVersion || "?"} / ${r.platform || "?"})`
    );
    console.log(
      `  ID: ${r.id} | Time: ${r.timestampIso || r.timestampMs} | Route: ${r.routeName || "-"} | Resolved: ${Boolean(r.isResolved)}`
    );
    if (r.message) console.log(`  Message: ${r.message}`);
    if (r.metrics && Object.keys(r.metrics).length > 0) {
      console.log(`  Metrics: ${JSON.stringify(r.metrics)}`);
    }
    if (r.stackTrace) {
      const preview = String(r.stackTrace).split("\n").slice(0, 6).join("\n    ");
      console.log(`  Stack:\n    ${preview}`);
    }
    console.log("");
  }
}

main().catch((err) => {
  console.error("Failed to fetch diagnostics:", err);
  process.exit(1);
});
