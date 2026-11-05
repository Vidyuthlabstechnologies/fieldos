// Pure mapping from a RevenueCat webhook event to the plan change it
// implies, kept apart from index.ts so it is testable without a server.
// Event reference: https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields

export const TEAM_ENTITLEMENT = "team";

export type PlanChange =
  | { kind: "set"; companyId: string; plan: "team" | "free"; expiresAt: string | null }
  | { kind: "ignore"; reason: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// deno-lint-ignore no-explicit-any
export function planChangeFor(event: any, now = Date.now()): PlanChange {
  if (!event || typeof event !== "object") return { kind: "ignore", reason: "no event" };
  // The app logs in to RevenueCat with the company id as the app user id,
  // so the subscription belongs to the company, not to one phone.
  const companyId = String(event.app_user_id ?? "");
  if (!UUID.test(companyId)) return { kind: "ignore", reason: "app_user_id is not a company id" };
  const entitlements: string[] = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : []);
  if (!entitlements.includes(TEAM_ENTITLEMENT)) return { kind: "ignore", reason: "not the team entitlement" };

  const expiresMs = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
  const expiresAt = expiresMs === null ? null : new Date(expiresMs).toISOString();

  switch (event.type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "PRODUCT_CHANGE":
    case "UNCANCELLATION":
    case "NON_RENEWING_PURCHASE":
    case "SUBSCRIPTION_EXTENDED":
    case "TEMPORARY_ENTITLEMENT_GRANT":
      if (expiresMs !== null && expiresMs <= now) return { kind: "set", companyId, plan: "free", expiresAt: null };
      return { kind: "set", companyId, plan: "team", expiresAt };
    case "EXPIRATION":
      return { kind: "set", companyId, plan: "free", expiresAt: null };
    case "CANCELLATION":
    case "BILLING_ISSUE":
      // Paid time already bought still counts; EXPIRATION ends it.
      return { kind: "ignore", reason: `${event.type} keeps access until expiry` };
    default:
      return { kind: "ignore", reason: `unhandled type ${event.type}` };
  }
}
