// Checks against the real services, with the real keys: run by
// .github/workflows/ai-assistant.yml with the repo secrets. Each test is
// skipped when its key isn't in the environment, so this file is safe to run
// anywhere. It spends a few paise of Anthropic and Sarvam credit per run.
//
//   ANTHROPIC_API_KEY=... SARVAM_API_KEY=... REVENUECAT_ANDROID_KEY=... \
//     deno test --allow-env --allow-net supabase/functions/ai-assistant/live_test.ts

import Anthropic from "@anthropic-ai/sdk";
import { assert, assertEquals } from "@std/assert";

import {
  chatParams,
  claudeCostInr,
  entitlementActive,
  fallbackCostInr,
  fallbackParams,
  fromOpenAi,
  MODEL_DEFAULT,
} from "./core.ts";
import { WRITE_TOOLS } from "./tools.ts";

const env = (k: string) => Deno.env.get(k) || undefined;
const anthropicKey = env("ANTHROPIC_API_KEY");
const sarvamKey = env("SARVAM_API_KEY");
const revenuecatKey = env("REVENUECAT_SECRET_KEY") ?? env("REVENUECAT_ANDROID_KEY");
const functionUrl = env("AI_FUNCTION_URL");
const model = env("AI_MODEL") ?? MODEL_DEFAULT;

const usdInr = 95;

const appState =
  `<app_state>{"today":"2026-11-09","app_language":"en","company":"Sri Sai Constructions","user":"Ravi","projects":[{"id":"p1","name":"Narapally Villa","status":"active"}]}</app_state>`;

Deno.test({
  name: "anthropic: the real prompt and tools are accepted, and the assistant uses them",
  ignore: !anthropicKey,
  async fn() {
    const client = new Anthropic({ apiKey: anthropicKey });
    const messages: unknown[] = [{
      role: "user",
      content: [{ type: "text", text: appState }, { type: "text", text: "Add 4500 rupees for cement today" }],
    }];
    // deno-lint-ignore no-explicit-any
    const first = await client.beta.messages.create(chatParams(model, messages) as any);
    console.log("first:", first.stop_reason, JSON.stringify(first.usage));
    assertEquals(first.stop_reason, "tool_use");
    const uses = first.content.filter((b) => b.type === "tool_use") as { id: string; name: string; input: unknown }[];
    assert(uses.length > 0);
    const add = uses.find((u) => u.name === "add_expense");
    assert(add, `expected add_expense, got ${uses.map((u) => u.name)}`);
    assert(WRITE_TOOLS.has(add.name));
    const input = add.input as { project_id: string; amount: number; category: string };
    assertEquals(input.project_id, "p1");
    assertEquals(input.amount, 4500);
    assertEquals(input.category, "Material");

    messages.push({ role: "assistant", content: first.content });
    messages.push({
      role: "user",
      content: uses.map((u) => ({
        type: "tool_result",
        tool_use_id: u.id,
        content: u.name === "add_expense" ? '{"saved":true,"amount":4500}' : '{"ok":true}',
      })),
    });
    // deno-lint-ignore no-explicit-any
    const second = await client.beta.messages.create(chatParams(model, messages) as any);
    console.log("second:", second.stop_reason, JSON.stringify(second.usage));
    assertEquals(second.stop_reason, "end_turn");
    const text = second.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join(" ");
    console.log("reply:", text);
    assert(text.length > 0 && text.length < 600);
    // The whole question, both calls, must stay cheap: that is what keeps the margin.
    const cost = claudeCostInr(model, first.usage, usdInr) + claudeCostInr(model, second.usage, usdInr);
    console.log(`cost of this question: ₹${cost.toFixed(4)}`);
    assert(cost < 0.15, `one question cost ₹${cost}`);
  },
});

Deno.test({
  name: "fallback: DeepSeek on the Sarvam key takes the same tools",
  ignore: !sarvamKey,
  async fn() {
    const messages = [{
      role: "user",
      content: [{ type: "text", text: appState }, { type: "text", text: "Add 4500 rupees for cement today" }],
    }];
    const res = await fetch("https://api.sarvam.ai/v2/chat/completions", {
      method: "POST",
      headers: { "api-subscription-key": sarvamKey!, "content-type": "application/json" },
      body: JSON.stringify(fallbackParams(messages)),
    });
    const body = await res.json();
    console.log("fallback:", res.status, JSON.stringify(body).slice(0, 400));
    assertEquals(res.status, 200);
    const { content, stopReason } = fromOpenAi(body);
    assertEquals(stopReason, "tool_use");
    const add = content.find((b) => (b as { name?: string }).name === "add_expense") as
      | { input: { amount: number; project_id: string } }
      | undefined;
    assert(add, JSON.stringify(content));
    assertEquals(add.input.amount, 4500);
    assertEquals(add.input.project_id, "p1");
    console.log(`fallback call cost: ₹${fallbackCostInr(body.usage).toFixed(4)}`);
  },
});

Deno.test({
  name: "anthropic: replies in the language spoken",
  ignore: !anthropicKey,
  async fn() {
    const client = new Anthropic({ apiKey: anthropicKey });
    const messages = [{
      role: "user",
      content: [{ type: "text", text: appState }, { type: "text", text: "मेरे कितने साइट हैं?" }],
    }];
    // deno-lint-ignore no-explicit-any
    let res = await client.beta.messages.create(chatParams(model, messages) as any);
    const history: unknown[] = [...messages];
    for (let i = 0; i < 3 && res.stop_reason === "tool_use"; i++) {
      history.push({ role: "assistant", content: res.content });
      history.push({
        role: "user",
        content: res.content.filter((b) => b.type === "tool_use").map((b) => ({
          type: "tool_result",
          tool_use_id: (b as { id: string }).id,
          content: '[{"id":"p1","name":"Narapally Villa","status":"active"}]',
        })),
      });
      // deno-lint-ignore no-explicit-any
      res = await client.beta.messages.create(chatParams(model, history) as any);
    }
    const text = res.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join(" ");
    console.log("hindi reply:", text);
    assert(/[ऀ-ॿ]/.test(text), "expected a Devanagari reply");
  },
});

function silentWav(seconds: number): Uint8Array {
  const rate = 16000, dataLen = seconds * rate * 2;
  const buf = new Uint8Array(44 + dataLen);
  const v = new DataView(buf.buffer);
  const put = (o: number, s: string) => [...s].forEach((c, i) => (buf[o + i] = c.charCodeAt(0)));
  put(0, "RIFF");
  v.setUint32(4, 36 + dataLen, true);
  put(8, "WAVE");
  put(12, "fmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  put(36, "data");
  v.setUint32(40, dataLen, true);
  return buf;
}

Deno.test({
  name: "sarvam: the shared key is accepted",
  ignore: !sarvamKey,
  async fn() {
    const form = new FormData();
    form.append("model", "saaras:v4");
    form.append("mode", "transcribe");
    form.append("language_code", "hi-IN");
    form.append("file", new Blob([new Uint8Array(silentWav(1))], { type: "audio/wav" }), "check.wav");
    const res = await fetch("https://api.sarvam.ai/speech-to-text", {
      method: "POST",
      headers: { "api-subscription-key": sarvamKey! },
      body: form,
    });
    const body = await res.text();
    console.log("sarvam:", res.status, body.slice(0, 200));
    assertEquals(res.status, 200);
  },
});

Deno.test({
  name: "revenuecat: the key can read customers",
  ignore: !revenuecatKey,
  async fn() {
    // One fixed id, so repeated runs don't fill RevenueCat with test customers.
    const res = await fetch("https://api.revenuecat.com/v1/subscribers/fieldos-ci-key-check", {
      headers: {
        authorization: `Bearer ${revenuecatKey}`,
        ...(revenuecatKey!.startsWith("goog_") ? { "x-platform": "android" } : {}),
      },
    });
    const body = await res.json();
    console.log("revenuecat:", res.status);
    // 201 the first time a key sees this id (RevenueCat creates the customer), 200 after.
    assert(res.status === 200 || res.status === 201, `status ${res.status}`);
    assertEquals(entitlementActive(body), false);
  },
});

Deno.test({
  name: "deployed function: refuses a caller with no session",
  ignore: !functionUrl,
  async fn() {
    const res = await fetch(functionUrl!, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "chat", messages: [{ role: "user", content: "hi" }] }),
    });
    await res.body?.cancel();
    assertEquals(res.status, 401);
  },
});
