/// The report library: about fifty ready reports over what the company has
/// already recorded, for one site, several or all of them, over a period.
/// Each report is a plain table (headers, rows, totals) so the same thing
/// goes to the screen, a PDF and an Excel sheet. Everything is worked out
/// on the phone, offline.
library;

import 'package:drift/drift.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart' show isOpenStage, isFollowUpDue, leadValue;
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart' show advanceOwed, monthKey;
import 'package:fieldos_mobile/features/procurement/quote_compare.dart' show compareQuotes;
import 'package:fieldos_mobile/features/procurement/site_stock.dart' show buildSiteStock, isOpeningStock;
import 'package:fieldos_mobile/features/project/task_plan.dart' show isOverdue, daysOverdue;
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart' show storeStock, shortage, arrivedQty;

/// Who may open a report. Money received is for owners and managers only
/// (as on the money screens); salaries, sales and the company stores for
/// owners and project managers.
enum ReportAccess { everyone, moneyIn, managers }

enum ReportGroup { progress, labour, material, stores, money, subcontract, equipment, staff, sales }

const reportGroupLabels = {
  ReportGroup.progress: 'Progress',
  ReportGroup.labour: 'Labour',
  ReportGroup.material: 'Material and purchase',
  ReportGroup.stores: 'Stores and tools',
  ReportGroup.money: 'Money',
  ReportGroup.subcontract: 'Subcontractors',
  ReportGroup.equipment: 'Equipment',
  ReportGroup.staff: 'Staff salaries',
  ReportGroup.sales: 'Sales',
};

/// One report's result. Cells are String, num, DateTime or null.
class ReportTable {
  ReportTable(this.headers, this.rows, {this.sumColumns = const {}, this.note});
  final List<String> headers;
  final List<List<Object?>> rows;

  /// Columns that get a total at the foot.
  final Set<int> sumColumns;
  final String? note;

  List<Object?>? get totals {
    if (sumColumns.isEmpty || rows.isEmpty) return null;
    return [
      for (var i = 0; i < headers.length; i++)
        if (i == 0)
          'Total'
        else if (sumColumns.contains(i))
          rows.fold<double>(0, (s, r) => s + ((r[i] as num?)?.toDouble() ?? 0))
        else
          null,
    ];
  }
}

class ReportDef {
  const ReportDef(
    this.id,
    this.group,
    this.title,
    this.about,
    this.build, {
    this.access = ReportAccess.everyone,
    this.usesPeriod = true,
  });
  final String id;
  final ReportGroup group;
  final String title;
  final String about;
  final ReportAccess access;

  /// False for registers (who is on site, which tools exist): they show
  /// today's state whatever period is picked.
  final bool usesPeriod;
  final ReportTable Function(ReportInput d) build;
}

/// Everything the reports read, for the chosen sites and period, loaded
/// once.
class ReportInput {
  ReportInput({
    required this.sites,
    required this.from,
    required this.to,
    required this.now,
    this.users = const {},
    this.tasks = const [],
    this.dprs = const [],
    this.issues = const [],
    this.inspections = const [],
    this.documents = const [],
    this.attendance = const [],
    this.marks = const [],
    this.workers = const [],
    this.receipts = const [],
    this.usage = const [],
    this.requests = const [],
    this.orders = const [],
    this.suppliers = const [],
    this.supplierInvoices = const [],
    this.supplierQuotes = const [],
    this.expenses = const [],
    this.payments = const [],
    this.bills = const [],
    this.subcontractors = const [],
    this.workOrders = const [],
    this.variations = const [],
    this.variationDecisions = const [],
    this.equipment = const [],
    this.equipmentLogs = const [],
    this.approvals = const [],
    this.stores = const [],
    this.moves = const [],
    this.tools = const [],
    this.toolIssues = const [],
    this.staff = const [],
    this.advances = const [],
    this.payroll = const [],
    this.leads = const [],
    this.crmQuotes = const [],
  });

  final List<Project> sites;

  /// First day (midnight) and the day after the last (exclusive).
  final DateTime from;
  final DateTime to;
  final DateTime now;
  final Map<String, String> users;
  final List<Task> tasks;
  final List<DprEntry> dprs;
  final List<Issue> issues;
  final List<Inspection> inspections;
  final List<Document> documents;
  final List<LabourAttendanceData> attendance;
  final List<AttendanceMark> marks;
  final List<Worker> workers;
  final List<MaterialReceipt> receipts;
  final List<MaterialUsageData> usage;
  final List<PurchaseRequest> requests;
  final List<PurchaseOrder> orders;
  final List<Supplier> suppliers;
  final List<SupplierInvoice> supplierInvoices;
  final List<SupplierQuote> supplierQuotes;
  final List<SiteExpense> expenses;
  final List<PaymentsReceivedData> payments;
  final List<ClientBill> bills;
  final List<Subcontractor> subcontractors;
  final List<WorkOrder> workOrders;
  final List<Variation> variations;
  final List<VariationDecision> variationDecisions;
  final List<EquipmentData> equipment;
  final List<EquipmentLog> equipmentLogs;
  final List<Approval> approvals;
  final List<Store> stores;
  final List<StockMove> moves;
  final List<Tool> tools;
  final List<ToolIssue> toolIssues;
  final List<StaffMember> staff;
  final List<StaffAdvance> advances;
  final List<PayrollLine> payroll;
  final List<CrmLead> leads;
  final List<CrmQuote> crmQuotes;

  late final Map<String, String> siteName = {for (final s in sites) s.id: s.name};
  late final Set<String> siteIds = siteName.keys.toSet();
  late final Map<String, String> supplierName = {for (final s in suppliers) s.id: s.name};
  late final Map<String, String> storeName = {for (final s in stores) s.id: s.name};

  String site(String? id) => id == null ? '' : (siteName[id] ?? '');
  String user(String? id) => id == null ? '' : (users[id] ?? '');

  bool inPeriod(DateTime? t) {
    if (t == null) return false;
    final l = t.toLocal();
    return !l.isBefore(from) && l.isBefore(to);
  }

  /// SQLite date text ("2026-11-10") to a date.
  bool inPeriodDay(String day) => inPeriod(parseDay(day));

  /// Where a move went or came from, by name.
  String place(String? storeId, String? projectId) =>
      storeId != null ? (storeName[storeId] ?? '') : (projectId != null ? (siteName[projectId] ?? '') : '');
}

DateTime? parseDay(String s) {
  final t = DateTime.tryParse(s.trim());
  return t == null ? null : DateTime(t.year, t.month, t.day);
}

DateTime _day(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

String _word(String? code) {
  if (code == null || code.isEmpty) return '';
  final s = code.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// Sums [value] by [key], largest first.
List<MapEntry<String, double>> _sumBy<T>(Iterable<T> xs, String Function(T) key, double Function(T) value) {
  final m = <String, double>{};
  for (final x in xs) {
    m[key(x)] = (m[key(x)] ?? 0) + value(x);
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

int _byDate<T>(DateTime a, DateTime b) => a.compareTo(b);

// ---------------------------------------------------------------------------
// The reports.
// ---------------------------------------------------------------------------

final List<ReportDef> reportLibrary = [
  // --- Progress -----------------------------------------------------------
  ReportDef('dpr-log', ReportGroup.progress, 'Daily reports', 'Each day\'s report: people on site, weather and work done.', (d) {
    final xs = d.dprs.where((e) => d.inPeriod(e.entryDate)).toList()..sort((a, b) => _byDate(a.entryDate, b.entryDate));
    return ReportTable(
      ['Date', 'Site', 'People', 'Weather', 'Work done', 'By'],
      [
        for (final e in xs)
          [_day(e.entryDate), d.site(e.projectId), e.manpowerCount, e.weather ?? '', e.workSummary, d.user(e.createdBy)],
      ],
      sumColumns: {2},
    );
  }),
  ReportDef(
    'manpower',
    ReportGroup.progress,
    'People on site by day',
    'How many people each site had each day, from the daily reports.',
    (d) {
      final m = <String, int>{};
      final days = <String, DateTime>{};
      for (final e in d.dprs.where((e) => d.inPeriod(e.entryDate))) {
        final k = '${_day(e.entryDate).toIso8601String()}|${e.projectId}';
        m[k] = (m[k] ?? 0) + e.manpowerCount;
        days[k] = _day(e.entryDate);
      }
      final keys = m.keys.toList()..sort();
      return ReportTable(
        ['Date', 'Site', 'People'],
        [
          for (final k in keys) [days[k], d.site(k.split('|')[1]), m[k]],
        ],
        sumColumns: {2},
      );
    },
  ),
  ReportDef('tasks', ReportGroup.progress, 'Task status', 'Every task with its progress, dates and whether it is late.', (d) {
    final xs = [...d.tasks]..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
    return ReportTable(
      ['Site', 'Task', 'Status', 'Progress %', 'Start', 'Due', 'Days late'],
      [
        for (final t in xs)
          [
            d.site(t.projectId),
            t.title,
            _word(t.status),
            t.progress,
            t.startDate,
            t.dueDate,
            isOverdue(t, d.now) ? daysOverdue(t, d.now) : null,
          ],
      ],
    );
  }, usesPeriod: false),
  ReportDef('late-tasks', ReportGroup.progress, 'Late tasks', 'Open tasks past their due date, most late first.', (d) {
    final xs = d.tasks.where((t) => isOverdue(t, d.now)).toList()
      ..sort((a, b) => daysOverdue(b, d.now).compareTo(daysOverdue(a, d.now)));
    return ReportTable(
      ['Site', 'Task', 'Due', 'Days late', 'Progress %', 'Who'],
      [
        for (final t in xs) [d.site(t.projectId), t.title, t.dueDate, daysOverdue(t, d.now), t.progress, d.user(t.assigneeId)],
      ],
    );
  }, usesPeriod: false),
  ReportDef('tasks-done', ReportGroup.progress, 'Tasks finished', 'Tasks marked done in the period.', (d) {
    final xs = d.tasks.where((t) => t.status == 'done' && d.inPeriod(t.updatedAt)).toList()
      ..sort((a, b) => _byDate(a.updatedAt, b.updatedAt));
    return ReportTable(
      ['Finished', 'Site', 'Task', 'Due', 'On time'],
      [
        for (final t in xs)
          [
            _day(t.updatedAt),
            d.site(t.projectId),
            t.title,
            t.dueDate,
            t.dueDate == null ? '' : (_day(t.updatedAt).isAfter(_day(t.dueDate!)) ? 'No' : 'Yes'),
          ],
      ],
    );
  }),
  ReportDef('issues', ReportGroup.progress, 'Issues register', 'Issues raised in the period, with how long each took to fix.', (
    d,
  ) {
    final xs = d.issues.where((i) => d.inPeriod(i.createdAt)).toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Raised', 'Site', 'Issue', 'Severity', 'Status', 'Fixed', 'Days open'],
      [
        for (final i in xs)
          [
            _day(i.createdAt),
            d.site(i.projectId),
            i.description,
            _word(i.severity),
            _word(i.status),
            i.resolvedAt,
            (i.resolvedAt ?? d.now).difference(i.createdAt).inDays,
          ],
      ],
    );
  }),
  ReportDef('open-issues', ReportGroup.progress, 'Open issues by age', 'Issues not yet fixed, oldest first.', (d) {
    final xs = d.issues.where((i) => i.status != 'resolved').toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Raised', 'Site', 'Issue', 'Severity', 'Days open'],
      [
        for (final i in xs)
          [_day(i.createdAt), d.site(i.projectId), i.description, _word(i.severity), d.now.difference(i.createdAt).inDays],
      ],
    );
  }, usesPeriod: false),
  ReportDef('inspections', ReportGroup.progress, 'Inspections', 'Quality and safety inspections with their results.', (d) {
    final xs = d.inspections.where((i) => d.inPeriod(i.scheduledDate ?? i.completedDate ?? i.createdAt)).toList()
      ..sort((a, b) => _byDate(a.scheduledDate ?? a.createdAt, b.scheduledDate ?? b.createdAt));
    return ReportTable(
      ['Planned', 'Site', 'Inspection', 'Type', 'Status', 'Done on', 'Result'],
      [
        for (final i in xs)
          [
            i.scheduledDate,
            d.site(i.projectId),
            i.title,
            _word(i.inspectionType),
            _word(i.status),
            i.completedDate,
            _word(i.overallResult),
          ],
      ],
    );
  }),
  ReportDef('documents', ReportGroup.progress, 'Documents register', 'Drawings and documents on each site, latest version.', (d) {
    final xs = [...d.documents]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ReportTable(
      ['Site', 'Document', 'Kind', 'Version', 'Added', 'By'],
      [
        for (final x in xs) [d.site(x.projectId), x.name, _word(x.category), x.version, _day(x.createdAt), d.user(x.uploadedBy)],
      ],
    );
  }, usesPeriod: false),
  ReportDef('approvals', ReportGroup.progress, 'Approvals waiting', 'Requests still waiting for a decision, oldest first.', (d) {
    final xs = d.approvals.where((a) => a.status == 'pending').toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Asked', 'Site', 'What', 'Asked by', 'Days waiting'],
      [
        for (final a in xs)
          [
            _day(a.createdAt),
            d.site(a.projectId),
            _word(a.entityType),
            d.user(a.requestedBy),
            d.now.difference(a.createdAt).inDays,
          ],
      ],
    );
  }, usesPeriod: false),

  // --- Labour -------------------------------------------------------------
  ReportDef(
    'punches',
    ReportGroup.labour,
    'Attendance punches',
    'Each punch in and out, hours, and whether it was at the site.',
    (d) {
      final xs = d.attendance.where((a) => d.inPeriod(a.punchIn)).toList()..sort((a, b) => _byDate(a.punchIn, b.punchIn));
      return ReportTable(
        ['Date', 'Site', 'Worker', 'In', 'Out', 'Hours', 'At site'],
        [
          for (final a in xs)
            [
              _day(a.punchIn),
              d.site(a.projectId),
              a.workerName,
              a.punchIn.toLocal(),
              a.punchOut?.toLocal(),
              a.punchOut == null ? null : _r2(a.punchOut!.difference(a.punchIn).inMinutes / 60),
              a.withinGeofence == null ? '' : (a.withinGeofence! ? 'Yes' : 'No'),
            ],
        ],
        sumColumns: {5},
      );
    },
  ),
  ReportDef(
    'outside-geofence',
    ReportGroup.labour,
    'Punches away from site',
    'Punches made outside the site boundary, to check.',
    (d) {
      final xs = d.attendance.where((a) => d.inPeriod(a.punchIn) && a.withinGeofence == false).toList()
        ..sort((a, b) => _byDate(a.punchIn, b.punchIn));
      return ReportTable(
        ['Date', 'Site', 'Worker', 'In', 'By'],
        [
          for (final a in xs) [_day(a.punchIn), d.site(a.projectId), a.workerName, a.punchIn.toLocal(), d.user(a.recordedBy)],
        ],
      );
    },
  ),
  ReportDef('worker-days', ReportGroup.labour, 'Days worked by worker', 'Days marked on the wage sheet for each worker.', (d) {
    final workers = {for (final w in d.workers) w.id: w};
    final m = <String, double>{};
    for (final x in d.marks.where((x) => d.inPeriodDay(x.day))) {
      m[x.workerId] = (m[x.workerId] ?? 0) + (x.units ?? 1);
    }
    final ids = m.keys.toList()..sort((a, b) => (workers[a]?.name ?? '').compareTo(workers[b]?.name ?? ''));
    return ReportTable(
      ['Worker', 'Site', 'Role', 'Days'],
      [
        for (final id in ids) [workers[id]?.name ?? '', d.site(workers[id]?.projectId), workers[id]?.role ?? '', m[id]],
      ],
      sumColumns: {3},
    );
  }),
  ReportDef('wages-due', ReportGroup.labour, 'Wages earned', 'Days marked times the daily wage, for each worker.', (d) {
    final workers = {for (final w in d.workers) w.id: w};
    final m = <String, double>{};
    for (final x in d.marks.where((x) => d.inPeriodDay(x.day))) {
      m[x.workerId] = (m[x.workerId] ?? 0) + (x.units ?? 1);
    }
    final ids = m.keys.toList()..sort((a, b) => (workers[a]?.name ?? '').compareTo(workers[b]?.name ?? ''));
    return ReportTable(
      ['Worker', 'Site', 'Days', 'Daily wage', 'Earned'],
      [
        for (final id in ids)
          [
            workers[id]?.name ?? '',
            d.site(workers[id]?.projectId),
            m[id],
            workers[id]?.dailyWage,
            _r2(m[id]! * (workers[id]?.dailyWage ?? 0)),
          ],
      ],
      sumColumns: {2, 4},
    );
  }),
  ReportDef('workers', ReportGroup.labour, 'Workers list', 'Everyone on the wage sheet, with role, phone and wage.', (d) {
    final xs = [...d.workers]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ReportTable(
      ['Worker', 'Site', 'Role', 'Phone', 'Daily wage', 'Status'],
      [
        for (final w in xs) [w.name, d.site(w.projectId), w.role ?? '', w.phone ?? '', w.dailyWage, _word(w.status)],
      ],
    );
  }, usesPeriod: false),

  // --- Material and purchase -----------------------------------------------
  ReportDef('grn', ReportGroup.material, 'Material received', 'Every delivery (GRN) with supplier and amount.', (d) {
    final xs = d.receipts.where((r) => d.inPeriod(r.receivedOn) && !isOpeningStock(r)).toList()
      ..sort((a, b) => _byDate(a.receivedOn, b.receivedOn));
    return ReportTable(
      ['Date', 'Site', 'Material', 'Qty', 'Unit', 'Supplier', 'Amount'],
      [
        for (final r in xs)
          [
            _day(r.receivedOn),
            d.site(r.projectId),
            r.materialName,
            r.quantity,
            r.unit ?? '',
            d.supplierName[r.supplierId] ?? '',
            r.amount,
          ],
      ],
      sumColumns: {6},
    );
  }),
  ReportDef(
    'grn-by-material',
    ReportGroup.material,
    'Received by material',
    'Quantity and amount of each material received, with the average rate.',
    (d) {
      final m = <String, ({String name, String unit, double qty, double amount})>{};
      for (final r in d.receipts.where((r) => d.inPeriod(r.receivedOn) && !isOpeningStock(r))) {
        final k = '${r.materialName.trim().toLowerCase()}|${(r.unit ?? '').trim().toLowerCase()}';
        final o = m[k];
        m[k] = (
          name: o?.name ?? r.materialName.trim(),
          unit: o?.unit ?? (r.unit ?? ''),
          qty: (o?.qty ?? 0) + r.quantity,
          amount: (o?.amount ?? 0) + r.amount,
        );
      }
      final xs = m.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
      return ReportTable(
        ['Material', 'Unit', 'Qty', 'Amount', 'Average rate'],
        [
          for (final x in xs) [x.name, x.unit, x.qty, x.amount, x.qty > 0 ? _r2(x.amount / x.qty) : null],
        ],
        sumColumns: {3},
      );
    },
  ),
  ReportDef('usage', ReportGroup.material, 'Material used', 'Material used on site, day by day.', (d) {
    final xs = d.usage.where((u) => d.inPeriod(u.usedOn)).toList()..sort((a, b) => _byDate(a.usedOn, b.usedOn));
    return ReportTable(
      ['Date', 'Site', 'Material', 'Qty', 'Unit', 'Note'],
      [
        for (final u in xs) [_day(u.usedOn), d.site(u.projectId), u.materialName, u.quantity, u.unit ?? '', u.note ?? ''],
      ],
    );
  }),
  ReportDef(
    'site-stock',
    ReportGroup.material,
    'Site stock',
    'What each site received, got from stores, used, sent on and has left.',
    (d) {
      final rows = <List<Object?>>[];
      for (final s in d.sites) {
        final lines = buildSiteStock(
          [
            for (final r in d.receipts)
              if (r.projectId == s.id) r,
          ],
          [
            for (final u in d.usage)
              if (u.projectId == s.id) u,
          ],
          moves: d.moves,
          projectId: s.id,
        );
        for (final l in lines) {
          rows.add([s.name, l.name, l.unit ?? '', l.received, l.transferredIn, l.used, l.transferredOut, l.balance]);
        }
      }
      return ReportTable(['Site', 'Material', 'Unit', 'Received', 'From stores', 'Used', 'Sent on', 'Left'], rows);
    },
    usesPeriod: false,
  ),
  ReportDef('requests', ReportGroup.material, 'Purchase requests', 'Material asked for, and whether it was ordered.', (d) {
    final xs = d.requests.where((r) => d.inPeriod(r.createdAt)).toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Date', 'Site', 'Material', 'Qty', 'Unit', 'Urgency', 'Status', 'Estimate'],
      [
        for (final r in xs)
          [
            _day(r.createdAt),
            d.site(r.projectId),
            r.materialName,
            r.quantity,
            r.unit,
            _word(r.urgency),
            _word(r.status),
            r.estimatedAmount,
          ],
      ],
      sumColumns: {7},
    );
  }),
  ReportDef('pos', ReportGroup.material, 'Purchase orders', 'Every PO with supplier, amount, delivery date and status.', (d) {
    final xs = d.orders.where((o) => d.inPeriod(o.createdAt)).toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Date', 'Site', 'PO', 'Supplier', 'Amount', 'Delivery', 'Status'],
      [
        for (final o in xs)
          [
            _day(o.createdAt),
            d.site(o.projectId),
            o.poNumber ?? '',
            d.supplierName[o.supplierId] ?? '',
            o.totalAmount,
            o.deliveryDate,
            _word(o.status),
          ],
      ],
      sumColumns: {4},
    );
  }),
  ReportDef('late-pos', ReportGroup.material, 'Late deliveries', 'POs past their delivery date and not yet delivered.', (d) {
    final today = _day(d.now);
    final xs =
        d.orders
            .where(
              (o) =>
                  o.deliveryDate != null &&
                  _day(o.deliveryDate!).isBefore(today) &&
                  o.status != 'delivered' &&
                  o.status != 'cancelled',
            )
            .toList()
          ..sort((a, b) => _byDate(a.deliveryDate!, b.deliveryDate!));
    return ReportTable(
      ['Due', 'Site', 'PO', 'Supplier', 'Amount', 'Days late'],
      [
        for (final o in xs)
          [
            o.deliveryDate,
            d.site(o.projectId),
            o.poNumber ?? '',
            d.supplierName[o.supplierId] ?? '',
            o.totalAmount,
            today.difference(_day(o.deliveryDate!)).inDays,
          ],
      ],
      sumColumns: {4},
    );
  }, usesPeriod: false),
  ReportDef(
    'by-supplier',
    ReportGroup.material,
    'Purchases by supplier',
    'Deliveries and orders from each supplier in the period.',
    (d) {
      final grn = <String, double>{};
      final po = <String, double>{};
      final count = <String, int>{};
      for (final r in d.receipts.where((r) => d.inPeriod(r.receivedOn) && !isOpeningStock(r))) {
        final sid = r.supplierId ?? d.orders.where((o) => o.id == r.poId).map((o) => o.supplierId).firstOrNull;
        if (sid == null) continue;
        grn[sid] = (grn[sid] ?? 0) + r.amount;
        count[sid] = (count[sid] ?? 0) + 1;
      }
      for (final o in d.orders.where((o) => d.inPeriod(o.createdAt) && o.status != 'cancelled')) {
        po[o.supplierId] = (po[o.supplierId] ?? 0) + (o.totalAmount ?? 0);
      }
      final ids = {...grn.keys, ...po.keys}.toList()..sort((a, b) => (grn[b] ?? 0).compareTo(grn[a] ?? 0));
      return ReportTable(
        ['Supplier', 'Deliveries', 'Received worth', 'Ordered worth'],
        [
          for (final id in ids) [d.supplierName[id] ?? '', count[id] ?? 0, grn[id] ?? 0, po[id] ?? 0],
        ],
        sumColumns: {1, 2, 3},
      );
    },
  ),
  ReportDef('supplier-invoices', ReportGroup.material, 'Supplier invoices', 'Invoices entered against POs, with GST.', (d) {
    final xs = d.supplierInvoices.where((i) => !i.voided && d.inPeriod(i.invoiceDate)).toList()
      ..sort((a, b) => _byDate(a.invoiceDate, b.invoiceDate));
    return ReportTable(
      ['Date', 'Site', 'Supplier', 'Invoice', 'Amount', 'GST'],
      [
        for (final i in xs)
          [_day(i.invoiceDate), d.site(i.projectId), d.supplierName[i.supplierId] ?? '', i.invoiceNumber, i.amount, i.gstAmount],
      ],
      sumColumns: {4, 5},
    );
  }),
  ReportDef(
    'quote-savings',
    ReportGroup.material,
    'Savings from quotes',
    'Requests with several supplier quotes: who won and what it saved.',
    (d) {
      final rows = <List<Object?>>[];
      for (final r in d.requests.where((r) => d.inPeriod(r.createdAt))) {
        final qs = [
          for (final q in d.supplierQuotes)
            if (q.requestId == r.id) q,
        ];
        if (qs.isEmpty) continue;
        final c = compareQuotes(r, qs, d.now);
        final won = c.lines.where((l) => l.quote.status == 'accepted').firstOrNull;
        final others = [
          for (final l in c.lines)
            if (l != won) l.landed,
        ];
        final dearest = others.isEmpty ? null : others.reduce((a, b) => a > b ? a : b);
        rows.add([
          _day(r.createdAt),
          d.site(r.projectId),
          r.materialName,
          qs.length,
          won == null ? '' : (d.supplierName[won.quote.supplierId] ?? ''),
          won?.landed,
          won == null || dearest == null ? null : _r2(dearest - won.landed),
        ]);
      }
      return ReportTable(
        ['Date', 'Site', 'Material', 'Quotes', 'Ordered from', 'Landed', 'Saved vs dearest'],
        rows,
        sumColumns: {5, 6},
      );
    },
  ),

  // --- Stores and tools ----------------------------------------------------
  ReportDef(
    'store-stock',
    ReportGroup.stores,
    'Store stock and value',
    'What each store holds and what it is worth at the average rate.',
    (d) {
      final rows = <List<Object?>>[];
      for (final s in d.stores.where((s) => !s.archived)) {
        for (final l in storeStock(d.moves, s.id)) {
          rows.add([s.name, l.name, l.unit ?? '', l.balance, l.avgRate == null ? null : _r2(l.avgRate!), _r2(l.value)]);
        }
      }
      return ReportTable(['Store', 'Material', 'Unit', 'Qty', 'Average rate', 'Worth'], rows, sumColumns: {5});
    },
    access: ReportAccess.managers,
    usesPeriod: false,
  ),
  ReportDef('transfers', ReportGroup.stores, 'Transfers', 'Material sent between stores and sites, and what arrived.', (d) {
    final xs = d.moves.where((m) => m.kind == 'transfer' && d.inPeriod(m.sentOn) && _touches(d, m)).toList()
      ..sort((a, b) => _byDate(a.sentOn, b.sentOn));
    return ReportTable(
      ['Sent', 'From', 'To', 'Material', 'Qty', 'Unit', 'Arrived', 'Status', 'Worth'],
      [
        for (final m in xs)
          [
            _day(m.sentOn),
            d.place(m.fromStoreId, m.fromProjectId),
            d.place(m.toStoreId, m.toProjectId),
            m.materialName,
            m.quantity,
            m.unit ?? '',
            m.status == 'received' ? arrivedQty(m) : null,
            _word(m.status),
            m.rate == null ? null : _r2(m.quantity * m.rate!),
          ],
      ],
      sumColumns: {8},
    );
  }),
  ReportDef('shortages', ReportGroup.stores, 'Arrived short', 'Transfers where less arrived than was sent.', (d) {
    final xs = d.moves.where((m) => m.kind == 'transfer' && d.inPeriod(m.sentOn) && shortage(m) > 0 && _touches(d, m)).toList()
      ..sort((a, b) => _byDate(a.sentOn, b.sentOn));
    return ReportTable(
      ['Sent', 'From', 'To', 'Material', 'Sent qty', 'Arrived', 'Short', 'Short worth'],
      [
        for (final m in xs)
          [
            _day(m.sentOn),
            d.place(m.fromStoreId, m.fromProjectId),
            d.place(m.toStoreId, m.toProjectId),
            m.materialName,
            m.quantity,
            arrivedQty(m),
            shortage(m),
            m.rate == null ? null : _r2(shortage(m) * m.rate!),
          ],
      ],
      sumColumns: {7},
    );
  }),
  ReportDef('tools', ReportGroup.stores, 'Tools register', 'Every tool, where it is and who has it.', (d) {
    final xs = [...d.tools]..sort((a, b) => (a.code ?? '').compareTo(b.code ?? ''));
    return ReportTable(
      ['Tag', 'Tool', 'Kind', 'Store', 'Worth', 'State', 'With', 'Site', 'Due back'],
      [
        for (final t in xs)
          () {
            final open = openIssueOf(t.id, d.toolIssues);
            return [
              t.code ?? '',
              t.name,
              t.category ?? '',
              d.storeName[t.storeId] ?? '',
              t.value,
              toolStateLabels[toolState(t, d.toolIssues, d.now)],
              open?.issuedTo ?? '',
              d.site(open?.projectId),
              open?.dueBack,
            ];
          }(),
      ],
      sumColumns: {4},
    );
  }, usesPeriod: false),
  ReportDef('tools-overdue', ReportGroup.stores, 'Tools overdue', 'Tools not back by their due date.', (d) {
    final rows = <List<Object?>>[];
    for (final t in d.tools.where((t) => toolState(t, d.toolIssues, d.now) == ToolState.overdue)) {
      final i = openIssueOf(t.id, d.toolIssues)!;
      rows.add([
        t.code ?? '',
        t.name,
        i.issuedTo,
        d.site(i.projectId),
        i.dueBack,
        _day(d.now).difference(_day(i.dueBack!)).inDays,
      ]);
    }
    rows.sort((a, b) => (b[5] as int).compareTo(a[5] as int));
    return ReportTable(['Tag', 'Tool', 'With', 'Site', 'Due back', 'Days late'], rows);
  }, usesPeriod: false),
  ReportDef('tools-recover', ReportGroup.stores, 'Tools to recover', 'What is owed for tools returned damaged or lost.', (d) {
    final tools = {for (final t in d.tools) t.id: t};
    final xs = toRecover(d.toolIssues).toList()..sort((a, b) => _byDate(a.returnedOn ?? a.issuedOn, b.returnedOn ?? b.issuedOn));
    return ReportTable(
      ['Returned', 'Tag', 'Tool', 'From', 'Site', 'Condition', 'To recover'],
      [
        for (final i in xs)
          [
            i.returnedOn,
            tools[i.toolId]?.code ?? '',
            tools[i.toolId]?.name ?? '',
            i.issuedTo,
            d.site(i.projectId),
            returnConditionLabels[i.returnCondition] ?? '',
            i.recoverAmount,
          ],
      ],
      sumColumns: {6},
    );
  }, usesPeriod: false),

  // --- Money ---------------------------------------------------------------
  ReportDef('expenses', ReportGroup.money, 'Expenses', 'Every payment made, with voucher number, mode and GST.', (d) {
    final xs = d.expenses.where((e) => d.inPeriodDay(e.incurredOn)).toList()
      ..sort((a, b) => a.incurredOn.compareTo(b.incurredOn));
    return ReportTable(
      ['Date', 'Site', 'Voucher', 'Head', 'Paid to', 'Mode', 'Amount', 'Status'],
      [
        for (final e in xs)
          [
            parseDay(e.incurredOn),
            d.site(e.projectId),
            e.voucherNo,
            e.category,
            e.paidTo ?? '',
            _word(e.mode),
            e.voided ? 0 : e.amount,
            e.voided ? 'Cancelled' : '',
          ],
      ],
      sumColumns: {6},
      note: 'Cancelled vouchers stay in the list at zero, so the numbers have no gaps.',
    );
  }),
  ReportDef(
    'expense-heads',
    ReportGroup.money,
    'Spending by head',
    'Total spent under each head (material, labour, transport...).',
    (d) {
      final xs = _sumBy(
        d.expenses.where((e) => !e.voided && d.inPeriodDay(e.incurredOn)),
        (e) => e.category.trim().isEmpty ? 'Other' : e.category.trim(),
        (e) => e.amount,
      );
      final all = xs.fold<double>(0, (s, e) => s + e.value);
      return ReportTable(
        ['Head', 'Amount', 'Share %'],
        [
          for (final e in xs) [e.key, e.value, all > 0 ? _r2(e.value * 100 / all) : 0],
        ],
        sumColumns: {1},
      );
    },
  ),
  ReportDef('expense-sites', ReportGroup.money, 'Spending by site', 'Total spent on each site.', (d) {
    final xs = _sumBy(
      d.expenses.where((e) => !e.voided && d.inPeriodDay(e.incurredOn)),
      (e) => d.site(e.projectId),
      (e) => e.amount,
    );
    return ReportTable(
      ['Site', 'Amount'],
      [
        for (final e in xs) [e.key, e.value],
      ],
      sumColumns: {1},
    );
  }),
  ReportDef('paid-to', ReportGroup.money, 'Paid to each party', 'Total paid to each person or firm.', (d) {
    final xs = _sumBy(
      d.expenses.where((e) => !e.voided && d.inPeriodDay(e.incurredOn)),
      (e) => (e.paidTo ?? '').trim().isEmpty ? 'Not named' : e.paidTo!.trim(),
      (e) => e.amount,
    );
    return ReportTable(
      ['Paid to', 'Amount'],
      [
        for (final e in xs) [e.key, e.value],
      ],
      sumColumns: {1},
    );
  }),
  ReportDef('mode', ReportGroup.money, 'Cash and bank', 'What went out in cash, by bank, UPI or cheque.', (d) {
    final xs = _sumBy(
      d.expenses.where((e) => !e.voided && d.inPeriodDay(e.incurredOn)),
      (e) => _word(e.mode ?? 'cash'),
      (e) => e.amount,
    );
    return ReportTable(
      ['Mode', 'Amount'],
      [
        for (final e in xs) [e.key, e.value],
      ],
      sumColumns: {1},
    );
  }),
  ReportDef('gst-input', ReportGroup.money, 'GST on purchases', 'GST inside each payment that carries it, for your accountant.', (
    d,
  ) {
    final xs = d.expenses.where((e) => !e.voided && (e.gstPct ?? 0) > 0 && d.inPeriodDay(e.incurredOn)).toList()
      ..sort((a, b) => a.incurredOn.compareTo(b.incurredOn));
    return ReportTable(
      ['Date', 'Site', 'Paid to', 'Amount', 'GST %', 'GST in it', 'Kind'],
      [
        for (final e in xs)
          [
            parseDay(e.incurredOn),
            d.site(e.projectId),
            e.paidTo ?? '',
            e.amount,
            e.gstPct,
            _r2(e.amount * e.gstPct! / (100 + e.gstPct!)),
            e.gstInterState ? 'IGST' : 'CGST + SGST',
          ],
      ],
      sumColumns: {3, 5},
    );
  }),
  ReportDef('received', ReportGroup.money, 'Money received', 'Payments received from clients.', (d) {
    final xs = d.payments.where((p) => !p.voided && d.inPeriod(p.receivedOn)).toList()
      ..sort((a, b) => _byDate(a.receivedOn, b.receivedOn));
    return ReportTable(
      ['Date', 'Site', 'From', 'Mode', 'Amount'],
      [
        for (final p in xs) [_day(p.receivedOn), d.site(p.projectId), p.fromParty, _word(p.mode), p.amount],
      ],
      sumColumns: {4},
    );
  }, access: ReportAccess.moneyIn),
  ReportDef(
    'client-bills',
    ReportGroup.money,
    'Client bills',
    'Running bills and tax invoices raised, and whether paid.',
    (d) {
      final xs = d.bills.where((b) => d.inPeriod(b.billDate)).toList()..sort((a, b) => _byDate(a.billDate, b.billDate));
      return ReportTable(
        ['Date', 'Site', 'Bill', 'Kind', 'Client', 'Gross', 'Net payable', 'Status'],
        [
          for (final b in xs)
            [
              _day(b.billDate),
              d.site(b.projectId),
              b.billNumber,
              b.kind == 'ra' ? 'Running bill' : 'Tax invoice',
              b.clientName,
              b.gross,
              b.netPayable,
              _word(b.status),
            ],
        ],
        sumColumns: {5, 6},
      );
    },
    access: ReportAccess.moneyIn,
  ),
  ReportDef(
    'site-margin',
    ReportGroup.money,
    'Site profit',
    'Billed, received and spent on each site, and what is left.',
    (d) {
      return ReportTable(
        ['Site', 'Billed', 'Received', 'Spent', 'Received less spent', 'Still to collect'],
        [
          for (final s in d.sites)
            () {
              final billed = d.bills
                  .where((b) => b.projectId == s.id && d.inPeriod(b.billDate))
                  .fold<double>(0, (t, b) => t + b.netPayable);
              final got = d.payments
                  .where((p) => p.projectId == s.id && !p.voided && d.inPeriod(p.receivedOn))
                  .fold<double>(0, (t, p) => t + p.amount);
              final spent = d.expenses
                  .where((e) => e.projectId == s.id && !e.voided && d.inPeriodDay(e.incurredOn))
                  .fold<double>(0, (t, e) => t + e.amount);
              return [s.name, billed, got, spent, _r2(got - spent), billed > got ? _r2(billed - got) : 0];
            }(),
        ],
        sumColumns: {1, 2, 3, 4, 5},
      );
    },
    access: ReportAccess.moneyIn,
  ),

  // --- Subcontractors ------------------------------------------------------
  ReportDef('work-orders', ReportGroup.subcontract, 'Work orders', 'Each work order: agreed, billed and still to bill.', (d) {
    final subs = {for (final s in d.subcontractors) s.id: s.name};
    final xs = [...d.workOrders]..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Site', 'Subcontractor', 'Work', 'Agreed', 'Billed', 'Left to bill'],
      [
        for (final w in xs)
          [
            d.site(w.projectId),
            subs[w.subcontractorId] ?? '',
            w.description,
            w.agreedAmount,
            w.billedAmount,
            w.agreedAmount == null ? null : _r2(w.agreedAmount! - w.billedAmount),
          ],
      ],
      sumColumns: {3, 4, 5},
    );
  }, usesPeriod: false),
  ReportDef(
    'by-subcontractor',
    ReportGroup.subcontract,
    'Subcontractor totals',
    'Agreed and billed for each subcontractor across sites.',
    (d) {
      final subs = {for (final s in d.subcontractors) s.id: s};
      final agreed = <String, double>{};
      final billed = <String, double>{};
      final count = <String, int>{};
      for (final w in d.workOrders) {
        agreed[w.subcontractorId] = (agreed[w.subcontractorId] ?? 0) + (w.agreedAmount ?? 0);
        billed[w.subcontractorId] = (billed[w.subcontractorId] ?? 0) + w.billedAmount;
        count[w.subcontractorId] = (count[w.subcontractorId] ?? 0) + 1;
      }
      final ids = count.keys.toList()..sort((a, b) => (agreed[b] ?? 0).compareTo(agreed[a] ?? 0));
      return ReportTable(
        ['Subcontractor', 'Trade', 'Work orders', 'Agreed', 'Billed'],
        [
          for (final id in ids) [subs[id]?.name ?? '', subs[id]?.trade ?? '', count[id], agreed[id], billed[id]],
        ],
        sumColumns: {2, 3, 4},
      );
    },
    usesPeriod: false,
  ),
  ReportDef('variations', ReportGroup.subcontract, 'Variations', 'Extra and changed work, its cost and the decision.', (d) {
    final xs = d.variations.where((v) => d.inPeriod(v.createdAt)).toList()..sort((a, b) => _byDate(a.createdAt, b.createdAt));
    return ReportTable(
      ['Raised', 'Site', 'Variation', 'From', 'Estimated cost', 'Extra days', 'Decision', 'Approved cost'],
      [
        for (final v in xs)
          () {
            final dec = d.variationDecisions.where((x) => x.variationId == v.id).lastOrNull;
            return [
              _day(v.createdAt),
              d.site(v.projectId),
              v.title,
              _word(v.origin),
              v.estimatedCost,
              v.scheduleDays,
              dec == null ? 'Waiting' : _word(dec.decision),
              dec?.approvedCost,
            ];
          }(),
      ],
      sumColumns: {4, 7},
    );
  }),

  // --- Equipment -----------------------------------------------------------
  ReportDef('equipment', ReportGroup.equipment, 'Equipment register', 'Machines on each site, owned or hired, and their rates.', (
    d,
  ) {
    final xs = [...d.equipment]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ReportTable(
      ['Site', 'Equipment', 'Type', 'Number', 'Owned or hired', 'Status', 'Day rate', 'Return due'],
      [
        for (final e in xs)
          [
            d.site(e.projectId),
            e.name,
            e.equipmentType ?? '',
            e.registrationNumber ?? '',
            _word(e.ownership),
            _word(e.status),
            e.dailyRate,
            e.returnedOn == null ? e.returnDueOn : null,
          ],
      ],
    );
  }, usesPeriod: false),
  ReportDef('equipment-use', ReportGroup.equipment, 'Equipment hours and cost', 'Hours run and money spent on each machine.', (
    d,
  ) {
    final eq = {for (final e in d.equipment) e.id: e};
    final hours = <String, double>{};
    final cost = <String, double>{};
    for (final l in d.equipmentLogs.where((l) => d.inPeriod(l.logDate) && eq.containsKey(l.equipmentId))) {
      hours[l.equipmentId] = (hours[l.equipmentId] ?? 0) + (l.hoursUsed ?? 0);
      cost[l.equipmentId] = (cost[l.equipmentId] ?? 0) + (l.cost ?? 0);
    }
    final ids = {...hours.keys, ...cost.keys}.toList()..sort((a, b) => (cost[b] ?? 0).compareTo(cost[a] ?? 0));
    return ReportTable(
      ['Equipment', 'Site', 'Hours', 'Cost', 'Cost an hour'],
      [
        for (final id in ids)
          [
            eq[id]!.name,
            d.site(eq[id]!.projectId),
            hours[id] ?? 0,
            cost[id] ?? 0,
            (hours[id] ?? 0) > 0 ? _r2((cost[id] ?? 0) / hours[id]!) : null,
          ],
      ],
      sumColumns: {2, 3},
    );
  }),
  ReportDef(
    'hire-due',
    ReportGroup.equipment,
    'Hired equipment due back',
    'Hired machines still on site, by return date, so rent does not run on.',
    (d) {
      final xs = d.equipment.where((e) => e.ownership == 'hired' && e.returnedOn == null).toList()
        ..sort((a, b) => (a.returnDueOn ?? DateTime(9999)).compareTo(b.returnDueOn ?? DateTime(9999)));
      return ReportTable(
        ['Equipment', 'Site', 'Hired from', 'Hired on', 'Return due', 'Day rate', 'Days so far'],
        [
          for (final e in xs)
            [
              e.name,
              d.site(e.projectId),
              e.hiredFrom ?? '',
              e.hiredOn,
              e.returnDueOn,
              e.dailyRate,
              e.hiredOn == null ? null : _day(d.now).difference(_day(e.hiredOn!)).inDays,
            ],
        ],
      );
    },
    usesPeriod: false,
  ),

  // --- Staff salaries --------------------------------------------------------
  ReportDef(
    'salary-register',
    ReportGroup.staff,
    'Salary register',
    'Each payslip in the period: earned, deductions and net.',
    (d) {
      final staff = {for (final s in d.staff) s.id: s};
      final months = _monthsIn(d);
      final xs = d.payroll.where((l) => months.contains(l.month)).toList()
        ..sort(
          (a, b) => a.month == b.month
              ? (staff[a.staffId]?.name ?? '').compareTo(staff[b.staffId]?.name ?? '')
              : a.month.compareTo(b.month),
        );
      return ReportTable(
        ['Month', 'Name', 'Days paid', 'Gross', 'PF', 'ESI', 'PT', 'Advance', 'Other', 'Net', 'Status'],
        [
          for (final l in xs)
            [
              l.month,
              staff[l.staffId]?.name ?? '',
              l.paidDays,
              l.gross,
              l.pfEmployee,
              l.esiEmployee,
              l.pt,
              l.advanceRecovery,
              l.otherDeduction,
              l.net,
              _word(l.status),
            ],
        ],
        sumColumns: {3, 4, 5, 6, 7, 8, 9},
      );
    },
    access: ReportAccess.managers,
  ),
  ReportDef(
    'pf-esi',
    ReportGroup.staff,
    'PF and ESI to deposit',
    'Both shares of PF and ESI, and professional tax, month by month.',
    (d) {
      final inPeriod = _monthsIn(d);
      final months = {
        for (final l in d.payroll)
          if (inPeriod.contains(l.month)) l.month,
      }.toList()..sort();
      return ReportTable(
        ['Month', 'PF staff', 'PF company', 'ESI staff', 'ESI company', 'Professional tax', 'To deposit'],
        [
          for (final m in months)
            () {
              final ls = d.payroll.where((l) => l.month == m);
              double s(double Function(PayrollLine) f) => _r2(ls.fold<double>(0, (t, l) => t + f(l)));
              final pf = s((l) => l.pfEmployee),
                  pfc = s((l) => l.pfEmployer),
                  esi = s((l) => l.esiEmployee),
                  esic = s((l) => l.esiEmployer),
                  pt = s((l) => l.pt);
              return [m, pf, pfc, esi, esic, pt, _r2(pf + pfc + esi + esic + pt)];
            }(),
        ],
        sumColumns: {1, 2, 3, 4, 5, 6},
      );
    },
    access: ReportAccess.managers,
  ),
  ReportDef(
    'advances',
    ReportGroup.staff,
    'Advances still owed',
    'Salary advances not yet recovered, by person.',
    (d) {
      final rows = <List<Object?>>[];
      for (final s in d.staff) {
        final given = d.advances.where((a) => a.staffId == s.id).fold<double>(0, (t, a) => t + a.amount);
        if (given <= 0) continue;
        final owed = advanceOwed(s.id, d.advances, d.payroll);
        if (owed <= 0) continue;
        rows.add([s.name, s.designation ?? '', given, _r2(given - owed), owed]);
      }
      rows.sort((a, b) => (b[4] as double).compareTo(a[4] as double));
      return ReportTable(['Name', 'Role', 'Given', 'Recovered', 'Still owed'], rows, sumColumns: {2, 3, 4});
    },
    access: ReportAccess.managers,
    usesPeriod: false,
  ),
  ReportDef(
    'staff-cost-sites',
    ReportGroup.staff,
    'Staff cost by site',
    'Salary cost to the company for each site it is charged to.',
    (d) {
      final months = _monthsIn(d);
      final xs = _sumBy(
        d.payroll.where((l) => months.contains(l.month)),
        (l) => l.projectId == null ? 'Head office' : (d.siteName[l.projectId] ?? 'Other site'),
        (l) => l.gross + l.pfEmployer + l.esiEmployer,
      );
      return ReportTable(
        ['Charged to', 'Cost to company'],
        [
          for (final e in xs) [e.key, _r2(e.value)],
        ],
        sumColumns: {1},
      );
    },
    access: ReportAccess.managers,
  ),

  // --- Sales ---------------------------------------------------------------
  ReportDef(
    'pipeline',
    ReportGroup.sales,
    'Sales pipeline',
    'Open enquiries by stage, with their value.',
    (d) {
      const order = ['new', 'contacted', 'site_visit', 'quoted', 'negotiation'];
      return ReportTable(
        ['Stage', 'Enquiries', 'Value'],
        [
          for (final st in order)
            if (d.leads.any((l) => l.stage == st))
              () {
                final ls = d.leads.where((l) => l.stage == st);
                return [
                  _word(st),
                  ls.length,
                  _r2(
                    ls.fold<double>(
                      0,
                      (t, l) =>
                          t +
                          leadValue(l, [
                            for (final q in d.crmQuotes)
                              if (q.leadId == l.id) q,
                          ]),
                    ),
                  ),
                ];
              }(),
        ],
        sumColumns: {1, 2},
      );
    },
    access: ReportAccess.managers,
    usesPeriod: false,
  ),
  ReportDef(
    'follow-ups',
    ReportGroup.sales,
    'Follow-ups due',
    'Open enquiries to call today or already late.',
    (d) {
      final xs = d.leads.where((l) => isOpenStage(l.stage) && isFollowUpDue(l, d.now)).toList()
        ..sort((a, b) => _byDate(a.nextFollowUp!, b.nextFollowUp!));
      return ReportTable(
        ['Follow up', 'Name', 'Phone', 'Stage', 'Work', 'Who'],
        [
          for (final l in xs) [l.nextFollowUp, l.name, l.phone ?? '', _word(l.stage), l.workType ?? '', d.user(l.ownerId)],
        ],
      );
    },
    access: ReportAccess.managers,
    usesPeriod: false,
  ),
  ReportDef(
    'won-lost',
    ReportGroup.sales,
    'Won and lost',
    'Enquiries closed in the period, with the reason for each loss.',
    (d) {
      final xs = d.leads.where((l) => (l.stage == 'won' || l.stage == 'lost') && d.inPeriod(l.updatedAt)).toList()
        ..sort((a, b) => _byDate(a.updatedAt, b.updatedAt));
      return ReportTable(
        ['Closed', 'Name', 'Source', 'Result', 'Value', 'Reason'],
        [
          for (final l in xs)
            [
              _day(l.updatedAt),
              l.name,
              _word(l.source),
              _word(l.stage),
              leadValue(l, [
                for (final q in d.crmQuotes)
                  if (q.leadId == l.id) q,
              ]),
              l.lostReason ?? '',
            ],
        ],
        sumColumns: {4},
      );
    },
    access: ReportAccess.managers,
  ),
  ReportDef(
    'lead-sources',
    ReportGroup.sales,
    'Where enquiries come from',
    'Enquiries and wins from each source, to see what is working.',
    (d) {
      final xs = d.leads.where((l) => d.inPeriod(l.createdAt));
      final sources = {for (final l in xs) l.source}.toList()..sort();
      return ReportTable(
        ['Source', 'Enquiries', 'Won', 'Win rate %'],
        [
          for (final s in sources)
            () {
              final all = xs.where((l) => l.source == s).length;
              final won = xs.where((l) => l.source == s && l.stage == 'won').length;
              return [_word(s), all, won, all > 0 ? _r2(won * 100 / all) : 0];
            }(),
        ],
        sumColumns: {1, 2},
      );
    },
    access: ReportAccess.managers,
  ),
  ReportDef('crm-quotes', ReportGroup.sales, 'Quotations sent', 'Quotations made for enquiries, and their status.', (d) {
    final leads = {for (final l in d.leads) l.id: l.name};
    final xs = d.crmQuotes.where((q) => d.inPeriod(q.quoteDate)).toList()..sort((a, b) => _byDate(a.quoteDate, b.quoteDate));
    return ReportTable(
      ['Date', 'Quote', 'For', 'Total', 'Status'],
      [
        for (final q in xs) [_day(q.quoteDate), q.quoteNumber, leads[q.leadId] ?? '', q.total, _word(q.status)],
      ],
      sumColumns: {3},
    );
  }, access: ReportAccess.managers),
];

/// Company-wide moves shown when they touch one of the chosen sites, or
/// always when all the company's sites are chosen (store to store).
bool _touches(ReportInput d, StockMove m) =>
    d.siteIds.contains(m.fromProjectId) ||
    d.siteIds.contains(m.toProjectId) ||
    (m.fromProjectId == null && m.toProjectId == null);

Set<String> _monthsIn(ReportInput d) {
  final out = <String>{};
  var m = DateTime(d.from.year, d.from.month);
  while (m.isBefore(d.to)) {
    out.add(monthKey(m));
    m = DateTime(m.year, m.month + 1);
  }
  return out;
}

bool canOpenReport(ReportDef r, {required bool moneyIn, required bool manager}) => switch (r.access) {
  ReportAccess.everyone => true,
  ReportAccess.moneyIn => moneyIn,
  ReportAccess.managers => manager,
};

ReportDef? reportById(String id) => reportLibrary.where((r) => r.id == id).firstOrNull;

// ---------------------------------------------------------------------------
// Loading.
// ---------------------------------------------------------------------------

/// Reads what the reports need for [sites] (already limited to what the
/// person may see) and the company's stores, tools, staff and sales.
/// [manager]: owner or project manager (salaries, sales, stores).
/// [moneyIn]: may see money received.
Future<ReportInput> loadReportInput(
  AppDatabase db, {
  required String companyId,
  required List<Project> sites,
  required DateTime from,
  required DateTime to,
  required bool manager,
  required bool moneyIn,
  DateTime? now,
}) async {
  final ids = [for (final s in sites) s.id];
  Future<List<T>> of<T extends DataClass, TT extends Table>(TableInfo<TT, T> table, GeneratedColumn<String> Function(TT) col) =>
      ids.isEmpty ? Future.value(<T>[]) : (db.select(table)..where((t) => col(t).isIn(ids))).get();
  Future<List<T>> co<T extends DataClass, TT extends Table>(TableInfo<TT, T> table, GeneratedColumn<String> Function(TT) col) =>
      (db.select(table)..where((t) => col(t).equals(companyId))).get();

  final equipment = await of(db.equipment, (t) => t.projectId);
  final eqIds = [for (final e in equipment) e.id];
  return ReportInput(
    sites: sites,
    from: from,
    to: to,
    now: now ?? DateTime.now(),
    users: {for (final u in await db.select(db.users).get()) u.id: u.name},
    tasks: await of(db.tasks, (t) => t.projectId),
    dprs: await of(db.dprEntries, (t) => t.projectId),
    issues: await of(db.issues, (t) => t.projectId),
    inspections: await of(db.inspections, (t) => t.projectId),
    documents: await of(db.documents, (t) => t.projectId),
    attendance: await of(db.labourAttendance, (t) => t.projectId),
    marks: await of(db.attendanceMarks, (t) => t.projectId),
    workers: await of(db.workers, (t) => t.projectId),
    receipts: await of(db.materialReceipts, (t) => t.projectId),
    usage: await of(db.materialUsage, (t) => t.projectId),
    requests: await of(db.purchaseRequests, (t) => t.projectId),
    orders: await of(db.purchaseOrders, (t) => t.projectId),
    suppliers: await co(db.suppliers, (t) => t.companyId),
    supplierInvoices: await of(db.supplierInvoices, (t) => t.projectId),
    supplierQuotes: await of(db.supplierQuotes, (t) => t.projectId),
    expenses: await of(db.siteExpenses, (t) => t.projectId),
    payments: moneyIn ? await of(db.paymentsReceived, (t) => t.projectId) : const [],
    bills: moneyIn ? await of(db.clientBills, (t) => t.projectId) : const [],
    subcontractors: await co(db.subcontractors, (t) => t.companyId),
    workOrders: await of(db.workOrders, (t) => t.projectId),
    variations: await of(db.variations, (t) => t.projectId),
    variationDecisions: await of(db.variationDecisions, (t) => t.projectId),
    equipment: equipment,
    equipmentLogs: eqIds.isEmpty ? const [] : await (db.select(db.equipmentLogs)..where((t) => t.equipmentId.isIn(eqIds))).get(),
    approvals: ids.isEmpty ? const [] : await (db.select(db.approvals)..where((t) => t.projectId.isIn(ids))).get(),
    stores: await co(db.stores, (t) => t.companyId),
    moves: await co(db.stockMoves, (t) => t.companyId),
    tools: await co(db.tools, (t) => t.companyId),
    toolIssues: await co(db.toolIssues, (t) => t.companyId),
    staff: manager ? await co(db.staffMembers, (t) => t.companyId) : const [],
    advances: manager ? await co(db.staffAdvances, (t) => t.companyId) : const [],
    payroll: manager ? await co(db.payrollLines, (t) => t.companyId) : const [],
    leads: manager ? await co(db.crmLeads, (t) => t.companyId) : const [],
    crmQuotes: manager ? await co(db.crmQuotes, (t) => t.companyId) : const [],
  );
}
