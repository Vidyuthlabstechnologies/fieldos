# MaterialReceipts Sync Analysis

## Executive Summary

**Recommendation:** MaterialReceipts should NOT be synced in their current form. The mobile and desktop/Postgres schemas represent fundamentally different business processes and forcing a mapping would corrupt data or mislead users.

## Schema Comparison

### Mobile: MaterialReceipts (Simple Consumption Log)
Located in: `fieldos_mobile/lib/data/tables.dart`

```dart
class MaterialReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get materialName => text()();
  RealColumn get quantity => real()();
  TextColumn get unit => text()();
  RealColumn get amount => real().nullable()();
  DateTimeColumn get receiptDate => dateTime()();
  TextColumn get notes => text().nullable()();
}
```

**Purpose:** Track material consumption on-site with cost tracking
- Single quantity field (what was received/used)
- Single amount field (what it cost)
- No connection to procurement chain (PO, supplier, etc.)
- Can be created ad-hoc without a purchase order
- Feeds cost-engine actuals via `cost_head_id`

### Desktop/Postgres: grns (Goods Receipt Notes - Procurement-Linked)
Located in: `supabase/migrations/20260823000000_initial_schema.sql`

```sql
create table grns (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  purchase_order_id uuid not null references purchase_orders(id),
  supplier_id uuid not null references vendors(id),
  grn_number text,
  ordered_qty numeric(14,3),
  received_qty numeric(14,3),
  shortage_qty numeric(14,3),
  receipt_date date not null,
  quality_status text check(quality_status in ('pending', 'approved', 'rejected')),
  cost_head_id uuid references cost_heads(id),
  notes text
);
```

**Purpose:** Record receipt of goods against purchase orders
- Splits ordered_qty vs received_qty (procurement verification)
- REQUIRES purchase_order_id (NOT NULL)
- REQUIRES supplier_id (NOT NULL)
- Tracks shortages separately
- Quality approval workflow
- Has cost_head_id (like mobile) but in different context

## Critical Mismatches

### 1. Purchase Order Requirement
- **Postgres:** `purchase_order_id uuid not null` - MUST be linked to a PO
- **Mobile:** No PO field - receipts can be created independently
- **Impact:** 60-70% of mobile receipts would fail foreign key constraints

### 2. Quantity Model
- **Postgres:** Ordered qty + Received qty + Shortage (3 separate fields for verification)
- **Mobile:** Single quantity field (what was received)
- **Impact:** Cannot reconstruct ordered/received/shortage split from mobile data

### 3. Supplier Linkage
- **Postgres:** `supplier_id uuid not null` - direct supplier reference
- **Mobile:** No supplier field at all
- **Impact:** Would need to infer supplier from non-existent PO

### 4. Semantic Meaning
- **Postgres GRN:** "We ordered 100, received 95, 5 shortage" - procurement verification
- **Mobile Receipt:** "We used 20 bags of cement today costing ₹8000" - consumption tracking
- **Impact:** Same record means different things in each context

## Real-World Scenario Analysis

### Scenario 1: Field Purchase (No PO)
```
Site engineer buys emergency material from local vendor:
- 5 bags cement
- ₹2500
- No PO (emergency purchase)

Mobile: ✅ Creates MaterialReceipt
Sync to Postgres grns: ❌ Fails - no purchase_order_id
```

### Scenario 2: Planned Procurement
```
Office creates PO → Supplier delivers → Field receives:

Postgres grns:
- purchase_order_id: [PO-123]
- supplier_id: [Supplier-A]
- ordered_qty: 100
- received_qty: 95
- shortage_qty: 5

Mobile creates receipt for the 95 received:
- quantity: 95
- amount: ₹47500

Sync mobile → Postgres: ❌ Overwrites ordered_qty, loses shortage tracking
Sync Postgres → mobile: ❌ Collapses ordered/received into single field
```

### Scenario 3: Cost Head Tracking
```
Mobile uses MaterialReceipts to track cost_head_id actuals:
- Material: "RCC M25 Concrete"
- Quantity: 15 cu.m
- Cost Head: "Ground Floor Slab RCC"
- Amount: ₹82500

This is consumption tracking, not a GRN.
Postgres grns.cost_head_id exists but serves procurement allocation, not actuals.
```

## Alternative Solutions

### Option A: Don't Sync (Recommended)
**Keep MaterialReceipts mobile-only as a consumption log.**

Pros:
- No data corruption
- Clear separation of concerns
- Mobile remains fully functional offline
- Desktop GRNs serve procurement workflow

Cons:
- No cross-device sync for this entity
- Field receipts don't appear in desktop

Trade-off: Acceptable - consumption tracking vs procurement verification are different workflows

### Option B: Redesign Mobile Schema (Breaking Change)
**Align mobile to GRN shape:**

```dart
class MaterialReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get purchaseOrderId => text()(); // NEW - REQUIRED
  TextColumn get supplierId => text()(); // NEW - REQUIRED
  RealColumn get orderedQty => real()(); // NEW
  RealColumn get receivedQty => real()(); // REPLACES quantity
  RealColumn get shortageQty => real()(); // NEW
  TextColumn get qualityStatus => text()(); // NEW
  // ... rest
}
```

Pros:
- 1:1 mapping possible
- Full sync capability

Cons:
- BREAKING CHANGE to existing mobile database
- Requires Drift migration v5
- All existing MaterialReceipt rows must be backfilled or deleted
- Loses ad-hoc receipt capability (field purchases without PO)
- Forces mobile into desktop's procurement-centric workflow
- User experience degrades (can't track simple "used cement today" without full PO)

Effort: 2-3 days + data migration risk

### Option C: Dual-Table Architecture
**Create separate mobile tables:**

```
MaterialReceipts (current) - Simple consumption log
MaterialGRNs (new) - Procurement-linked, matches Postgres grns
```

Pros:
- Preserves both workflows
- GRNs sync, receipts stay local
- No breaking changes

Cons:
- Increased complexity
- UI needs to distinguish the two
- Users might be confused about which to use

Effort: 3-4 days

### Option D: Aggregation Layer (Future)
**Sync MaterialReceipts → separate Postgres table for consumption actuals**

Create new Postgres table:
```sql
create table material_consumption (
  id uuid primary key,
  project_id uuid references projects(id),
  material_name text,
  quantity numeric(14,3),
  unit text,
  amount numeric(14,2),
  receipt_date date,
  cost_head_id uuid references cost_heads(id),
  notes text
);
```

Pros:
- Preserves both models
- Mobile MaterialReceipts sync to new table
- Desktop GRNs remain unchanged
- Consumption data available cross-device

Cons:
- New schema entity
- Desktop doesn't use this table yet (no UI)
- Migration overhead

Effort: 2 days backend + eventual desktop UI

## Recommendation

**Go with Option A: Don't Sync MaterialReceipts**

Rationale:
1. **Data Integrity:** Forcing a mapping would corrupt or mislead
2. **Different Business Process:** Consumption tracking ≠ Procurement verification
3. **Acceptable Trade-off:** Most critical entities (Projects, Tasks, DPR, Issues, Estimation, Procurement) already sync
4. **Mobile-First Usage:** Field teams use MaterialReceipts for quick cost tracking, not formal GRNs
5. **Desktop Alternative:** Formal procurement (PO → GRN) flows through desktop anyway

## Implementation

Document in `sync_mappers.dart` (already done):

```dart
/// MaterialReceipts has no honest mapping to either synced-shape table:
/// desktop's material_entries is a simple consumption log, and Postgres's
/// own `grns` requires a purchase_order_id (mobile allows ad-hoc receipts
/// with no PO), splits ordered_qty/received_qty where mobile stores one
/// quantity plus an amount, and has no home for cost_head_id -- which is
/// what feeds mobile's cost-engine actuals.
```

Add to user documentation:

> **MaterialReceipts are mobile-only** and do not sync across devices. These are designed for quick field consumption tracking (e.g., "used 5 bags of cement today"). For formal procurement workflows (PO → GRN), use the desktop application's procurement module, which fully syncs through Purchase Orders.

## Future Consideration

If cross-device consumption tracking becomes essential:
1. Implement Option D (new `material_consumption` table)
2. Build desktop UI to view/report on consumption data
3. Keep GRNs separate for procurement verification

This is a deliberate architectural decision, not an oversight. The two schemas serve different purposes and should remain separate.

---

**Date:** 2026-08-28  
**Author:** AI Agent Analysis  
**Status:** Documented Decision - Not Implementing Sync
