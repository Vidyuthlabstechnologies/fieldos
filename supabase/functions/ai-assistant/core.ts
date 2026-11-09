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

import { SYSTEM_PROMPT, TOOLS } from "./tools.ts";

export const MODEL_DEFAULT = "claude-opus-5-5";
export const ENTITLEMENT = "fieldos_pro";
export const MAX_BODY_BYTES = 2_200_000; // a 25-second WAV piece, base64-encoded, fits
export const MAX_MESSAGES = 120;
export const MAX_TEXT_CHARS = 16_000;
export const MAX_AUDIO_BYTES = 1_500_000;

export interface Limits {
  chatCallsPerDay: number;
  voiceSecondsPerDay: number;
}

export interface Deps {
  /** The account behind a Supabase access token, or null if it isn't valid. */
  userFromToken(token: string): Promise<{ id: string } | null>;
  /** Whether this RevenueCat customer has the fieldos_pro entitlement now. */
  hasPlan(subscriberId: string): Promise<boolean>;
  /** Takes from today's allowance: the new total, or null when over [limit]. */
  takeUsage(userId: string, kind: "chat" | "voice", amount: number, limit: number): Promise<number | null>;
  callClaude(params: Record<string, unknown>): Promise<{ content: unknown[]; stop_reason: string | null }>;
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

async function chat(body: Record<string, unknown>, userId: string, deps: Deps): Promise<Response> {
  if (!deps.configured.anthropic) {
    throw new HttpError(503, "not_configured", "The assistant is not switched on yet. Please try again later.");
  }
  const messages = validateMessages(body.messages);
  const used = await deps.takeUsage(userId, "chat", 1, deps.limits.chatCallsPerDay);
  if (used === null) {
    throw new HttpError(429, "daily_limit", "You've used the assistant a lot today. It will be ready again tomorrow.");
  }
  const params = chatParams(deps.model, messages);
  let reply;
  try {
    reply = await deps.callClaude(params);
  } catch (e) {
    console.error("claude call failed", e);
    throw new HttpError(502, "upstream", "The assistant could not answer just now. Please try again in a minute.");
  }
  return json(200, {
    content: reply.content,
    stop_reason: reply.stop_reason,
    left_today: Math.max(0, deps.limits.chatCallsPerDay - used),
  });
}

/** The Messages API request: fixed instructions and tools, the app's history. */
export function chatParams(model: string, messages: unknown[]): Record<string, unknown> {
  return {
    model,
    max_tokens: 8000,
    // Short, practical turns: low effort keeps replies quick and cheap.
    output_config: { effort: "low" },
    system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
    tools: TOOLS,
    // Caches the growing conversation too, so each tool round re-reads it cheaply.
    cache_control: { type: "ephemeral" },
    messages,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
  };
}

const USER_BLOCKS = new Set(["text", "tool_result"]);
const BLOCKED_ASSISTANT_BLOCKS = new Set(["image", "document", "search_result", "container_upload"]);

/** Accepts only what the app's chat can produce: text from the person, tool
 * results from the phone, and assistant messages as the API returned them. */
export function validateMessages(value: unknown): unknown[] {
  const bad = (why: string) =>
    new HttpError(400, "bad_request", `The chat could not be sent (${why}). Start a new chat.`);
  if (!Array.isArray(value) || value.length === 0) throw bad("empty");
  if (value.length > MAX_MESSAGES) {
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
  const used = await deps.takeUsage(userId, "voice", Math.max(1, Math.ceil(seconds)), deps.limits.voiceSecondsPerDay);
  if (used === null) {
    throw new HttpError(429, "daily_limit", "Today's voice time is used up. Please type, or try again tomorrow.");
  }
  let transcript: string;
  try {
    transcript = await deps.transcribe(wav, language);
  } catch (e) {
    console.error("sarvam call failed", e);
    throw new HttpError(502, "upstream", "Could not turn the recording into text just now. Please try again.");
  }
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
    const v = Number.parseInt(get(k) ?? "", 10);
    return Number.isFinite(v) && v > 0 ? v : d;
  };
  return {
    chatCallsPerDay: n("AI_DAILY_CHAT_CALLS", 120),
    voiceSecondsPerDay: n("AI_DAILY_VOICE_SECONDS", 900),
  };
}
