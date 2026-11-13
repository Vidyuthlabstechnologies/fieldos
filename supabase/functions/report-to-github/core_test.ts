import { assert, assertEquals } from "@std/assert";

import { bugIssue, type BugReport, fileAll, messageIssue, type MessageReport } from "./core.ts";

const bug: BugReport = {
  id: "b1",
  created_at: "2026-11-11T06:00:00Z",
  user_id: null,
  message: "The DPR\nbutton ```does``` nothing",
  contact_email: null,
  app_version: "1.7.4+19",
  platform: "Android 14",
  recent_errors: null,
};
const msg: MessageReport = {
  id: "m1",
  created_at: "2026-11-11T06:01:00Z",
  message_id: "x",
  reason: "abuse",
  details: null,
  body: null,
  sender_name: "Ravi",
  project_id: "p",
  sent_at: null,
};

Deno.test("issues read like the ones the old script filed, and user text can't break the fence", () => {
  const b = bugIssue(bug);
  assertEquals(b.title, "Bug report: The DPR button ```does``` nothing");
  assertEquals(b.labels, ["bug-report"]);
  assert(b.body.includes("```\nThe DPR\nbutton '''does''' nothing\n```"));
  assert(b.body.includes("**Signed in to the cloud:** no"));
  const m = messageIssue(msg);
  assertEquals(m.title, "Message report: Abuse or harassment");
  assert(m.body.includes("(the message has been deleted)"));
});

Deno.test("a crash the app sent on its own is titled and labelled as a crash", () => {
  const c = bugIssue({ ...bug, message: "[crash 0a1b2c3d] StateError: Bad state: no element" });
  assertEquals(c.title, "Crash: StateError: Bad state: no element");
  assertEquals(c.labels, ["bug-report", "crash"]);
});

Deno.test("files every waiting report; one GitHub failure leaves only that one for next time", async () => {
  const marked: string[] = [];
  let next = 100;
  const r = await fileAll({
    claimBugs: () => Promise.resolve([bug, { ...bug, id: "b2", message: "fails" }]),
    claimMessages: () => Promise.resolve([msg]),
    openIssue: (i) => i.title.includes("fails") ? Promise.reject(new Error("502")) : Promise.resolve(next++),
    markFiled: (kind, id) => {
      marked.push(`${kind}:${id}`);
      return Promise.resolve();
    },
    purgeOld: () => Promise.resolve(3),
  });
  assertEquals(r, { filed: [100, 101], failed: 1, purged: 3 });
  assertEquals(marked, ["bug:b1", "message:m1"]);
});
