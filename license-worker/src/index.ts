export interface Env {
  LICENSES: KVNamespace;
  GUMROAD_SECRET: string;
  REVOKE_SECRET: string;
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
