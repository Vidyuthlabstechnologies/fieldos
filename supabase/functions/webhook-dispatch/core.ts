// Sends queued webhook deliveries. Kept apart from Deno.serve so it can be
// tested without a server, a database or the network.
//
// Each run: webhook_enqueue() turns new sync_changes lines into deliveries,
// webhook_claim() leases the due ones, each is POSTed signed with its
// webhook's secret, and webhook_report() records the answer (the SQL side
// decides retries, backoff and switching a failing webhook off).

export type Claimed = {
  id: string;
  url: string;
  secret: string;
  event_type: string;
  payload: unknown;
  attempts: number;
};

export type Store = {
  enqueue(): Promise<number>;
  claim(limit: number): Promise<Claimed[]>;
  report(id: string, status: number, error: string | null): Promise<void>;
};

export type Net = {
  fetch(url: string, init: RequestInit): Promise<Response>;
  /** Every address the host name resolves to (A and AAAA). */
  resolve(host: string): Promise<string[]>;
  now(): number;
};

const TIMEOUT_MS = 10_000;
const PARALLEL = 8;

/** Same rules as webhook_url_ok() in SQL, checked again before every send. */
export function urlOk(raw: string): boolean {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return false;
  }
  if (u.protocol !== "https:" || u.username || u.password) return false;
  if (u.port && u.port !== "443") return false;
  const host = u.hostname.toLowerCase();
  if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(host)) return false;
  if (/^[0-9.]+$/.test(host)) return false;
  if (/\.(localhost|local|internal|intranet|lan|home|corp|private|arpa|test|invalid|example)$/.test(host)) return false;
  return host !== "localhost";
}

/** A private, loopback, link-local or otherwise non-public address. */
export function privateAddress(ip: string): boolean {
  const a = ip.toLowerCase();
  if (a.includes(":")) {
    if (a === "::" || a === "::1") return true;
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(a);
    if (mapped) return privateAddress(mapped[1]);
    return /^(fc|fd|fe8|fe9|fea|feb|ff)/.test(a) || a.startsWith("64:ff9b:") || a.startsWith("2001:db8");
  }
  const p = a.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [x, y] = p;
  return x === 0 || x === 10 || x === 127 || (x === 100 && y >= 64 && y <= 127) || (x === 169 && y === 254) ||
    (x === 172 && y >= 16 && y <= 31) || (x === 192 && y === 168) || (x === 192 && y === 0) ||
    (x === 198 && (y === 18 || y === 19)) || x >= 224;
}

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

/** "t=<unix seconds>,v1=<hex HMAC-SHA256 of '<t>.<body>' with the secret>" */
export async function sign(secret: string, t: number, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [
      "sign",
    ],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${body}`));
  return `t=${t},v1=${hex(mac)}`;
}

/** One send. Returns the HTTP status (0 = no answer) and why it failed. */
export async function deliver(d: Claimed, net: Net): Promise<{ status: number; error: string | null }> {
  if (!urlOk(d.url)) return { status: 0, error: "Address not allowed" };
  const host = new URL(d.url).hostname;
  let addrs: string[];
  try {
    addrs = await net.resolve(host);
  } catch {
    return { status: 0, error: "Could not find the address (DNS)" };
  }
  if (addrs.length === 0) return { status: 0, error: "Could not find the address (DNS)" };
  if (addrs.some(privateAddress)) return { status: 0, error: "Address is on a private network" };
  const body = JSON.stringify(d.payload);
  const t = Math.floor(net.now() / 1000);
  try {
    const res = await net.fetch(d.url, {
      method: "POST",
      // A redirect could point anywhere, including inside a network.
      redirect: "manual",
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        "content-type": "application/json",
        "user-agent": "FieldOS-Webhooks/1.0",
        "fieldos-signature": await sign(d.secret, t, body),
        "fieldos-event-id": d.id,
        "fieldos-event-type": d.event_type,
      },
      body,
    });
    await res.body?.cancel();
    if (res.status >= 200 && res.status < 300) return { status: res.status, error: null };
    return {
      status: res.status,
      error: res.status >= 300 && res.status < 400 ? "Redirects are not followed" : `HTTP ${res.status}`,
    };
  } catch (e) {
    const name = (e as Error)?.name;
    return { status: 0, error: name === "TimeoutError" ? "No answer in 10 seconds" : "Could not connect" };
  }
}

/** Queues, then sends what is due, a few at a time, until none are left or time runs out. */
export async function dispatch(
  store: Store,
  net: Net,
  budgetMs = 45_000,
): Promise<{ queued: number; sent: number; failed: number }> {
  const started = net.now();
  const queued = await store.enqueue();
  let sent = 0;
  let failed = 0;
  while (net.now() - started < budgetMs) {
    const batch = await store.claim(50);
    if (batch.length === 0) break;
    for (let i = 0; i < batch.length; i += PARALLEL) {
      await Promise.all(
        batch.slice(i, i + PARALLEL).map(async (d) => {
          const r = await deliver(d, net);
          await store.report(d.id, r.status, r.error);
          if (r.error === null) sent++;
          else failed++;
        }),
      );
    }
  }
  return { queued, sent, failed };
}
