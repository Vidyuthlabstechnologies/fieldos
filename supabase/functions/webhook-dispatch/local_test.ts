// Against the local Supabase stack (skipped unless LOCAL_STACK=1, with
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from `supabase status -o env`):
// a write through public-api's handler lands in the table, webhook_enqueue
// queues it, and dispatch() delivers it signed to a receiver on this
// machine (standing in for the registered public address).
//   LOCAL_STACK=1 deno test -A local_test.ts
import { assert, assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";

import { handle } from "../public-api/core.ts";
import { type Claimed, dispatch, sign } from "./core.ts";

const on = Deno.env.get("LOCAL_STACK") === "1";

Deno.test({ name: "write, queue, deliver signed", ignore: !on }, async () => {
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const email = `hook-${crypto.randomUUID()}@fieldos.test`;
  const { data: u, error: ue } = await admin.auth.admin.createUser({
    email,
    password: "pw-123456!",
    email_confirm: true,
  });
  if (ue) throw ue;
  const uid = u.user!.id;
  const cid = crypto.randomUUID();
  const pid = crypto.randomUUID();
  await admin.from("companies").insert({ id: cid, name: "Hook Co" }).throwOnError();
  await admin.from("company_members").insert({ company_id: cid, user_id: uid, role: "owner" }).throwOnError();
  await admin.from("projects").insert({ id: pid, company_id: cid, name: "Hook Site" }).throwOnError();
  const owner = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("ANON_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      auth: { persistSession: false },
    },
  );
  await owner.auth.signInWithPassword({ email, password: "pw-123456!" });
  const { data: k } = await owner.rpc("create_company_api_key", {
    p_company_id: cid,
    p_name: "Zapier",
    p_scopes: ["write"],
  }).throwOnError();
  const key = (k as { key: string }).key;

  const got: { headers: Headers; body: string }[] = [];
  const server = Deno.serve({ port: 0, onListen() {} }, async (req) => {
    got.push({ headers: req.headers, body: await req.text() });
    return new Response(null, { status: 204 });
  });
  const port = (server.addr as Deno.NetAddr).port;
  const rpc = async (fn: "api_read" | "api_write" | "api_webhooks", args: Record<string, unknown>) =>
    await admin.rpc(fn, args);
  try {
    // Subscribe through the API, as Zapier does.
    let res = await handle(
      new Request("http://x/public-api/v1/webhooks", {
        method: "POST",
        headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
        body: JSON.stringify({ url: "https://hooks.receiver.co.in/catch", events: ["tasks"] }),
      }),
      rpc,
    );
    assertEquals(res.status, 201);
    const hook = (await res.json()).data as { id: string; secret: string };

    res = await handle(
      new Request("http://x/public-api/v1/tasks", {
        method: "POST",
        headers: { authorization: `Bearer ${key}`, "content-type": "application/json", "idempotency-key": "t-1" },
        body: JSON.stringify({ project_id: pid, title: "Pour slab", due_date: "2026-12-05" }),
      }),
      rpc,
    );
    assertEquals(res.status, 201);
    const task = (await res.json()).data as { id: string; title: string };
    assertEquals(task.title, "Pour slab");

    const result = await dispatch(
      {
        async enqueue() {
          return (await admin.rpc("webhook_enqueue", { p_settle_seconds: 0 })).data as number;
        },
        async claim(limit) {
          const { data } = await admin.rpc("webhook_claim", { p_limit: limit });
          return (data ?? []) as Claimed[];
        },
        async report(id, status, error) {
          await admin.rpc("webhook_report", { p_delivery_id: id, p_status: status, p_error: error });
        },
      },
      {
        // The registered public address is answered by the receiver here.
        fetch: (url, init) => fetch(url.replace("https://hooks.receiver.co.in", `http://127.0.0.1:${port}`), init),
        resolve: () => Promise.resolve(["93.184.216.34"]),
        now: () => Date.now(),
      },
    );
    assert(result.sent >= 1);
    const { data: rows } = await admin.from("company_webhook_deliveries").select("id, payload, status, attempts")
      .eq("webhook_id", hook.id);
    // The create and nothing else (one task, folded into one delivery).
    assertEquals(rows!.length, 1);
    assertEquals(rows![0].status, "delivered");
    const mine = got.filter((g) => g.headers.get("fieldos-event-id") === rows![0].id);
    assertEquals(mine.length, 1);
    const ev = JSON.parse(mine[0].body);
    assertEquals(ev.type, "tasks.changed");
    assertEquals(ev.data.object.title, "Pour slab");
    assertEquals(ev.data.project_id, pid);
    const sig = mine[0].headers.get("fieldos-signature")!;
    const t = Number(/t=(\d+)/.exec(sig)![1]);
    assertEquals(sig, await sign(hook.secret, t, mine[0].body));
    const { data: wh } = await admin.from("company_webhooks").select("last_success_at").eq("id", hook.id).single();
    assert(wh!.last_success_at);
  } finally {
    await server.shutdown();
    await admin.from("companies").delete().eq("id", cid);
    await admin.auth.admin.deleteUser(uid);
  }
});
