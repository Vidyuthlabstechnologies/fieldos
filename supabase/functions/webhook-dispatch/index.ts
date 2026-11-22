// webhook-dispatch: sends the company webhooks' queued deliveries
// (docs/OPEN_API.md, Webhooks). Called every minute by pg_cron's
// webhook_tick() when something is due, and by the app's "Send test". It
// needs no caller identity: it only sends what the database already
// queued, to addresses the owner registered, and two runs at once skip each
// other's deliveries. Deployed with --no-verify-jwt.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "@supabase/supabase-js";

import { type Claimed, dispatch } from "./core.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function resolve(host: string): Promise<string[]> {
  const [a, aaaa] = await Promise.allSettled([Deno.resolveDns(host, "A"), Deno.resolveDns(host, "AAAA")]);
  const out = [...(a.status === "fulfilled" ? a.value : []), ...(aaaa.status === "fulfilled" ? aaaa.value : [])];
  if (out.length === 0 && a.status === "rejected") throw a.reason;
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  try {
    const result = await dispatch(
      {
        async enqueue() {
          const { data, error } = await admin.rpc("webhook_enqueue", {});
          if (error) throw error;
          return (data ?? 0) as number;
        },
        async claim(limit) {
          const { data, error } = await admin.rpc("webhook_claim", { p_limit: limit });
          if (error) throw error;
          return (data ?? []) as Claimed[];
        },
        async report(id, status, err) {
          const { error } = await admin.rpc("webhook_report", { p_delivery_id: id, p_status: status, p_error: err });
          if (error) console.error("webhook_report failed", id, error.message);
        },
      },
      { fetch: (url, init) => fetch(url, init), resolve, now: () => Date.now() },
    );
    return Response.json(result);
  } catch (e) {
    console.error("webhook-dispatch failed", e);
    return Response.json({ error: "dispatch failed; it is retried on the next call" }, { status: 500 });
  }
});
