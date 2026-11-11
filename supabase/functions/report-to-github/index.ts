// report-to-github: called by the app right after it sends a bug report or
// a message report. It needs no caller identity: it only files reports
// already in the database, and each call files all that are waiting, so a
// call that never arrived is caught up by the next one.
//
// Function secrets (set by .github/workflows/functions-deploy.yml):
//   GITHUB_ISSUES_TOKEN  fine-grained token, Issues: read and write on this repo only
//   GITHUB_REPOSITORY    owner/name, e.g. Vidyuthlabstechnologies/fieldos
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import { createClient } from "@supabase/supabase-js";

import { fileAll, type Issue, MESSAGE_LABEL } from "./core.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const token = Deno.env.get("GITHUB_ISSUES_TOKEN");
const repo = Deno.env.get("GITHUB_REPOSITORY") ?? "Vidyuthlabstechnologies/fieldos";

async function gh(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`https://api.github.com/repos/${repo}/${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "user-agent": "fieldos-report-to-github",
    },
    signal: AbortSignal.timeout(15_000),
  });
}

const labelsReady = new Set<string>();
async function ensureLabel(name: string) {
  if (labelsReady.has(name)) return;
  const res = await gh(`labels/${encodeURIComponent(name)}`);
  if (res.status === 404) {
    const color = name === MESSAGE_LABEL ? "b60205" : "d73a4a";
    await gh("labels", { method: "POST", body: JSON.stringify({ name, color }) });
  } else {
    await res.body?.cancel();
  }
  labelsReady.add(name);
}

async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await admin.rpc(fn, args);
  if (error) throw error;
  return data as T;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  if (!token) return Response.json({ error: "GITHUB_ISSUES_TOKEN is not set; reports wait" }, { status: 503 });
  try {
    const result = await fileAll({
      claimBugs: (limit) => rpc("claim_bug_reports", { p_limit: limit }),
      claimMessages: (limit) => rpc("claim_message_reports", { p_limit: limit }),
      async openIssue(issue: Issue) {
        for (const l of issue.labels) await ensureLabel(l);
        const res = await gh("issues", { method: "POST", body: JSON.stringify(issue) });
        if (!res.ok) throw new Error(`GitHub answered ${res.status}: ${(await res.text()).slice(0, 300)}`);
        return (await res.json()).number as number;
      },
      markFiled: (kind, id, issue) => rpc("mark_report_filed", { p_kind: kind, p_id: id, p_issue: issue }),
      purgeOld: () => rpc("purge_old_reports"),
    });
    return Response.json(result);
  } catch (e) {
    console.error("report-to-github failed", e);
    return Response.json({ error: "filing failed; it is retried on the next call" }, { status: 500 });
  }
});
