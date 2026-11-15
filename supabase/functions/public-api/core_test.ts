import { assertEquals } from "@std/assert";

import { type ApiRead, handle, keyOf, route } from "./core.ts";

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

function reader(answer: { data?: unknown; error?: string }, seen: unknown[] = []): ApiRead {
  return (args) => {
    seen.push(args);
    return Promise.resolve({ data: answer.data ?? null, error: answer.error ? { message: answer.error } : null });
  };
}

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
  assertEquals(await status(new Request("http://x/public-api/v1/tasks", { method: "POST" })), 405);
  // A counted call that found nothing comes back as data.
  assertEquals((await handle(get(`/rfis/${ID}`), reader({ data: { error: "not_found" } }))).status, 404);
  assertEquals((await handle(get("/tasks?after=x"), reader({ data: { error: "bad_cursor" } }))).status, 400);
  // Only exact codes map; anything else is a 500 with no detail.
  assertEquals(await status(get("/tasks"), "invalid_key: or something"), 500);
  const res = await handle(get("/tasks"), reader({ error: 'relation "x" does not exist' }));
  assertEquals(res.status, 500);
  assertEquals((await res.json()).message.includes("relation"), false);
});
