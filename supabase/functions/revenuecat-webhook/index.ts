// Receives RevenueCat webhooks and records each company's plan. Deployed
// with --no-verify-jwt: RevenueCat can't send a Supabase JWT, so it sends
// the shared secret REVENUECAT_WEBHOOK_SECRET as its Authorization header
// instead (set in RevenueCat -> Integrations -> Webhooks).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { planChangeFor } from "./plan.ts";

const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const auth = req.headers.get("authorization") ?? "";
  if (!secret || (auth !== secret && auth !== `Bearer ${secret}`)) {
    return new Response("unauthorized", { status: 401 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  // deno-lint-ignore no-explicit-any
  const change = planChangeFor((body as any)?.event);
  if (change.kind === "ignore") return Response.json({ ok: true, ignored: change.reason });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { error, count } = await admin
    .from("companies")
    .update({ plan: change.plan, plan_expires_at: change.expiresAt }, { count: "exact" })
    .eq("id", change.companyId);
  if (error) {
    // 500 makes RevenueCat retry later.
    return new Response(`db error: ${error.message}`, { status: 500 });
  }
  return Response.json({ ok: true, plan: change.plan, updated: count ?? 0 });
});
