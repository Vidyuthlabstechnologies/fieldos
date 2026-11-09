// Request handling for the ai-assistant edge function, kept free of Deno
// globals and network clients so the tests can drive every path with fakes.
// index.ts wires in the real Supabase, RevenueCat, Anthropic and Sarvam.
//
// Two actions, both for signed-in accounts with an active FieldOS plan:
//   chat        one step of the assistant conversation. The app sends the
//               whole history (the API needs it, unchanged, every time) and
//               gets the next assistant message back. When that message asks
//               for tools, the app runs them on the phone and calls again.
//   transcribe  speech to text with the shared Sarvam key, only for phones
//               whose own recognizer can't do the language. Most speech is
//               turned into text on the phone, offline and free.
//
// Every call is costed from the providers' own token counts and added to the
// account's spend for the month. Past AI_MONTHLY_BUDGET_INR (₹10 by default,
// about 1.3% of what one person's plan brings in after store fees) the
// assistant stops until the 1st, so careless use can't run up a bill.

import { SYSTEM_PROMPT, TOOLS } from "./tools.ts";

// The cheapest model that does the job well. The prompt and tools are cached,
// thinking is off and replies are short, so a typical question (two or three
// calls) costs well under ₹0.10.
export const MODEL_DEFAULT = "claude-haiku-5-5";
// Used only when Anthropic is down or overloaded: DeepSeek on the shared Sarvam
// key, through Sarvam's OpenAI-style chat API.
export const FALLBACK_MODEL = "deepseekv4.1-flash-1017";
export const ENTITLEMENT = "fieldos_pro";
export const MAX_BODY_BYTES = 2_200_000; // a 25-second WAV piece, base64-encoded, fits
// A chat bigger than this is refused ("start a new chat"): it keeps every call
// well under 100K tokens, where Haiku's price is 5 times higher.
export const MAX_CHAT_CHARS = 120_000;
export const MAX_MESSAGES = 120;
export const MAX_TEXT_CHARS = 16_000;
export const MAX_AUDIO_BYTES = 1_500_000;
export const MAX_OUTPUT_TOKENS = 2000;

/** Spend is counted in 1/10,000 of a rupee, so small calls still add up exactly. */
export const UNITS_PER_INR = 10_000;

export interface Limits {
  /** Model calls per account per India calendar day: a guard against bursts. */
  chatCallsPerDay: number;
  /** What one account's AI use (chat and Sarvam voice) may cost a month, in ₹. */
  monthlyBudgetInr: number;
  /** Rupees per US dollar, for Anthropic's dollar prices. Kept on the high side. */
  usdInr: number;
}

export interface TokenUsage {
  input_tokens?: number | null;
  output_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}

export interface OpenAiUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: { cached_tokens?: number } | null;
}

export interface Deps {
  /** The account behind a Supabase access token, or null if it isn't valid. */
  userFromToken(token: string): Promise<{ id: string } | null>;
  /** Whether this RevenueCat customer has the fieldos_pro entitlement now. */
  hasPlan(subscriberId: string): Promise<boolean>;
  /** Takes from today's call allowance: the new total, or null when over [limit]. */
  takeUsage(userId: string, kind: "chat", amount: number, limit: number): Promise<number | null>;
  /** Adds [units] (0 just reads) to this month's spend and returns the total. */
  addSpend(userId: string, units: number): Promise<number>;
  callClaude(params: Record<string, unknown>): Promise<{
    content: unknown[];
    stop_reason: string | null;
    usage?: TokenUsage;
  }>;
  /** Sarvam's chat completions API (OpenAI shape), for the fallback model. */
  callFallback(params: Record<string, unknown>): Promise<Record<string, unknown>>;
  transcribe(wav: Uint8Array, languageCode: string): Promise<string>;
  model: string;
  limits: Limits;
  /** Off only for a test project; production always checks the plan. */
  planCheck: boolean;
  configured: { anthropic: boolean; sarvam: boolean; revenuecat: boolean };
}

export class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export function errorResponse(e: HttpError) {
  return json(e.status, { error: e.code, message: e.message });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  try {
    return await route(req, deps);
  } catch (e) {
    if (e instanceof HttpError) return errorResponse(e);
    console.error("ai-assistant failed", e);
    return errorResponse(new HttpError(500, "internal", "Something went wrong on our side. Please try again."));
  }
}

async function route(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") throw new HttpError(405, "method", "Use POST.");
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    throw new HttpError(413, "too_large", "This chat has grown too long. Start a new chat.");
  }
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "bad_request", "The request could not be read.");
  }
  if (typeof body !== "object" || body === null) {
    throw new HttpError(400, "bad_request", "The request could not be read.");
  }

  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const user = token ? await deps.userFromToken(token) : null;
  if (!user) throw new HttpError(401, "signed_out", "Sign in to FieldOS again to use the assistant.");

  if (deps.planCheck) {
    if (!deps.configured.revenuecat) {
      throw new HttpError(503, "not_configured", "The assistant is not switched on yet. Please try again later.");
    }
    const subscriber = typeof body.subscriber_id === "string" ? body.subscriber_id.trim() : "";
    if (!subscriber || subscriber.length > 200 || !(await deps.hasPlan(subscriber))) {
      throw new HttpError(
        402,
        "no_plan",
        "The assistant comes with the FieldOS plan. Start or renew it in My subscription.",
      );
    }
  }

  switch (body.action) {
    case "chat":
      return await chat(body, user.id, deps);
    case "transcribe":
      return await transcribe(body, user.id, deps);
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}

const monthlyLimit = () =>
  new HttpError(
    429,
    "monthly_limit",
    "You've used this month's assistant allowance. It starts again on the 1st. Everything else in FieldOS works as usual.",
  );

async function chat(body: Record<string, unknown>, userId: string, deps: Deps): Promise<Response> {
  if (!deps.configured.anthropic) {
    throw new HttpError(503, "not_configured", "The assistant is not switched on yet. Please try again later.");
  }
  const messages = validateMessages(body.messages);
  const budget = Math.round(deps.limits.monthlyBudgetInr * UNITS_PER_INR);
  if ((await deps.addSpend(userId, 0)) >= budget) throw monthlyLimit();
  const used = await deps.takeUsage(userId, "chat", 1, deps.limits.chatCallsPerDay);
  if (used === null) {
    throw new HttpError(429, "daily_limit", "You've used the assistant a lot today. It will be ready again tomorrow.");
  }

  let content: unknown[];
  let stopReason: string | null;
  let costInr: number;
  try {
    const reply = await deps.callClaude(chatParams(deps.model, messages));
    content = reply.content;
    stopReason = reply.stop_reason;
    costInr = claudeCostInr(deps.model, reply.usage ?? {}, deps.limits.usdInr);
  } catch (e) {
    if (!deps.configured.sarvam || !worthFallback(e)) {
      console.error("claude call failed", e);
      throw new HttpError(502, "upstream", "The assistant could not answer just now. Please try again in a minute.");
    }
    console.error("claude unavailable, using the fallback model", e);
    try {
      const res = await deps.callFallback(fallbackParams(messages));
      ({ content, stopReason } = fromOpenAi(res));
      costInr = fallbackCostInr(res.usage as OpenAiUsage | undefined);
    } catch (e2) {
      console.error("fallback call failed", e2);
      throw new HttpError(502, "upstream", "The assistant could not answer just now. Please try again in a minute.");
    }
  }
  const spent = await deps.addSpend(userId, Math.ceil(costInr * UNITS_PER_INR));
  return json(200, {
    content,
    stop_reason: stopReason,
    // Share of this month's allowance still left, 0-100, so the app can warn early.
    allowance_left: Math.max(0, Math.min(100, Math.floor((100 * (budget - spent)) / budget))),
  });
}

/** Down, overloaded or rate limited: worth trying the other model. A request
 * Anthropic refused as malformed would fail there too. */
function worthFallback(e: unknown): boolean {
  const status = (e as { status?: unknown })?.status;
  return typeof status !== "number" || status === 408 || status === 429 || status >= 500;
}

/** The Messages API request: fixed instructions and tools, the app's history. */
export function chatParams(model: string, messages: unknown[]): Record<string, unknown> {
  return {
    model,
    max_tokens: MAX_OUTPUT_TOKENS,
    // Short, practical turns. Haiku does them well without thinking, which
    // would only add output tokens; the other models can't turn it off.
    ...(model.startsWith("claude-haiku") ? { thinking: { type: "disabled" } } : {}),
    output_config: { effort: "low" },
    system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
    tools: TOOLS,
    // Caches the growing conversation too, so each tool round re-reads it cheaply.
    cache_control: { type: "ephemeral" },
    messages,
  };
}

// Prices in US dollars per million tokens: input, output, cache write (5
// minutes), cache read. A model not listed is charged at the dearest rate here.
const CLAUDE_USD: Record<string, [number, number, number, number]> = {
  "claude-haiku-5-5": [0.10, 0.50, 0.125, 0.01],
  "claude-sonnet-5-5": [2, 10, 2.5, 0.2],
  "claude-opus-5-5": [4, 20, 5, 0.2],
};

/** What one Claude call cost, in rupees, from the token counts it reported. */
export function claudeCostInr(model: string, u: TokenUsage, usdInr: number): number {
  let [inp, out, write, read] = CLAUDE_USD[model] ?? CLAUDE_USD["claude-opus-5-5"];
  const prompt = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0);
  if (model.startsWith("claude-haiku") && prompt > 100_000) {
    [inp, out, write, read] = [inp, out, write, read].map((x) => x * 5);
  }
  const usd = ((u.input_tokens ?? 0) * inp + (u.output_tokens ?? 0) * out +
    (u.cache_creation_input_tokens ?? 0) * write + (u.cache_read_input_tokens ?? 0) * read) / 1e6;
  return usd * usdInr;
}

/** DeepSeek on Sarvam, in rupees per million tokens: input, cached input, output. */
const FALLBACK_INR: [number, number, number] = [14, 0.25, 55];

export function fallbackCostInr(u: OpenAiUsage | undefined): number {
  const prompt = u?.prompt_tokens ?? 0;
  const cached = Math.min(prompt, u?.prompt_tokens_details?.cached_tokens ?? 0);
  const [inp, hit, out] = FALLBACK_INR;
  return ((prompt - cached) * inp + cached * hit + (u?.completion_tokens ?? 0) * out) / 1e6;
}

/** Sarvam speech to text: ₹0.49 a minute, billed by the second. */
export function voiceCostInr(seconds: number): number {
  return (Math.ceil(seconds) * 0.49) / 60;
}

/** The same conversation for the fallback model, in the OpenAI chat shape. */
export function fallbackParams(messages: unknown[]): Record<string, unknown> {
  return {
    model: FALLBACK_MODEL,
    max_tokens: MAX_OUTPUT_TOKENS,
    reasoning_effort: "none",
    tools: TOOLS.map((t) => ({
      type: "function",
      function: { name: t.name, description: t.description, parameters: t.input_schema },
    })),
    messages: [{ role: "system", content: SYSTEM_PROMPT }, ...toOpenAi(messages)],
  };
}

type Block = Record<string, unknown>;

export function toOpenAi(messages: unknown[]): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  for (const m of messages as { role: string; content: string | Block[] }[]) {
    const blocks: Block[] = typeof m.content === "string" ? [{ type: "text", text: m.content }] : m.content;
    const text = blocks.filter((b) => b.type === "text").map((b) => String(b.text)).join("\n\n");
    if (m.role === "user") {
      // Tool results answer the previous assistant turn, so they go first.
      for (const b of blocks) {
        if (b.type === "tool_result") {
          const err = b.is_error === true ? "Error: " : "";
          out.push({ role: "tool", tool_call_id: b.tool_use_id, content: err + String(b.content) });
        }
      }
      if (text) out.push({ role: "user", content: text });
    } else {
      const calls = blocks.filter((b) => b.type === "tool_use").map((b) => ({
        id: b.id,
        type: "function",
        function: { name: b.name, arguments: JSON.stringify(b.input ?? {}) },
      }));
      out.push({ role: "assistant", content: text || null, ...(calls.length ? { tool_calls: calls } : {}) });
    }
  }
  return out;
}

/** The fallback's answer as Messages API blocks, so the app sees one format. */
export function fromOpenAi(res: Record<string, unknown>): { content: unknown[]; stopReason: string } {
  const choice = (res.choices as Record<string, unknown>[] | undefined)?.[0] ?? {};
  const msg = (choice.message ?? {}) as { content?: string | null; tool_calls?: Record<string, unknown>[] };
  const content: unknown[] = [];
  if (typeof msg.content === "string" && msg.content.trim()) content.push({ type: "text", text: msg.content.trim() });
  for (const [i, call] of (msg.tool_calls ?? []).entries()) {
    const fn = (call.function ?? {}) as { name?: string; arguments?: string };
    let input: unknown = {};
    try {
      input = JSON.parse(fn.arguments || "{}");
    } catch {
      input = {};
    }
    // Claude needs ids of letters, digits, _ and - when it reads this history later.
    const raw = String(call.id ?? "");
    const id = /^[A-Za-z0-9_-]{1,64}$/.test(raw) ? raw : `call_${i}_${Date.now()}`;
    content.push({ type: "tool_use", id, name: String(fn.name ?? ""), input });
  }
  const hasTools = content.some((b) => (b as Block).type === "tool_use");
  const finish = choice.finish_reason;
  const stopReason = hasTools ? "tool_use" : finish === "length" ? "max_tokens" : "end_turn";
  if (content.length === 0) content.push({ type: "text", text: "…" });
  return { content, stopReason };
}

const USER_BLOCKS = new Set(["text", "tool_result"]);
const BLOCKED_ASSISTANT_BLOCKS = new Set(["image", "document", "search_result", "container_upload"]);

/** Accepts only what the app's chat can produce: text from the person, tool
 * results from the phone, and assistant messages as the API returned them. */
export function validateMessages(value: unknown): unknown[] {
  const bad = (why: string) =>
    new HttpError(400, "bad_request", `The chat could not be sent (${why}). Start a new chat.`);
  if (!Array.isArray(value) || value.length === 0) throw bad("empty");
  if (value.length > MAX_MESSAGES || JSON.stringify(value).length > MAX_CHAT_CHARS) {
    throw new HttpError(413, "too_large", "This chat has grown too long. Start a new chat.");
  }
  value.forEach((m, i) => {
    if (typeof m !== "object" || m === null) throw bad("message");
    const { role, content } = m as { role?: unknown; content?: unknown };
    if (role !== (i % 2 === 0 ? "user" : "assistant")) throw bad("order");
    if (role === "user") {
      if (typeof content === "string") {
        if (content.trim() === "" || content.length > MAX_TEXT_CHARS) throw bad("text");
        return;
      }
      if (!Array.isArray(content) || content.length === 0) throw bad("content");
      for (const b of content) {
        const block = b as Record<string, unknown>;
        if (!block || !USER_BLOCKS.has(block.type as string)) throw bad("block");
        if (block.type === "text" && (typeof block.text !== "string" || block.text.length > MAX_TEXT_CHARS)) {
          throw bad("text");
        }
        if (block.type === "tool_result") {
          if (typeof block.tool_use_id !== "string") throw bad("tool result");
          if (typeof block.content !== "string" || block.content.length > MAX_TEXT_CHARS) throw bad("tool result");
        }
      }
    } else {
      if (!Array.isArray(content) || content.length === 0) throw bad("reply");
      for (const b of content) {
        const t = (b as Record<string, unknown>)?.type;
        if (typeof t !== "string" || BLOCKED_ASSISTANT_BLOCKS.has(t)) throw bad("reply block");
      }
    }
  });
  return value;
}

async function transcribe(body: Record<string, unknown>, userId: string, deps: Deps): Promise<Response> {
  if (!deps.configured.sarvam) {
    throw new HttpError(503, "not_configured", "Voice in this language is not switched on yet. Please type instead.");
  }
  const b64 = typeof body.audio_base64 === "string" ? body.audio_base64 : "";
  let wav: Uint8Array;
  try {
    wav = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    throw new HttpError(400, "bad_audio", "The recording could not be read. Please record it again.");
  }
  if (wav.length === 0 || wav.length > MAX_AUDIO_BYTES) {
    throw new HttpError(400, "bad_audio", "Send the recording in pieces of 25 seconds or less.");
  }
  const seconds = wavSeconds(wav);
  if (seconds === null || seconds > 30) {
    throw new HttpError(400, "bad_audio", "Send the recording in pieces of 25 seconds or less.");
  }
  const language = typeof body.language_code === "string" && /^[a-z]{2}-IN$|^unknown$/.test(body.language_code)
    ? body.language_code
    : "unknown";
  const cost = Math.ceil(voiceCostInr(Math.max(1, seconds)) * UNITS_PER_INR);
  const budget = Math.round(deps.limits.monthlyBudgetInr * UNITS_PER_INR);
  if ((await deps.addSpend(userId, 0)) + cost > budget) {
    throw new HttpError(
      429,
      "monthly_limit",
      "This month's voice allowance is used up. Please type, or use the phone's own voice typing.",
    );
  }
  let transcript: string;
  try {
    transcript = await deps.transcribe(wav, language);
  } catch (e) {
    console.error("sarvam call failed", e);
    throw new HttpError(502, "upstream", "Could not turn the recording into text just now. Please try again.");
  }
  await deps.addSpend(userId, cost);
  return json(200, { transcript });
}

/** Length of a PCM WAV recording, read from its header; null if it isn't one. */
export function wavSeconds(wav: Uint8Array): number | null {
  if (wav.length < 44) return null;
  const tag = (o: number) => String.fromCharCode(...wav.subarray(o, o + 4));
  if (tag(0) !== "RIFF" || tag(8) !== "WAVE") return null;
  const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  let offset = 12;
  let byteRate = 0;
  while (offset + 8 <= wav.length) {
    const id = tag(offset);
    const size = view.getUint32(offset + 4, true);
    if (id === "fmt " && offset + 20 <= wav.length) byteRate = view.getUint32(offset + 16, true);
    if (id === "data") {
      if (byteRate <= 0) return null;
      return Math.min(size, wav.length - offset - 8) / byteRate;
    }
    offset += 8 + size + (size % 2);
  }
  return null;
}

/** Whether a RevenueCat v1 subscriber response has the entitlement active. */
export function entitlementActive(subscriber: unknown, now = new Date()): boolean {
  const ent = (subscriber as { subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> } })
    ?.subscriber?.entitlements?.[ENTITLEMENT];
  if (!ent) return false;
  if (ent.expires_date == null) return true; // lifetime / no end date
  const ends = Date.parse(ent.expires_date);
  return Number.isFinite(ends) && ends > now.getTime();
}

export function limitsFromEnv(get: (k: string) => string | undefined): Limits {
  const n = (k: string, d: number) => {
    const v = Number.parseFloat(get(k) ?? "");
    return Number.isFinite(v) && v > 0 ? v : d;
  };
  return {
    chatCallsPerDay: Math.floor(n("AI_DAILY_CHAT_CALLS", 60)),
    monthlyBudgetInr: n("AI_MONTHLY_BUDGET_INR", 10),
    usdInr: n("AI_USD_INR", 95),
  };
}
