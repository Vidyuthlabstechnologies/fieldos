import { assertEquals, assertMatch } from "@std/assert";

import { type Claimed, deliver, dispatch, type Net, privateAddress, sign, urlOk } from "./core.ts";

const D: Claimed = {
  id: "0b9f6a52-3c1d-4e8a-9f00-1234567890ab",
  url: "https://hooks.zapier.com/hooks/catch/1/abc",
  secret: "whsec_" + "ab".repeat(24),
  event_type: "tasks.changed",
  payload: { id: "0b9f6a52-3c1d-4e8a-9f00-1234567890ab", type: "tasks.changed", data: { id: "t1" } },
  attempts: 1,
};

function net(
  answer: number | Error,
  addrs: string[] = ["93.184.216.34"],
  seen: { url: string; init: RequestInit }[] = [],
): Net {
  return {
    fetch(url, init) {
      seen.push({ url, init });
      return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(new Response(null, { status: answer }));
    },
    resolve: () => Promise.resolve(addrs),
    now: () => 1_700_000_000_000,
  };
}

Deno.test("addresses: https, public names only", () => {
  assertEquals(urlOk("https://hooks.zapier.com/x?y=1"), true);
  assertEquals(urlOk("https://hook.eu1.make.com/abc"), true);
  assertEquals(urlOk("https://erp.example.co.in:443/in"), true);
  for (
    const bad of [
      "http://hooks.zapier.com/x",
      "https://127.0.0.1/x",
      "https://localhost/x",
      "https://db.internal/x",
      "https://printer.local/x",
      "https://user:pw@hooks.zapier.com/x",
      "https://hooks.zapier.com:8443/x",
      "https://[::1]/x",
      "https://intranet/x",
      "not a url",
    ]
  ) assertEquals(urlOk(bad), false, bad);
});

Deno.test("private and special addresses are refused", () => {
  for (
    const ip of [
      "10.0.0.5",
      "127.0.0.1",
      "169.254.169.254",
      "172.16.0.1",
      "192.168.1.1",
      "100.64.0.1",
      "0.0.0.0",
      "::1",
      "fd00::1",
      "fe80::1",
      "::ffff:10.0.0.1",
      "224.0.0.1",
    ]
  ) {
    assertEquals(privateAddress(ip), true, ip);
  }
  for (const ip of ["93.184.216.34", "8.8.8.8", "172.32.0.1", "2606:4700::6810:84e5"]) {
    assertEquals(privateAddress(ip), false, ip);
  }
});

Deno.test("the signature is HMAC-SHA256 of '<t>.<body>' with the secret", async () => {
  const sig = await sign("whsec_test", 1700000000, '{"a":1}');
  assertMatch(sig, /^t=1700000000,v1=[0-9a-f]{64}$/);
  // Fixed vector, so receivers' checks can be tested against it.
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode("whsec_test"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const mac = Uint8Array.from(sig.split("v1=")[1].match(/../g)!.map((h) => parseInt(h, 16)));
  assertEquals(await crypto.subtle.verify("HMAC", key, mac, new TextEncoder().encode('1700000000.{"a":1}')), true);
});

Deno.test("a send: signed headers, no redirects, the status back", async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  assertEquals(await deliver(D, net(204, undefined, seen)), { status: 204, error: null });
  const h = new Headers(seen[0].init.headers);
  assertEquals(seen[0].init.redirect, "manual");
  assertEquals(h.get("fieldos-event-id"), D.id);
  assertEquals(h.get("fieldos-event-type"), "tasks.changed");
  assertEquals(h.get("fieldos-signature"), await sign(D.secret, 1_700_000_000, JSON.stringify(D.payload)));
  assertEquals(seen[0].init.body, JSON.stringify(D.payload));
  assertEquals(await deliver(D, net(500)), { status: 500, error: "HTTP 500" });
  assertEquals(await deliver(D, net(302)), { status: 302, error: "Redirects are not followed" });
  assertEquals(await deliver(D, net(new TypeError("refused"))), { status: 0, error: "Could not connect" });
  assertEquals((await deliver(D, net(new DOMException("t", "TimeoutError")))).error, "No answer in 10 seconds");
});

Deno.test("a name that resolves to a private address is never called", async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  assertEquals(await deliver(D, net(200, ["93.184.216.34", "10.1.2.3"], seen)), {
    status: 0,
    error: "Address is on a private network",
  });
  assertEquals(await deliver(D, net(200, [], seen)), { status: 0, error: "Could not find the address (DNS)" });
  assertEquals(await deliver({ ...D, url: "https://127.0.0.1/x" }, net(200, undefined, seen)), {
    status: 0,
    error: "Address not allowed",
  });
  assertEquals(seen.length, 0);
});

Deno.test("dispatch queues, sends every due delivery and reports each", async () => {
  const queue = [[D, { ...D, id: "2", url: "https://down.example.co.in/x" }], []];
  const reports: [string, number, string | null][] = [];
  const result = await dispatch(
    {
      enqueue: () => Promise.resolve(2),
      claim: () => Promise.resolve(queue.shift() ?? []),
      report: (id, status, error) => {
        reports.push([id, status, error]);
        return Promise.resolve();
      },
    },
    {
      fetch: (url) => Promise.resolve(new Response(null, { status: url.includes("down") ? 503 : 200 })),
      resolve: () => Promise.resolve(["93.184.216.34"]),
      now: () => Date.now(),
    },
  );
  assertEquals(result, { queued: 2, sent: 1, failed: 1 });
  assertEquals(reports.sort(), [["0b9f6a52-3c1d-4e8a-9f00-1234567890ab", 200, null], ["2", 503, "HTTP 503"]].sort());
});
