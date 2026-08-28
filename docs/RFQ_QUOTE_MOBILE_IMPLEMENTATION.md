# RFQ/Quote Mobile Implementation Plan

## Executive Summary

**Status:** Not Yet Implemented  
**Scope:** Medium-Large Feature (~3-4 hours)  
**Priority:** Medium (procurement chain gap after Purchase Orders)

RFQ (Request for Quotation) and Quote entities complete the procurement workflow: Purchase Request → RFQ → Quote → Purchase Order → GRN. Currently, mobile apps can create Purchase Requests and Purchase Orders, but the RFQ/Quote step is missing.

## Current State

### Backend (fieldos/models.py)
```python
class RFQ(Base):
    __tablename__ = "rfqs"
    id, project_id, requisition_id, title, deadline, status, created_by, created_at
    
class Quote(Base):
    __tablename__ = "quotes"
    id, rfq_id, vendor_id, total_amount, delivery_days, payment_terms, notes, status, created_at
```

### Postgres (supabase/migrations)
```sql
create table rfqs (
  id uuid, project_id uuid, requisition_id uuid, 
  title text, deadline date, 
  status text check (status in ('open', 'closed', 'awarded')),
  created_by uuid, created_at timestamptz
);

create table quotes (
  id uuid, rfq_id uuid, vendor_id uuid,
  total_amount numeric(14,2), delivery_days integer,
  payment_terms text, notes text,
  status text check (status in ('received', 'accepted', 'rejected')),
  created_at timestamptz
);
```

### Mobile: **NO TABLES EXIST**

## Implementation Plan

### Phase 1: Drift Tables (30 minutes)

Add to `lib/data/tables.dart`:

```dart
/// Request for Quotation sent to multiple vendors for price comparison.
class Rfqs extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get requisitionId => text().withLength(max: 36).nullable()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get deadline => dateTime().nullable()();
  /// Status: 'open', 'closed', 'awarded'
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Vendor quote in response to an RFQ.
class Quotes extends Table {
  TextColumn get id => text()();
  TextColumn get rfqId => text().withLength(min: 1, max: 36)();
  TextColumn get vendorId => text().withLength(min: 1, max: 36)();
  RealColumn get totalAmount => real()();
  IntColumn get deliveryDays => integer().nullable()();
  TextColumn get paymentTerms => text().withLength(max: 200).nullable()();
  TextColumn get notes => text().nullable()();
  /// Status: 'received', 'accepted', 'rejected'
  TextColumn get status => text().withDefault(const Constant('received'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

**Migration Step:**
- Increment `schemaVersion` in `app_database.dart` (currently 4 → 5)
- Add migration in `AppDatabase.migration.onUpgrade`:

```dart
if (from < 5) {
  await m.createTable(rfqs);
  await m.createTable(quotes);
}
```

### Phase 2: DAOs (45 minutes)

Add to `lib/data/app_database.dart`:

```dart
@DriftAccessor(tables: [Rfqs, Quotes])
class RfqDao extends DatabaseAccessor<AppDatabase> with _$RfqDaoMixin {
  RfqDao(AppDatabase db) : super(db);

  // ---- RFQs ----
  
  Future<List<Rfq>> forProject(String projectId) =>
      (select(rfqs)..where((t) => t.projectId.equals(projectId)))
          .get();

  Future<Rfq?> byId(String id) =>
      (select(rfqs)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> create(RfqsCompanion rfq) => into(rfqs).insert(rfq);

  Future<void> updateStatus(String id, String status) =>
      (update(rfqs)..where((t) => t.id.equals(id)))
          .write(RfqsCompanion(status: Value(status)));

  Future<void> upsertFromRemote(RfqsCompanion rfq) =>
      into(rfqs).insertOnConflictUpdate(rfq);

  // ---- Quotes ----
  
  Future<List<Quote>> quotesForRfq(String rfqId) =>
      (select(quotes)..where((t) => t.rfqId.equals(rfqId)))
          .get();

  Future<Quote?> quoteById(String id) =>
      (select(quotes)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> createQuote(QuotesCompanion quote) => 
      into(quotes).insert(quote);

  Future<void> updateQuoteStatus(String id, String status) =>
      (update(quotes)..where((t) => t.id.equals(id)))
          .write(QuotesCompanion(status: Value(status)));

  Future<void> upsertQuoteFromRemote(QuotesCompanion quote) =>
      into(quotes).insertOnConflictUpdate(quote);
}
```

Update `AppDatabase` class:

```dart
@DriftDatabase(
  tables: [...existing..., Rfqs, Quotes],
  daos: [...existing..., RfqDao],
)
class AppDatabase extends _$AppDatabase {
  // ...
  RfqDao get rfqDao => RfqDao(this);
  // ...
}
```

### Phase 3: Providers (10 minutes)

Add to `lib/providers.dart`:

```dart
/// RFQ list per project
final rfqsProvider = FutureProvider.autoDispose.family<List<Rfq>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).rfqDao.forProject(projectId));

/// Quotes for a specific RFQ
final quotesProvider = FutureProvider.autoDispose.family<List<Quote>, String>(
    (ref, rfqId) => ref.watch(appDatabaseProvider).rfqDao.quotesForRfq(rfqId));
```

### Phase 4: UI Screens (90 minutes)

#### Option A: Add RFQ Tab to ProcurementView

Update `procurement_screen.dart`:

```dart
// Add RFQ tab to TabBar
TabBar(
  tabs: [
    Tab(text: 'Suppliers'),
    Tab(text: 'Requests'),
    Tab(text: 'RFQs'),        // NEW
    Tab(text: 'Quotes'),      // NEW
    Tab(text: 'Orders'),
    Tab(text: 'GRN'),
  ],
)

// Add views
TabBarView(
  children: [
    _SuppliersTab(...),
    _RequestsTab(...),
    _RfqsTab(projectId: projectId, userId: userId),     // NEW
    _QuotesTab(projectId: projectId, userId: userId),   // NEW
    _OrdersTab(...),
    _GrnTab(...),
  ],
)
```

#### RFQ Tab Implementation

```dart
class _RfqsTab extends ConsumerWidget {
  const _RfqsTab({required this.projectId, required this.userId});
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rfqs = ref.watch(rfqsProvider(projectId));
    return Column(
      children: [
        _sectionHeader(context, 'RFQs', () => _addRfq(context, ref)),
        Expanded(
          child: rfqs.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No RFQs yet.'))
                : ListView(
                    children: rows.map((rfq) =>
                      _RfqTile(rfq: rfq, projectId: projectId, userId: userId)
                    ).toList(),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
      ],
    );
  }

  Future<void> _addRfq(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final deadline = TextEditingController();
    
    // Optional: link to a Purchase Request
    final requests = await ref.read(requestsProvider(projectId).future);
    String? selectedRequisitionId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Create RFQ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'RFQ Title'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Link to Request (optional)'),
                value: selectedRequisitionId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('No link')),
                  ...requests.map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.materialName),
                      )),
                ],
                onChanged: (v) => setDialogState(() => selectedRequisitionId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: deadline,
                decoration: const InputDecoration(labelText: 'Deadline (optional)'),
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(Duration(days: 365)),
                  );
                  if (picked != null) {
                    deadline.text = picked.toIso8601String().split('T').first;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    final rfqId = const Uuid().v4();
    
    await db.rfqDao.create(RfqsCompanion.insert(
      id: rfqId,
      projectId: projectId,
      requisitionId: Value(selectedRequisitionId),
      title: title.text.trim(),
      deadline: deadline.text.isEmpty
          ? const Value.absent()
          : Value(DateTime.parse(deadline.text)),
      createdBy: userId,
    ));
    
    // Enqueue sync
    await db.syncOutboxDao.enqueue(
      targetTable: 'rfqs',
      recordId: rfqId,
      operation: 'insert',
      payloadJson: jsonEncode(rfqToSupabaseJson(/* ... */)),
    );

    ref.invalidate(rfqsProvider(projectId));
  }
}

class _RfqTile extends ConsumerWidget {
  const _RfqTile({required this.rfq, required this.projectId, required this.userId});
  final Rfq rfq;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesCount = ref.watch(quotesProvider(rfq.id)).valueOrNull?.length ?? 0;
    
    return Card(
      child: ListTile(
        title: Text(rfq.title),
        subtitle: Text(
          'Status: ${rfq.status} · $quotesCount quote${quotesCount == 1 ? '' : 's'}'
          '${rfq.deadline != null ? ' · Due ${rfq.deadline!.toLocal().toString().split(" ").first}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.format_quote),
          tooltip: 'View quotes',
          onPressed: () => _viewQuotes(context, ref),
        ),
        onTap: () => _viewQuotes(context, ref),
      ),
    );
  }

  Future<void> _viewQuotes(BuildContext context, WidgetRef ref) async {
    final quotes = await ref.read(quotesProvider(rfq.id).future);
    final suppliers = await ref.read(suppliersProvider(/* companyId */).future);
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quotes for ${rfq.title}'),
        content: SizedBox(
          width: 400,
          child: quotes.isEmpty
              ? const Text('No quotes received yet.')
              : ListView(
                  shrinkWrap: true,
                  children: quotes.map((q) {
                    final vendor = suppliers.firstWhere(
                      (s) => s.id == q.vendorId,
                      orElse: () => Supplier(
                        id: q.vendorId,
                        companyId: '',
                        name: 'Unknown',
                        createdAt: DateTime.now(),
                      ),
                    );
                    return ListTile(
                      title: Text(vendor.name),
                      subtitle: Text(
                        '₹${q.totalAmount} · ${q.deliveryDays ?? '?'} days'
                        '${q.status != 'received' ? ' · ${q.status}' : ''}',
                      ),
                      trailing: q.status == 'received'
                          ? PopupMenuButton<String>(
                              onSelected: (action) => _handleQuoteAction(ctx, ref, q, action),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'accept', child: Text('Accept')),
                                const PopupMenuItem(value: 'reject', child: Text('Reject')),
                              ],
                            )
                          : null,
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () => _addQuote(context, ref),
            child: const Text('Add quote'),
          ),
        ],
      ),
    );
  }

  Future<void> _addQuote(BuildContext context, WidgetRef ref) async {
    final suppliers = await ref.read(suppliersProvider(/* companyId */).future);
    
    String? selectedVendorId;
    final amount = TextEditingController();
    final deliveryDays = TextEditingController();
    final paymentTerms = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Add vendor quote'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Vendor'),
                  value: selectedVendorId,
                  items: suppliers.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name),
                      )).toList(),
                  onChanged: (v) => setDialogState(() => selectedVendorId = v),
                ),
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Total amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: deliveryDays,
                  decoration: const InputDecoration(labelText: 'Delivery days'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: paymentTerms,
                  decoration: const InputDecoration(labelText: 'Payment terms'),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || selectedVendorId == null || !context.mounted) return;

    final db = ref.read(appDatabaseProvider);
    final quoteId = const Uuid().v4();
    
    await db.rfqDao.createQuote(QuotesCompanion.insert(
      id: quoteId,
      rfqId: rfq.id,
      vendorId: selectedVendorId,
      totalAmount: double.tryParse(amount.text) ?? 0,
      deliveryDays: Value(int.tryParse(deliveryDays.text)),
      paymentTerms: Value(paymentTerms.text.trim().isEmpty ? null : paymentTerms.text.trim()),
      notes: Value(notes.text.trim().isEmpty ? null : notes.text.trim()),
    ));
    
    // Enqueue sync
    await db.syncOutboxDao.enqueue(
      targetTable: 'quotes',
      recordId: quoteId,
      operation: 'insert',
      payloadJson: jsonEncode(quoteToSupabaseJson(/* ... */)),
    );

    ref.invalidate(quotesProvider(rfq.id));
  }

  Future<void> _handleQuoteAction(
    BuildContext context,
    WidgetRef ref,
    Quote quote,
    String action,
  ) async {
    final db = ref.read(appDatabaseProvider);
    
    if (action == 'accept') {
      await db.rfqDao.updateQuoteStatus(quote.id, 'accepted');
      await db.rfqDao.updateStatus(rfq.id, 'awarded');
      
      // Optionally: auto-create PO from accepted quote
      // await _createPoFromQuote(quote);
    } else if (action == 'reject') {
      await db.rfqDao.updateQuoteStatus(quote.id, 'rejected');
    }
    
    ref.invalidate(quotesProvider(rfq.id));
    ref.invalidate(rfqsProvider(projectId));
  }
}
```

### Phase 5: Sync Mappers (20 minutes)

Add to `lib/sync/sync_mappers.dart`:

```dart
// ---- RFQs ----

Map<String, dynamic> rfqToSupabaseJson(Rfq r) => {
      'id': r.id,
      'project_id': r.projectId,
      'requisition_id': r.requisitionId,
      'title': r.title,
      'deadline': _dateOnly(r.deadline),
      'status': r.status,
      'created_by': r.createdBy,
    };

RfqsCompanion rfqFromSupabaseJson(Map<String, dynamic> row) => RfqsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      requisitionId: Value(row['requisition_id'] as String?),
      title: row['title'] as String,
      deadline: Value(row['deadline'] == null ? null : DateTime.parse(row['deadline'] as String)),
      status: Value(row['status'] as String? ?? 'open'),
      createdBy: row['created_by'] as String,
    );

// ---- Quotes ----

Map<String, dynamic> quoteToSupabaseJson(Quote q) => {
      'id': q.id,
      'rfq_id': q.rfqId,
      'vendor_id': q.vendorId,
      'total_amount': q.totalAmount,
      'delivery_days': q.deliveryDays,
      'payment_terms': q.paymentTerms,
      'notes': q.notes,
      'status': q.status,
    };

QuotesCompanion quoteFromSupabaseJson(Map<String, dynamic> row) => QuotesCompanion.insert(
      id: row['id'] as String,
      rfqId: row['rfq_id'] as String,
      vendorId: row['vendor_id'] as String,
      totalAmount: (row['total_amount'] as num).toDouble(),
      deliveryDays: Value(row['delivery_days'] as int?),
      paymentTerms: Value(row['payment_terms'] as String?),
      notes: Value(row['notes'] as String?),
      status: Value(row['status'] as String? ?? 'received'),
    );
```

### Phase 6: Sync Engine Integration (15 minutes)

Add to `SyncEngine.pullAll()`:

```dart
// RFQs
final rfqRows = await client.from('rfqs').select();
for (final row in rfqRows) {
  await db.rfqDao.upsertFromRemote(rfqFromSupabaseJson(row));
}

// Quotes
final quoteRows = await client.from('quotes').select();
for (final row in quoteRows) {
  await db.rfqDao.upsertQuoteFromRemote(quoteFromSupabaseJson(row));
}
```

Add to `SyncEngine.pushPending()` (already handles 'rfqs' and 'quotes' tables generically via existing upsert logic).

### Phase 7: Testing (30 minutes)

Create `test/rfq_quote_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('create RFQ and add quotes', () async {
    // Setup: create project and suppliers
    final projectId = 'proj-1';
    final vendorId1 = 'vendor-1';
    final vendorId2 = 'vendor-2';

    // Create RFQ
    final rfqId = 'rfq-1';
    await db.rfqDao.create(RfqsCompanion.insert(
      id: rfqId,
      projectId: projectId,
      title: 'Need 100 bags of cement',
      createdBy: 'user-1',
    ));

    final rfqs = await db.rfqDao.forProject(projectId);
    expect(rfqs.length, 1);
    expect(rfqs[0].title, 'Need 100 bags of cement');
    expect(rfqs[0].status, 'open');

    // Add quotes
    await db.rfqDao.createQuote(QuotesCompanion.insert(
      id: 'quote-1',
      rfqId: rfqId,
      vendorId: vendorId1,
      totalAmount: 45000,
      deliveryDays: Value(7),
    ));

    await db.rfqDao.createQuote(QuotesCompanion.insert(
      id: 'quote-2',
      rfqId: rfqId,
      vendorId: vendorId2,
      totalAmount: 42000,
      deliveryDays: Value(10),
    ));

    final quotes = await db.rfqDao.quotesForRfq(rfqId);
    expect(quotes.length, 2);
    expect(quotes[0].totalAmount, 45000);
    expect(quotes[1].totalAmount, 42000);
  });

  test('accept quote updates status', () async {
    // Setup RFQ and quote
    final rfqId = 'rfq-1';
    final quoteId = 'quote-1';

    await db.rfqDao.create(RfqsCompanion.insert(
      id: rfqId,
      projectId: 'proj-1',
      title: 'RFQ',
      createdBy: 'user-1',
    ));

    await db.rfqDao.createQuote(QuotesCompanion.insert(
      id: quoteId,
      rfqId: rfqId,
      vendorId: 'vendor-1',
      totalAmount: 50000,
    ));

    // Accept quote
    await db.rfqDao.updateQuoteStatus(quoteId, 'accepted');
    await db.rfqDao.updateStatus(rfqId, 'awarded');

    final rfq = await db.rfqDao.byId(rfqId);
    final quote = await db.rfqDao.quoteById(quoteId);

    expect(rfq?.status, 'awarded');
    expect(quote?.status, 'accepted');
  });
}
```

## Workflow Example

1. **Site Engineer creates Purchase Request** for "100 bags cement"
2. **Project Manager creates RFQ** titled "Cement procurement - 100 bags"
   - Links to the Purchase Request
   - Sets deadline: 7 days from now
3. **PM adds quotes manually** (or vendors submit via desktop):
   - Vendor A: ₹45,000, 7 days delivery
   - Vendor B: ₹42,000, 10 days delivery
   - Vendor C: ₹47,000, 5 days delivery
4. **PM accepts Vendor B's quote** → RFQ status → 'awarded'
5. **PM creates Purchase Order** from accepted quote (existing PO flow)

## Integration with Existing Flows

- **Purchase Request → RFQ:** Optional link via `requisitionId`
- **Quote → Purchase Order:** PO's `quote_id` field preserves linkage
- **Sync:** Full bidirectional sync with Supabase (desktop can create RFQs, mobile can view/add quotes)

## Effort Breakdown

| Phase | Time | Complexity |
|-------|------|------------|
| Drift tables + migration | 30 min | Low |
| DAOs | 45 min | Low |
| Providers | 10 min | Low |
| UI screens | 90 min | Medium |
| Sync mappers | 20 min | Low |
| Sync engine | 15 min | Low |
| Testing | 30 min | Low |
| **Total** | **~3.5 hours** | **Medium** |

## Dependencies

- Suppliers table (✅ exists and syncs)
- Purchase Requests table (✅ exists and syncs)
- Purchase Orders table (✅ exists and syncs)

## Production Checklist

- [ ] Drift tables added and migration created
- [ ] DAO methods for CRUD operations
- [ ] Providers registered
- [ ] UI screens with create/view/update flows
- [ ] Sync mappers for bidirectional sync
- [ ] SyncEngine integration for push/pull
- [ ] Unit tests (create, quote, accept workflow)
- [ ] Integration test (sync to Postgres and back)
- [ ] RLS policies verified in Postgres
- [ ] Update AGENT_HANDOFF.md with new entity coverage

## Future Enhancements

1. **Auto-create PO from accepted quote** (1-click conversion)
2. **Quote comparison view** (side-by-side table)
3. **File attachments** for quotes (vendor PDFs)
4. **Notifications** when new quotes arrive (requires push notifications)
5. **Desktop vendor portal** where vendors can submit quotes directly

---

**Date:** 2026-08-28  
**Author:** AI Agent Analysis  
**Status:** Design Complete - Ready for Implementation  
**Priority:** Medium (completes procurement chain)
