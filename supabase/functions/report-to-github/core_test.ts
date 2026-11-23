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
  assert(m.body.includes("deleted since"));
});

Deno.test("nothing that identifies a person reaches the public repository", () => {
  const b = bugIssue({
    ...bug,
    message: "Sync fails, call me on +91 98480 12345 or 9848012345, mail ravi.k@example.co.in",
    contact_email: "ravi.k@example.co.in",
    recent_errors: "AuthException: user ravi.k@example.co.in not found",
  });
  for (const leak of ["ravi.k@example.co.in", "98480 12345", "9848012345"]) {
    assert(!b.body.includes(leak), leak);
    assert(!b.title.includes(leak), leak);
  }
  assert(b.body.includes("email given (in Supabase, bug_reports)"));
  assert(b.body.includes("[number removed]"));
  // Version numbers, short figures and error timestamps stay readable.
  assert(
    bugIssue({ ...bug, recent_errors: "2026-11-08 21:03:37.972752Z PlatformException(23)" }).body
      .includes("2026-11-08 21:03:37.972752Z PlatformException(23)"),
  );
  assert(bugIssue({ ...bug, message: "1.7.7+22 shows 2,500 twice" }).body.includes("1.7.7+22 shows 2,500 twice"));

  const m = messageIssue({
    ...msg,
    body: "Pay me at 9848012345",
    details: "He threatened Suresh",
    sender_name: "Ravi Kumar",
  });
  for (const leak of ["9848012345", "Suresh", "Ravi Kumar", "Pay me"]) assert(!m.body.includes(leak), leak);
  assert(m.body.includes("still in the chat"));
  assert(m.body.includes("message_reports id m1"));
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
