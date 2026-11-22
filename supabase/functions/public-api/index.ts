// public-api: REST for integrations (ERP, BI, Zapier, Make): reads, task and
// issue writes for keys that can write, and webhook subscriptions.
// Callers send a company API key made by the owner in the app; there is no
// Supabase sign-in, so this function is deployed with --no-verify-jwt.
// Every call goes through a SQL function (api_read, api_write, api_webhooks)
// that checks the key, counts the call and keeps each key to its own
// company. See docs/OPEN_API.md.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "@supabase/supabase-js";

import { handle } from "./core.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve((req) => handle(req, async (fn, args) => await admin.rpc(fn, args)));
