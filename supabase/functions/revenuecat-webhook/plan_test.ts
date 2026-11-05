import { assertEquals } from "jsr:@std/assert@1";
import { planChangeFor } from "./plan.ts";

const company = "2f1b6a3e-8c1d-4e5f-9a7b-0c2d3e4f5a6b";
const now = Date.UTC(2026, 10, 5);
const later = now + 30 * 24 * 3600 * 1000;

Deno.test("a purchase puts the company on Team until expiry", () => {
  assertEquals(
    planChangeFor({ type: "INITIAL_PURCHASE", app_user_id: company, entitlement_ids: ["team"], expiration_at_ms: later }, now),
    { kind: "set", companyId: company, plan: "team", expiresAt: new Date(later).toISOString() },
  );
});

Deno.test("expiry drops to free; cancellation keeps paid time", () => {
  assertEquals(planChangeFor({ type: "EXPIRATION", app_user_id: company, entitlement_ids: ["team"] }, now).kind, "set");
  assertEquals(planChangeFor({ type: "CANCELLATION", app_user_id: company, entitlement_ids: ["team"] }, now).kind, "ignore");
});

Deno.test("anonymous ids and other entitlements are ignored", () => {
  assertEquals(planChangeFor({ type: "RENEWAL", app_user_id: "$RCAnonymousID:abc", entitlement_ids: ["team"] }, now).kind, "ignore");
  assertEquals(planChangeFor({ type: "RENEWAL", app_user_id: company, entitlement_ids: ["pro"] }, now).kind, "ignore");
});
