import { assertEquals } from "@std/assert";

import { handle, keyOf, route, type Rpc } from "./core.ts";
import { OPENAPI } from "./openapi.ts";

const KEY = "fos_" + "ab".repeat(24);
const ID = "0b9f6a52-3c1d-4e8a-9f00-1234567890ab";

Deno.test("routes", () => {
  assertEquals(route("/public-api/v1"), { kind: "index" });
  assertEquals(route("/public-api"), { kind: "index" });
  assertEquals(route("/public-api/"), { kind: "index" });
  assertEquals(route("/functions/v1/public-api/v1/rfis"), { kind: "list", resource: "rfis", id: null });
  assertEquals(route(`/public-api/v1/rfis/${ID.toUpperCase()}`), { kind: "list", resource: "rfis", id: ID });
  assertEquals(route("/public-api/v1/changes"), { kind: "list", resource: "changes", id: null });
  assertEquals(route("/public-api/v1/company_api_keys").kind, "error");
  assertEquals(route("/public-api/v1/rfis/not-a-uuid").kind, "error");
  assertEquals(route(`/public-api/v1/changes/${ID}`).kind, "error");
});

Deno.test("keys from either header, only in the FieldOS shape", () => {
  assertEquals(keyOf(new Headers({ authorization: `Bearer ${KEY}` })), KEY);
  assertEquals(keyOf(new Headers({ "x-api-key": KEY })), KEY);
  assertEquals(keyOf(new Headers({ authorization: "Bearer eyJhbGciOi.x.y" })), null);
  assertEquals(keyOf(new Headers()), null);
});

function reader(answer: { data?: unknown; error?: string }, seen: unknown[] = []): Rpc {
  return (fn, args) => {
    seen.push(fn === "api_read" ? args : { fn, ...args });
    return Promise.resolve({ data: answer.data ?? null, error: answer.error ? { message: answer.error } : null });
  };
}

const auth = { authorization: `Bearer ${KEY}` };
const json = { ...auth, "content-type": "application/json" };

const get = (path: string, headers: Record<string, string> = { authorization: `Bearer ${KEY}` }) =>
  new Request(`http://x/public-api/v1${path}`, { headers });

Deno.test("passes the query through and returns the page", async () => {
  const seen: unknown[] = [];
  const res = await handle(
    get(`/tasks?project_id=${ID}&after=abc&limit=50`),
    reader({ data: { data: [{ id: 1 }], next: null } }, seen),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { data: [{ id: 1 }], next: null });
  assertEquals(seen[0], { p_key: KEY, p_resource: "tasks", p_project: ID, p_id: null, p_after: "abc", p_limit: 50 });
});

Deno.test("one row comes back as an object", async () => {
  const res = await handle(get(`/rfis/${ID}`), reader({ data: { data: [{ id: ID }], next: null } }));
  assertEquals(await res.json(), { data: { id: ID } });
});

Deno.test("errors map to statuses and never leak the database message", async () => {
  const status = async (req: Request, error?: string) => (await handle(req, reader({ error }))).status;
  assertEquals(await status(get("/tasks", {})), 401);
  assertEquals(await status(get("/tasks"), "invalid_key"), 401);
  assertEquals(await status(get("/tasks"), "rate_limited"), 429);
  assertEquals(await status(get(`/tasks/${ID}`), "not_found"), 404);
  assertEquals(await status(get("/tasks?after=x"), "bad_cursor"), 400);
  assertEquals(await status(get("/tasks?limit=0")), 400);
  assertEquals(await status(get("/tasks?limit=501")), 400);
  assertEquals(await status(get("/tasks?project_id=1;drop")), 400);
  assertEquals(await status(get("/secrets")), 404);
  assertEquals(await status(new Request("http://x/public-api/v1/tasks", { method: "DELETE", headers: auth })), 405);
  assertEquals(await status(new Request("http://x/public-api/v1/rfis", { method: "POST", headers: json })), 405);
  // A counted call that found nothing comes back as data.
  assertEquals((await handle(get(`/rfis/${ID}`), reader({ data: { error: "not_found" } }))).status, 404);
  assertEquals((await handle(get("/tasks?after=x"), reader({ data: { error: "bad_cursor" } }))).status, 400);
  // Only exact codes map; anything else is a 500 with no detail.
  assertEquals(await status(get("/tasks"), "invalid_key: or something"), 500);
  const res = await handle(get("/tasks"), reader({ error: 'relation "x" does not exist' }));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).message.includes("relation"), false);
});

Deno.test("more routes: webhooks and the description", () => {
  assertEquals(route("/public-api/v1/openapi.json"), { kind: "openapi" });
  assertEquals(route("/public-api/v1/webhooks"), { kind: "webhooks", id: null });
  assertEquals(route(`/public-api/v1/webhooks/${ID}`), { kind: "webhooks", id: ID });
  assertEquals(route("/public-api/v1/webhooks/x").kind, "error");
});

Deno.test("the OpenAPI description needs no key, and docs/openapi.json is its copy", async () => {
  const res = await handle(new Request("http://x/public-api/v1/openapi.json"), reader({}));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.openapi, "3.1.0");
  assertEquals(Object.keys(body.paths).includes("/v1/tasks/{id}"), true);
  assertEquals(typeof body.paths["/v1/tasks"].post, "object");
  assertEquals(body.paths["/v1/rfis"].post, undefined);
  const copy = await Deno.readTextFile(new URL("../../../docs/openapi.json", import.meta.url));
  assertEquals(JSON.parse(copy), JSON.parse(JSON.stringify(OPENAPI)), "run `deno task openapi`");
});

const send = (method: string, path: string, body: unknown, headers: Record<string, string> = json) =>
  new Request(`http://x/public-api/v1${path}`, {
    method,
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

Deno.test("POST creates through api_write with the idempotency key; PATCH updates one row", async () => {
  const seen: unknown[] = [];
  const row = { id: ID, title: "Footing" };
  let res = await handle(
    send("POST", "/tasks", { project_id: ID, title: "Footing" }, { ...json, "idempotency-key": "abc" }),
    reader({ data: { data: row } }, seen),
  );
  assertEquals(res.status, 201);
  assertEquals(await res.json(), { data: row });
  assertEquals(seen[0], {
    fn: "api_write",
    p_key: KEY,
    p_resource: "tasks",
    p_id: null,
    p_body: { project_id: ID, title: "Footing" },
    p_idempotency_key: "abc",
  });
  res = await handle(send("PATCH", `/issues/${ID}`, { status: "resolved" }), reader({ data: { data: row } }, seen));
  assertEquals(res.status, 200);
  assertEquals((seen[1] as { p_id: string; p_resource: string }).p_id, ID);
  assertEquals((seen[1] as { p_resource: string }).p_resource, "issues");
});

Deno.test("write errors: shape, scope and the SQL function's own message", async () => {
  const status = async (req: Request, answer: { data?: unknown; error?: string } = { data: { data: {} } }) =>
    (await handle(req, reader(answer))).status;
  assertEquals(await status(send("POST", `/tasks/${ID}`, {})), 405);
  assertEquals(await status(send("PATCH", "/tasks", {})), 405);
  assertEquals(await status(send("POST", "/changes", {})), 405);
  assertEquals(await status(send("POST", "/tasks", "[1]")), 400);
  assertEquals(await status(send("POST", "/tasks", "{nope")), 400);
  assertEquals(await status(send("POST", "/tasks", {}, auth)), 415);
  assertEquals(await status(send("POST", "/tasks", { t: "x".repeat(40_000) })), 413);
  assertEquals(await status(send("POST", "/tasks", {}, { ...json, "idempotency-key": "x".repeat(101) })), 400);
  assertEquals(await status(send("POST", "/tasks", {}, { "content-type": "application/json" })), 401);
  const res = await handle(
    send("PATCH", `/tasks/${ID}`, { project_id: ID }),
    reader({ data: { error: "bad_request", message: "project_id cannot be changed through the API." } }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).message, "project_id cannot be changed through the API.");
  assertEquals(await status(send("POST", "/tasks", {}), { data: { error: "forbidden", message: "read only" } }), 403);
  assertEquals(await status(send("POST", "/tasks", {}), { data: { error: "idempotency_conflict" } }), 409);
  assertEquals(await status(send("POST", "/tasks", {}), { error: "rate_limited" }), 429);
  // An unknown code in the data is never echoed.
  const odd = await handle(
    send("POST", "/tasks", {}),
    reader({ data: { error: "something internal", message: "secret" } }),
  );
  assertEquals(odd.status, 500);
  assertEquals(JSON.stringify(await odd.json()).includes("secret"), false);
});

Deno.test("webhooks: list, subscribe, unsubscribe", async () => {
  const seen: { fn: string; p_action: string; p_id: string | null }[] = [];
  const r = reader({ data: { data: [] } }, seen as unknown[]);
  assertEquals((await handle(get("/webhooks"), r)).status, 200);
  assertEquals((await handle(send("POST", "/webhooks", { url: "https://hooks.zapier.com/x" }), r)).status, 201);
  assertEquals(
    (await handle(new Request(`http://x/public-api/v1/webhooks/${ID}`, { method: "DELETE", headers: auth }), r)).status,
    200,
  );
  assertEquals(seen.map((s) => [s.fn, s.p_action, s.p_id]), [
    ["api_webhooks", "list", null],
    ["api_webhooks", "create", null],
    ["api_webhooks", "delete", ID],
  ]);
  assertEquals((await handle(send("PATCH", "/webhooks", {}), r)).status, 405);
  assertEquals(
    (await handle(new Request("http://x/public-api/v1/webhooks", { method: "DELETE", headers: auth }), r)).status,
    405,
  );
});
