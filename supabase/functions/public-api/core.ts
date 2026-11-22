// The public API's routing and error mapping, kept apart from Deno.serve so
// it can be tested without a server or a database.

import { OPENAPI } from "./openapi.ts";

/** One call of a SQL function as the service role (supabase-js rpc). */
export type Rpc = (
  fn: "api_read" | "api_write" | "api_webhooks",
  args: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message: string } | null }>;

export const RESOURCES = [
  "projects",
  "tasks",
  "issues",
  "daily_reports",
  "inspections",
  "approvals",
  "rfis",
  "submittals",
  "defects",
  "drawings",
  "drawing_revisions",
  "hold_points",
  "handover_units",
  "constraints",
  "attendance",
  "material_receipts",
  "purchase_orders",
  "expenses",
  "client_bills",
  "supplier_invoices",
  "payments_received",
] as const;

/** What a key that can write may create (POST) and update (PATCH). */
export const WRITABLE = ["tasks", "issues"] as const;

export const DOCS = "https://github.com/Vidyuthlabstechnologies/fieldos/blob/master/docs/OPEN_API.md";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Writes are small JSON objects; anything bigger is a mistake or abuse.
const MAX_BODY = 32 * 1024;

export type Route =
  | { kind: "index" }
  | { kind: "openapi" }
  | { kind: "list"; resource: string; id: string | null }
  | { kind: "webhooks"; id: string | null }
  | { kind: "error"; status: number; code: string };

/** Everything after ".../public-api/v1". */
export function route(pathname: string): Route {
  // The bare function URL is the index too, so a probe of it (and the
  // deploy workflow's liveness check) gets 401, not 404.
  if (/\/public-api\/?$/.test(pathname)) return { kind: "index" };
  const m = /\/public-api\/v1(\/.*)?$/.exec(pathname);
  if (!m) return { kind: "error", status: 404, code: "not_found" };
  const parts = (m[1] ?? "").split("/").filter(Boolean);
  if (parts.length === 0) return { kind: "index" };
  const resource = parts[0];
  if (resource === "openapi.json" && parts.length === 1) return { kind: "openapi" };
  if (resource === "webhooks") {
    if (parts.length === 1) return { kind: "webhooks", id: null };
    if (parts.length === 2 && UUID.test(parts[1])) return { kind: "webhooks", id: parts[1].toLowerCase() };
    return { kind: "error", status: 404, code: "not_found" };
  }
  if (resource !== "changes" && !(RESOURCES as readonly string[]).includes(resource)) {
    return { kind: "error", status: 404, code: "unknown_resource" };
  }
  if (parts.length === 1) return { kind: "list", resource, id: null };
  if (parts.length === 2 && resource !== "changes" && UUID.test(parts[1])) {
    return { kind: "list", resource, id: parts[1].toLowerCase() };
  }
  return { kind: "error", status: 404, code: "not_found" };
}

/** The key from "Authorization: Bearer fos_..." or "x-api-key". */
export function keyOf(headers: Headers): string | null {
  const auth = headers.get("authorization") ?? "";
  const m = /^Bearer\s+(fos_[0-9a-f]{48})$/i.exec(auth.trim());
  if (m) return m[1];
  const x = (headers.get("x-api-key") ?? "").trim();
  return /^fos_[0-9a-f]{48}$/i.test(x) ? x : null;
}

const STATUS: Record<string, number> = {
  invalid_key: 401,
  forbidden: 403,
  rate_limited: 429,
  not_found: 404,
  unknown_resource: 404,
  bad_cursor: 400,
  bad_request: 400,
  not_writable: 405,
  idempotency_conflict: 409,
};

const MESSAGE: Record<string, string> = {
  invalid_key:
    "Send a FieldOS API key as 'Authorization: Bearer fos_...'. Owners make keys in the app under Settings, API keys.",
  forbidden: "This key can only read. The owner makes a key that can write in Settings, API keys.",
  rate_limited: "120 calls a minute per key. Wait a minute and try again.",
  not_found: "Nothing here for this key.",
  unknown_resource: `Resources: ${RESOURCES.join(", ")}, changes, webhooks.`,
  bad_cursor: "'after' is the 'next' value from the previous page.",
  bad_request: "Check the query parameters and body.",
  not_writable: `Only ${WRITABLE.join(" and ")} can be created (POST) or changed (PATCH). Nothing can be deleted.`,
  idempotency_conflict: "This Idempotency-Key was already used for a different request.",
  method: "That method is not allowed here.",
  too_large: "The body is over 32 KB.",
};

const BASE_HEADERS = { "x-ratelimit-limit": "120", "cache-control": "no-store" };

function problem(status: number, code: string, message?: string): Response {
  return Response.json({ error: code, message: message ?? MESSAGE[code] ?? code }, {
    status,
    headers: { ...BASE_HEADERS, ...(status === 429 ? { "retry-after": "60" } : {}) },
  });
}

function ok(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: BASE_HEADERS });
}

async function readJson(req: Request): Promise<{ ok: true; body: unknown } | { ok: false; res: Response }> {
  const type = req.headers.get("content-type") ?? "";
  if (!/^application\/json\b/i.test(type)) {
    return { ok: false, res: problem(415, "bad_request", "Send 'Content-Type: application/json'.") };
  }
  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY) return { ok: false, res: problem(413, "too_large") };
  try {
    const body = JSON.parse(text);
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return { ok: false, res: problem(400, "bad_request", "Send a JSON object.") };
    }
    return { ok: true, body };
  } catch {
    return { ok: false, res: problem(400, "bad_request", "The body is not valid JSON.") };
  }
}

export async function handle(req: Request, rpc: Rpc): Promise<Response> {
  const url = new URL(req.url);
  const r = route(url.pathname);
  if (r.kind === "error") return problem(r.status, r.code);
  // The description of the API needs no key, so tools can import it.
  if (r.kind === "openapi") {
    if (req.method !== "GET") return problem(405, "method");
    return Response.json(OPENAPI, { headers: { "cache-control": "public, max-age=3600" } });
  }
  const key = keyOf(req.headers);
  if (!key) return problem(401, "invalid_key");

  if (r.kind === "index") {
    if (req.method !== "GET") return problem(405, "method");
    // Checks the key too, so a client can test it here.
    const { error } = await rpc("api_read", {
      p_key: key,
      p_resource: "projects",
      p_project: null,
      p_id: null,
      p_after: null,
      p_limit: 1,
    });
    if (error) return fromError(error.message);
    return ok({
      resources: [...RESOURCES, "changes"],
      writable: [...WRITABLE],
      webhooks: "/v1/webhooks",
      openapi: "/v1/openapi.json",
      docs: DOCS,
    });
  }

  if (r.kind === "webhooks") {
    if (req.method === "GET" && r.id === null) {
      return answer(await rpc("api_webhooks", { p_key: key, p_action: "list", p_id: null, p_body: {} }));
    }
    if (req.method === "POST" && r.id === null) {
      const b = await readJson(req);
      if (!b.ok) return b.res;
      return answer(await rpc("api_webhooks", { p_key: key, p_action: "create", p_id: null, p_body: b.body }), 201);
    }
    if (req.method === "DELETE" && r.id !== null) {
      return answer(await rpc("api_webhooks", { p_key: key, p_action: "delete", p_id: r.id, p_body: {} }));
    }
    return problem(405, "method");
  }

  if (req.method === "POST" || req.method === "PATCH") {
    if (r.resource === "changes" || !(WRITABLE as readonly string[]).includes(r.resource)) {
      return problem(405, "not_writable");
    }
    if (req.method === "POST" && r.id !== null) {
      return problem(405, "method", "POST to the list to create; PATCH a row.");
    }
    if (req.method === "PATCH" && r.id === null) return problem(405, "method", "PATCH one row: /v1/<resource>/<id>.");
    const idem = req.headers.get("idempotency-key");
    if (idem !== null && (idem.length < 1 || idem.length > 100)) {
      return problem(400, "bad_request", "Idempotency-Key is 1 to 100 characters.");
    }
    const b = await readJson(req);
    if (!b.ok) return b.res;
    return answer(
      await rpc("api_write", {
        p_key: key,
        p_resource: r.resource,
        p_id: r.id,
        p_body: b.body,
        p_idempotency_key: req.method === "POST" ? idem : null,
      }),
      req.method === "POST" ? 201 : 200,
    );
  }
  if (req.method !== "GET") return problem(405, "method");

  const project = url.searchParams.get("project_id");
  if (project !== null && !UUID.test(project)) return problem(400, "bad_request");
  const limitText = url.searchParams.get("limit");
  const limit = limitText === null ? 100 : Number(limitText);
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) return problem(400, "bad_request");
  const { data, error } = await rpc("api_read", {
    p_key: key,
    p_resource: r.resource,
    p_project: project?.toLowerCase() ?? null,
    p_id: r.id,
    p_after: url.searchParams.get("after"),
    p_limit: limit,
  });
  if (error) return fromError(error.message);
  const body = data as { data: unknown[]; next: string | null; error?: string };
  if (body.error) return fromError(body.error);
  if (r.id) return ok({ data: body.data[0] ?? null });
  return ok(body);
}

/** A write or webhook call: {"data": ...} or a counted {"error", "message"}. */
function answer(res: { data: unknown; error: { message: string } | null }, status = 200): Response {
  if (res.error) return fromError(res.error.message);
  const body = res.data as { data?: unknown; error?: string; message?: string };
  if (body?.error) {
    // The SQL functions' own messages are written for the caller (which
    // field, which value); anything not one of our codes is never echoed.
    if (!Object.hasOwn(STATUS, body.error)) return fromError(body.error);
    return problem(STATUS[body.error], body.error, typeof body.message === "string" ? body.message : undefined);
  }
  return ok({ data: body?.data ?? null }, status);
}

function fromError(message: string): Response {
  // Only the exact codes the SQL functions use; any other database message
  // is logged here and never sent back.
  if (Object.hasOwn(STATUS, message)) return problem(STATUS[message], message);
  console.error("public-api call failed", message);
  return Response.json({ error: "server_error", message: "Something went wrong on our side. Try again." }, {
    status: 500,
    headers: BASE_HEADERS,
  });
}
