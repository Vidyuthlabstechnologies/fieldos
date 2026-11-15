// The public API's routing and error mapping, kept apart from Deno.serve so
// it can be tested without a server or a database.

export type ApiRead = (args: {
  p_key: string;
  p_resource: string;
  p_project: string | null;
  p_id: string | null;
  p_after: string | null;
  p_limit: number;
}) => Promise<{ data: unknown; error: { message: string } | null }>;

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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type Route =
  | { kind: "index" }
  | { kind: "list"; resource: string; id: string | null }
  | { kind: "error"; status: number; code: string };

/** Everything after ".../public-api/v1". */
export function route(pathname: string): Route {
  const m = /\/public-api\/v1(\/.*)?$/.exec(pathname);
  if (!m) return { kind: "error", status: 404, code: "not_found" };
  const parts = (m[1] ?? "").split("/").filter(Boolean);
  if (parts.length === 0) return { kind: "index" };
  const resource = parts[0];
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
  rate_limited: 429,
  not_found: 404,
  unknown_resource: 404,
  bad_cursor: 400,
};

function problem(status: number, code: string): Response {
  const message: Record<string, string> = {
    invalid_key:
      "Send a FieldOS API key as 'Authorization: Bearer fos_...'. Owners make keys in the app under Settings, API keys.",
    rate_limited: "120 calls a minute per key. Wait a minute and try again.",
    not_found: "Nothing here for this key.",
    unknown_resource: `Resources: ${RESOURCES.join(", ")}, changes.`,
    bad_cursor: "'after' is the 'next' value from the previous page.",
    bad_request: "Check the query parameters.",
    method: "The API is read only: GET.",
  };
  return Response.json({ error: code, message: message[code] ?? code }, {
    status,
    headers: status === 429 ? { "retry-after": "60" } : {},
  });
}

export async function handle(req: Request, read: ApiRead): Promise<Response> {
  if (req.method !== "GET") return problem(405, "method");
  const url = new URL(req.url);
  const r = route(url.pathname);
  if (r.kind === "error") return problem(r.status, r.code);
  const key = keyOf(req.headers);
  if (!key) return problem(401, "invalid_key");
  if (r.kind === "index") {
    // Checks the key too, so a client can test it here.
    const { error } = await read({
      p_key: key,
      p_resource: "projects",
      p_project: null,
      p_id: null,
      p_after: null,
      p_limit: 1,
    });
    if (error) return fromError(error.message);
    return Response.json({
      resources: [...RESOURCES, "changes"],
      docs: "https://github.com/Vidyuthlabstechnologies/fieldos/blob/master/docs/OPEN_API.md",
    });
  }
  const project = url.searchParams.get("project_id");
  if (project !== null && !UUID.test(project)) return problem(400, "bad_request");
  const limitText = url.searchParams.get("limit");
  const limit = limitText === null ? 100 : Number(limitText);
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) return problem(400, "bad_request");
  const { data, error } = await read({
    p_key: key,
    p_resource: r.resource,
    p_project: project?.toLowerCase() ?? null,
    p_id: r.id,
    p_after: url.searchParams.get("after"),
    p_limit: limit,
  });
  if (error) return fromError(error.message);
  const body = data as { data: unknown[]; next: string | null };
  if (r.id) return Response.json({ data: body.data[0] ?? null });
  return Response.json(body);
}

function fromError(message: string): Response {
  const code = Object.keys(STATUS).find((c) => message.includes(c));
  if (code) return problem(STATUS[code], code);
  console.error("public-api read failed", message);
  return Response.json({ error: "server_error", message: "Something went wrong on our side. Try again." }, {
    status: 500,
  });
}
