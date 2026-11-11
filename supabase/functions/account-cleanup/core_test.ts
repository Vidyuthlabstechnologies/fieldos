import { assertEquals } from "@std/assert";

import { drain } from "./core.ts";

function fakeStorage(files: { bucket: string; name: string }[]) {
  const left = [...files];
  const calls: number[] = [];
  return {
    left,
    calls,
    deps: {
      queuedFiles: (limit: number) => Promise.resolve(left.slice(0, limit)),
      remove(bucket: string, names: string[]) {
        calls.push(names.length);
        for (const n of names) left.splice(left.findIndex((f) => f.bucket === bucket && f.name === n), 1);
        return Promise.resolve();
      },
      finish: () => Promise.resolve(left.length === 0 ? 2 : 0),
    },
  };
}

Deno.test("removes every queued file, 100 at a time, then clears the folders", async () => {
  const files = Array.from({ length: 250 }, (_, i) => ({ bucket: "documents", name: `p${i % 2}/photo-${i}.jpg` }));
  const s = fakeStorage(files);
  const r = await drain(s.deps, 1000);
  assertEquals(r, { removed: 250, foldersCleared: 2, done: true });
  assertEquals(s.calls, [100, 100, 50]);
  assertEquals(s.left.length, 0);
});

Deno.test("an empty queue does nothing", async () => {
  const s = fakeStorage([]);
  assertEquals(await drain(s.deps), { removed: 0, foldersCleared: 2, done: true });
  assertEquals(s.calls, []);
});

Deno.test("a very large queue stops after the round limit and says it is not done", async () => {
  const files = Array.from({ length: 30 }, (_, i) => ({ bucket: "documents", name: `p/f${i}` }));
  const s = fakeStorage(files);
  const r = await drain(s.deps, 10, 2);
  assertEquals(r.removed, 20);
  assertEquals(r.done, false);
});
