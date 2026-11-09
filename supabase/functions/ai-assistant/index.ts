// ai-assistant: the FieldOS AI assistant's server side. Holds the shared
// Anthropic and Sarvam keys (set as function secrets, never in the app),
// checks the caller's Supabase session and FieldOS plan, and caps what each
// account's use may cost a month. All request logic is in core.ts.
//
// Function secrets (set by .github/workflows/ai-assistant-deploy.yml from the
// repo secrets of the same names):
//   ANTHROPIC_API_KEY       Claude, for the chat
//   SARVAM_API_KEY          speech to text for languages a phone can't do, and
//                           the fallback chat model when Anthropic is down
//   REVENUECAT_SECRET_KEY   a RevenueCat v1 secret key (sk_...), to check the plan;
//   or REVENUECAT_ANDROID_KEY  the app's own public key (goog_...), which can
//                           read a customer's entitlements too
// Optional: AI_MODEL, AI_MONTHLY_BUDGET_INR, AI_DAILY_CHAT_CALLS, AI_USD_INR,
// and AI_PLAN_CHECK=off for a test project only.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.

import Anthropic from "@anthropic-ai/sdk";
import { createClient } from "@supabase/supabase-js";

import { type Deps, entitlementActive, handle, limitsFromEnv, MODEL_DEFAULT } from "./core.ts";

const env = (k: string) => Deno.env.get(k) ?? undefined;
const anthropicKey = env("ANTHROPIC_API_KEY");
const sarvamKey = env("SARVAM_API_KEY");
const revenuecatKey = env("REVENUECAT_SECRET_KEY") || env("REVENUECAT_ANDROID_KEY");

const admin = createClient(env("SUPABASE_URL")!, env("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const anthropic = anthropicKey ? new Anthropic({ apiKey: anthropicKey, maxRetries: 1, timeout: 30_000 }) : null;

// A plan rarely changes within minutes; asking RevenueCat on every tool round
// would add a second or so to each step of the conversation.
const planCache = new Map<string, { ok: boolean; at: number }>();
const PLAN_CACHE_MS = 10 * 60_000;

const deps: Deps = {
  async userFromToken(token) {
    const { data, error } = await admin.auth.getUser(token);
    return error || !data.user ? null : { id: data.user.id };
  },
  async hasPlan(subscriberId) {
    const hit = planCache.get(subscriberId);
    if (hit && Date.now() - hit.at < PLAN_CACHE_MS) return hit.ok;
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(subscriberId)}`, {
      headers: {
        authorization: `Bearer ${revenuecatKey}`,
        // A public app key reads the customer the way the app's own SDK does.
        ...(revenuecatKey!.startsWith("goog_") ? { "x-platform": "android" } : {}),
      },
    });
    if (!res.ok) {
      console.error("revenuecat", res.status, await res.text());
      return false;
    }
    const ok = entitlementActive(await res.json());
    planCache.set(subscriberId, { ok, at: Date.now() });
    return ok;
  },
  async hasCompanyPlan(userId) {
    const { data, error } = await admin.rpc("company_plan_covers", { p_user: userId });
    if (error) {
      // Not deployed yet, or the database is down: fall back to the store check.
      console.error("company_plan_covers", error.message);
      return false;
    }
    return data === true;
  },
  async takeUsage(userId, kind, amount, limit) {
    const { data, error } = await admin.rpc("ai_usage_take", {
      p_user: userId,
      p_kind: kind,
      p_amount: amount,
      p_limit: limit,
    });
    if (error) throw error;
    return data == null ? null : Number(data);
  },
  async addSpend(userId, units) {
    const { data, error } = await admin.rpc("ai_spend_add", { p_user: userId, p_amount: units });
    if (error) throw error;
    return Number(data ?? 0);
  },
  async callClaude(params) {
    // deno-lint-ignore no-explicit-any
    const msg = await anthropic!.beta.messages.create(params as any);
    return { content: msg.content as unknown[], stop_reason: msg.stop_reason, usage: msg.usage };
  },
  async callFallback(params) {
    const res = await fetch("https://api.sarvam.ai/v2/chat/completions", {
      method: "POST",
      headers: { "api-subscription-key": sarvamKey!, "content-type": "application/json" },
      body: JSON.stringify(params),
      signal: AbortSignal.timeout(35_000),
    });
    if (!res.ok) throw new Error(`sarvam chat ${res.status}: ${await res.text()}`);
    return await res.json();
  },
  async transcribe(wav, languageCode) {
    const form = new FormData();
    form.append("model", "saaras:v4");
    form.append("mode", "transcribe");
    form.append("language_code", languageCode);
    form.append("file", new Blob([new Uint8Array(wav)], { type: "audio/wav" }), "speech.wav");
    const res = await fetch("https://api.sarvam.ai/speech-to-text", {
      method: "POST",
      headers: { "api-subscription-key": sarvamKey! },
      body: form,
    });
    if (!res.ok) throw new Error(`sarvam ${res.status}: ${await res.text()}`);
    const body = await res.json();
    return String(body.transcript ?? "").trim();
  },
  model: env("AI_MODEL") ?? MODEL_DEFAULT,
  limits: limitsFromEnv(env),
  planCheck: env("AI_PLAN_CHECK") !== "off",
  configured: { anthropic: !!anthropicKey, sarvam: !!sarvamKey, revenuecat: !!revenuecatKey },
};

Deno.serve((req) => handle(req, deps));
