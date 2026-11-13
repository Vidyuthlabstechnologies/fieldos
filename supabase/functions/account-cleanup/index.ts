// account-cleanup: called by the app right after "Delete my cloud account".
// It needs no caller identity: it only removes files that
// delete_my_account() has already queued, and each call drains the whole
// queue, so a call that never arrived is caught up by the next one.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "@supabase/supabase-js";

import { drain } from "./core.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  try {
    const result = await drain({
      async queuedFiles(limit) {
        const { data, error } = await admin.rpc("storage_cleanup_files", { p_limit: limit });
        if (error) throw error;
        return (data ?? []) as { bucket: string; name: string }[];
      },
      async remove(bucket, names) {
        const { error } = await admin.storage.from(bucket).remove(names);
        if (error) throw error;
      },
      async finish() {
        const { data, error } = await admin.rpc("storage_cleanup_finish");
        if (error) throw error;
        return (data ?? 0) as number;
      },
    });
    return Response.json(result);
  } catch (e) {
    console.error("account-cleanup failed", e);
    return Response.json({ error: "cleanup failed; it is retried on the next call" }, { status: 500 });
  }
});
