/// Everything FieldOS holds for one site or a whole company, as one Excel
/// file the customer keeps. It reads only the database on this phone, so
/// it works offline, and it is never behind the paywall: whatever happens
/// to a subscription, people can take their records with them.
///
/// The file is in English whatever the app language, like the bill PDF:
/// it goes to accountants, Tally and Excel formulas.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/xlsx_writer.dart';
import 'package:fieldos_mobile/features/money/money_book.dart' show gstSplit, voucherLabel;
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';

/// What to put in the file.
class ExportScope {
  const ExportScope.project(this.projectId) : companyId = null;
  const ExportScope.company(this.companyId) : projectId = null;

  final String? projectId;
  final String? companyId;
}

/// The sheets of the export, in the order they appear in Excel.
///
/// [showMoneyIn] is false for roles that may not see what the client pays
/// (see canSeeMoneyIn): the file then leaves out money received, client
/// bills and the balance, as the app's own screens do.
Future<List<XlsxSheet>> buildExportSheets(AppDatabase db, ExportScope scope, {bool showMoneyIn = true}) async {
  final List<Project> projects;
  String? companyId = scope.companyId;
  if (scope.projectId != null) {
    final one = await (db.select(db.projects)..where((t) => t.id.equals(scope.projectId!))).getSingleOrNull();
    projects = one == null ? const [] : [one];
    companyId = one?.companyId;
  } else {
    final sample = await sampleProjectId(db, scope.companyId!);
    projects = (await db.projectDao.forCompany(scope.companyId!)).where((x) => x.id != sample).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  final ids = projects.map((x) => x.id).toList();
  final site = {for (final x in projects) x.id: x.name};
  final many = projects.length > 1;

  Future<List<T>> rowsOf<T extends DataClass, TT extends Table>(
    TableInfo<TT, T> table,
    Expression<bool> Function(TT t) inProjects,
  ) async {
    if (ids.isEmpty) return <T>[];
    return (db.select(table)..where(inProjects)).get();
  }

  final users = await db.select(db.users).get();
  final userName = {for (final u in users) u.id: u.name};
  String who(String? id) => id == null ? '' : (userName[id] ?? '');

  final tasks = await rowsOf(db.tasks, (t) => t.projectId.isIn(ids));
  final dprs = await rowsOf(db.dprEntries, (t) => t.projectId.isIn(ids));
  final issues = await rowsOf(db.issues, (t) => t.projectId.isIn(ids));
  final expenses = await rowsOf(db.siteExpenses, (t) => t.projectId.isIn(ids));
  final received = await rowsOf(db.paymentsReceived, (t) => t.projectId.isIn(ids));
  final bills = await rowsOf(db.clientBills, (t) => t.projectId.isIn(ids));
  final attendance = await rowsOf(db.labourAttendance, (t) => t.projectId.isIn(ids));
  final workers = await rowsOf(db.workers, (t) => t.projectId.isIn(ids));
  final marks = (await rowsOf(db.attendanceMarks, (t) => t.projectId.isIn(ids))).where((m) => m.units != null).toList();
  final receipts = await rowsOf(db.materialReceipts, (t) => t.projectId.isIn(ids));
  final usage = await rowsOf(db.materialUsage, (t) => t.projectId.isIn(ids));
  final requests = await rowsOf(db.purchaseRequests, (t) => t.projectId.isIn(ids));
  final orders = await rowsOf(db.purchaseOrders, (t) => t.projectId.isIn(ids));
  final workOrders = await rowsOf(db.workOrders, (t) => t.projectId.isIn(ids));
  final equipment = await rowsOf(db.equipment, (t) => t.projectId.isIn(ids));
  final equipmentIds = equipment.map((e) => e.id).toList();
  final equipmentLogs = equipmentIds.isEmpty
      ? const <EquipmentLog>[]
      : await (db.select(db.equipmentLogs)..where((t) => t.equipmentId.isIn(equipmentIds))).get();
  final inspections = await rowsOf(db.inspections, (t) => t.projectId.isIn(ids));
  final documents = await rowsOf(db.documents, (t) => t.projectId.isIn(ids));
  final notes = (await rowsOf(db.projectNotes, (t) => t.projectId.isIn(ids))).where((n) => !n.deleted).toList();
  final suppliers = companyId == null ? const <Supplier>[] : await db.supplierDao.forCompany(companyId);
  final subcontractors = companyId == null ? const <Subcontractor>[] : await db.subcontractorDao.forCompany(companyId);

  final workerName = {for (final w in workers) w.id: w.name};
  final supplierName = {for (final s in suppliers) s.id: s.name};
  final subName = {for (final s in subcontractors) s.id: s.name};
  final equipmentName = {for (final e in equipment) e.id: e.name};
  final equipmentSite = {for (final e in equipment) e.id: e.projectId};

  // Newest first, like the app's own lists.
  int newest(DateTime a, DateTime b) => b.compareTo(a);
  DateTime day(String iso, DateTime fallback) => DateTime.tryParse(iso) ?? fallback;

  /// Site column first when the file covers more than one site.
  List<String> h(List<String> headers) => [if (many) 'Site', ...headers];
  List<Object?> r(String projectId, List<Object?> cells) => [if (many) site[projectId] ?? '', ...cells];

  double sum<T>(Iterable<T> xs, double Function(T) f) => xs.fold(0.0, (s, x) => s + f(x));

  final sheets = <XlsxSheet>[
    XlsxSheet(
      'Summary',
      [
        'Site',
        'Client',
        'Status',
        'Start',
        'End',
        if (showMoneyIn) 'Received (₹)',
        'Spent (₹)',
        'Material bought (₹)',
        if (showMoneyIn) ...['Balance (₹)', 'Billed to client (₹)'],
        'Workers',
        'Daily reports',
        'Open issues',
        'Open tasks',
      ].toList(),
      [
        for (final x in projects)
          () {
            final inAmt = sum(received.where((e) => e.projectId == x.id && !e.voided), (e) => e.amount);
            final spent = sum(expenses.where((e) => e.projectId == x.id && !e.voided), (e) => e.amount);
            final material = sum(receipts.where((e) => e.projectId == x.id), (e) => e.amount);
            return <Object?>[
              x.name,
              x.clientName,
              _word(x.status),
              x.startDate,
              x.endDate,
              if (showMoneyIn) inAmt,
              spent,
              material,
              if (showMoneyIn) ...[inAmt - spent, sum(bills.where((e) => e.projectId == x.id), (e) => e.netPayable)],
              workers.where((w) => w.projectId == x.id).length,
              dprs.where((d) => d.projectId == x.id).length,
              issues.where((i) => i.projectId == x.id && i.status != 'resolved' && i.status != 'closed').length,
              tasks.where((t) => t.projectId == x.id && t.status != 'done').length,
            ];
          }(),
      ],
    ),
    XlsxSheet(
        'Money spent',
        h([
          'Date',
          'Voucher no.',
          'Category',
          'Worker',
          'Paid to',
          'Mode',
          'Amount (₹)',
          'Before GST (₹)',
          'GST %',
          'CGST (₹)',
          'SGST (₹)',
          'IGST (₹)',
          'Note',
          'Status',
          'Entered by',
        ]),
        [
          for (final e in expenses..sort((a, b) => newest(day(a.incurredOn, a.createdAt), day(b.incurredOn, b.createdAt))))
            () {
              final gst = (e.gstPct ?? 0) > 0 ? gstSplit(e.amount, e.gstPct!, interState: e.gstInterState) : null;
              return r(e.projectId, [
                day(e.incurredOn, e.createdAt),
                e.voucherNo == null ? null : voucherLabel(e.voucherNo),
                e.category,
                e.workerId == null ? null : workerName[e.workerId],
                e.paidTo,
                _modes[e.mode] ?? _word(e.mode),
                e.amount,
                gst?.taxable,
                gst == null ? null : e.gstPct,
                gst?.cgst,
                gst?.sgst,
                gst?.igst,
                e.note,
                _status(e.voided, e.voidReason),
                who(e.recordedBy),
              ]);
            }(),
        ]),
    if (showMoneyIn)
      XlsxSheet('Money received', h(['Date', 'From', 'Mode', 'Amount (₹)', 'Note', 'Status', 'Entered by']), [
        for (final e in received..sort((a, b) => newest(a.receivedOn, b.receivedOn)))
          r(e.projectId, [
            e.receivedOn,
            e.fromParty,
            _modes[e.mode] ?? _word(e.mode),
            e.amount,
            e.note,
            _status(e.voided, e.voidReason),
            who(e.recordedBy),
          ]),
      ]),
    if (showMoneyIn)
      XlsxSheet(
        'Client bills',
        h(['Bill no.', 'Date', 'Type', 'Client', 'Client GSTIN', 'Gross (₹)', 'GST %', 'Net payable (₹)', 'Status']),
        [
          for (final b in bills..sort((a, b) => newest(a.billDate, b.billDate)))
            r(b.projectId, [
              b.billNumber,
              b.billDate,
              b.kind == 'tax_invoice' ? 'Tax invoice' : 'RA bill',
              b.clientName,
              b.clientGstin,
              b.gross,
              b.gstRate,
              b.netPayable,
              _word(b.status),
            ]),
        ],
      ),
    XlsxSheet('Attendance', h(['Worker', 'In', 'Out', 'Hours', 'Inside site area']), [
      for (final a in attendance..sort((a, b) => newest(a.punchIn, b.punchIn)))
        r(a.projectId, [
          a.workerId != null ? (workerName[a.workerId] ?? a.workerName) : a.workerName,
          a.punchIn,
          a.punchOut,
          a.punchOut == null ? null : (a.punchOut!.difference(a.punchIn).inMinutes / 60.0),
          a.withinGeofence == null ? null : (a.withinGeofence! ? 'Yes' : 'No'),
        ]),
    ]),
    if (marks.isNotEmpty)
      XlsxSheet('Day register', h(['Date', 'Worker', 'Skill', 'Days of pay', 'Marked by']), [
        for (final m in marks..sort((a, b) => b.day.compareTo(a.day)))
          r(m.projectId, [
            DateTime.tryParse(m.day),
            workerName[m.workerId] ?? 'Worker',
            workers.where((w) => w.id == m.workerId).firstOrNull?.role,
            m.units,
            who(m.recordedBy),
          ]),
      ]),
    XlsxSheet('Workers', h(['Name', 'Skill', 'Phone', 'Daily wage (₹)', 'Status', 'Added on']), [
      for (final w in workers..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
        r(w.projectId, [w.name, w.role, w.phone, w.dailyWage, _word(w.status), w.createdAt]),
    ]),
    XlsxSheet('Daily reports', h(['Date', 'Work done', 'Workers on site', 'Weather', 'Status', 'Entered by']), [
      for (final d in dprs..sort((a, b) => newest(a.entryDate, b.entryDate)))
        r(d.projectId, [d.entryDate, d.workSummary, d.manpowerCount, d.weather, _word(d.status), who(d.createdBy)]),
    ]),
    XlsxSheet('Tasks', h(['Task', 'Status', 'Progress %', 'Priority', 'Start', 'Due', 'Created']), [
      for (final t in tasks..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(t.projectId, [t.title, _word(t.status), t.progress, _word(t.priority), t.startDate, t.dueDate, t.createdAt]),
    ]),
    XlsxSheet('Issues', h(['Raised', 'Issue', 'Severity', 'Status', 'Resolved']), [
      for (final i in issues..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(i.projectId, [i.createdAt, i.description, _word(i.severity), _word(i.status), i.resolvedAt]),
    ]),
    XlsxSheet('Material received', h(['Date', 'Material', 'Quantity', 'Unit', 'Amount (₹)', 'Supplier', 'Note']), [
      for (final m in receipts..sort((a, b) => newest(a.receivedOn, b.receivedOn)))
        r(m.projectId, [
          m.receivedOn,
          m.materialName,
          m.quantity,
          m.unit,
          m.amount,
          m.supplierId == null ? null : supplierName[m.supplierId],
          _plainNote(m.notes),
        ]),
    ]),
    XlsxSheet('Material used', h(['Date', 'Material', 'Quantity', 'Unit', 'Note']), [
      for (final m in usage..sort((a, b) => newest(a.usedOn, b.usedOn)))
        r(m.projectId, [m.usedOn, m.materialName, m.quantity, m.unit, m.note]),
    ]),
    XlsxSheet(
      'Purchase requests',
      h(['Raised', 'Material', 'Quantity', 'Unit', 'Estimated (₹)', 'Urgency', 'Status', 'Note']),
      [
        for (final q in requests..sort((a, b) => newest(a.createdAt, b.createdAt)))
          r(q.projectId, [
            q.createdAt,
            q.materialName,
            q.quantity,
            q.unit,
            q.estimatedAmount,
            _word(q.urgency),
            _word(q.status),
            q.notes,
          ]),
      ],
    ),
    XlsxSheet('Purchase orders', h(['PO no.', 'Raised', 'Supplier', 'Total (₹)', 'Delivery by', 'Status', 'Note']), [
      for (final o in orders..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(o.projectId, [
          o.poNumber,
          o.createdAt,
          supplierName[o.supplierId],
          o.totalAmount,
          o.deliveryDate,
          _word(o.status),
          o.notes,
        ]),
    ]),
    XlsxSheet('Work orders', h(['Work', 'Subcontractor', 'Agreed (₹)', 'Billed (₹)', 'Status', 'Created']), [
      for (final w in workOrders..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(w.projectId, [
          w.description,
          subName[w.subcontractorId],
          w.agreedAmount,
          w.billedAmount,
          _word(w.status),
          w.createdAt,
        ]),
    ]),
    XlsxSheet(
        'Equipment',
        h([
          'Name',
          'Type',
          'Model',
          'Registration',
          'Status',
          'Daily rate (₹)',
          'Rate per hour (₹)',
          'Own or hired',
          'Hired from',
          'On site since',
          'Goes back on',
          'Returned on',
          'Note',
        ]),
        [
          for (final e in equipment)
            r(e.projectId, [
              e.name,
              e.equipmentType,
              e.model,
              e.registrationNumber,
              _word(e.status),
              e.dailyRate,
              e.hourlyRate,
              e.ownership == 'hired' ? 'Hired' : 'Own',
              e.hiredFrom,
              e.hiredOn,
              e.returnDueOn,
              e.returnedOn,
              e.notes,
            ]),
        ]),
    XlsxSheet('Equipment logs', h(['Date', 'Equipment', 'Type', 'Hours', 'Cost (₹)', 'Note']), [
      for (final l in equipmentLogs.toList()..sort((a, b) => newest(a.logDate, b.logDate)))
        r(equipmentSite[l.equipmentId] ?? '', [
          l.logDate,
          equipmentName[l.equipmentId],
          _word(l.logType),
          l.hoursUsed,
          l.cost,
          l.description,
        ]),
    ]),
    XlsxSheet('Inspections', h(['Inspection', 'Type', 'Status', 'Scheduled', 'Completed', 'Result', 'Note']), [
      for (final i in inspections..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(i.projectId, [
          i.title,
          _word(i.inspectionType),
          _word(i.status),
          i.scheduledDate,
          i.completedDate,
          _word(i.overallResult),
          i.notes,
        ]),
    ]),
    XlsxSheet('Documents', h(['Name', 'Category', 'Version', 'Size (KB)', 'Added', 'Note']), [
      for (final d in documents..sort((a, b) => newest(a.createdAt, b.createdAt)))
        r(d.projectId, [
          d.name,
          _word(d.category),
          d.version,
          d.fileSize == null ? null : (d.fileSize! / 1024).round(),
          d.createdAt,
          d.notes,
        ]),
    ]),
    if (notes.isNotEmpty)
      XlsxSheet('Site notes', h(['Note', 'Pinned', 'Written by', 'Written', 'Last changed']), [
        for (final n in notes..sort((a, b) => newest(a.updatedAt, b.updatedAt)))
          r(n.projectId, [n.body, n.pinned ? 'Yes' : 'No', who(n.createdBy), n.createdAt, n.updatedAt]),
      ]),
    XlsxSheet(
        'Suppliers',
        ['Name', 'Contact person', 'Phone', 'Email', 'GSTIN', 'Category', 'Address', if (showMoneyIn) 'Opening balance (₹)']
            .toList(),
        [
          for (final s in suppliers)
            [
              s.name,
              s.contactPerson,
              s.contactPhone,
              s.email,
              s.gstNumber,
              s.category,
              s.address,
              if (showMoneyIn) s.openingBalance,
            ],
        ]),
    XlsxSheet('Subcontractors', ['Name', 'Trade', 'Phone'].toList(), [
      for (final s in subcontractors) [s.name, s.trade, s.contactPhone],
    ]),
  ];
  return sheets;
}

const _modes = {'cash': 'Cash', 'upi': 'UPI', 'bank': 'Bank transfer', 'cheque': 'Cheque'};

/// "in_progress" → "In progress", so stored codes read as words in Excel.
String? _word(String? code) {
  if (code == null || code.isEmpty) return code;
  final s = code.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// Receipt notes can carry photo paths on this phone (see photo_capture);
/// those mean nothing in Excel, so only the words are kept.
String? _plainNote(String? note) {
  if (note == null) return null;
  final words = note
      .split('\n')
      .where((l) => !l.trim().startsWith('/') && !l.trim().toLowerCase().startsWith('photo:') && !l.contains('/data/'))
      .join(' ')
      .trim();
  return words.isEmpty ? null : words;
}

/// "FieldOS Sunrise Villa 08-11-2026.xlsx", safe on every phone and PC.
String exportFileName(String label, DateTime now) {
  final clean = label.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final d = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  return 'FieldOS ${clean.isEmpty ? 'export' : clean} $d.xlsx';
}

/// Builds the file in the app's temporary folder and returns it, ready to
/// share or save.
Future<File> writeExportFile(
  AppDatabase db,
  ExportScope scope, {
  required String label,
  bool showMoneyIn = true,
  DateTime? now,
}) async {
  final sheets = await buildExportSheets(db, scope, showMoneyIn: showMoneyIn);
  final bytes = buildXlsx(sheets);
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, exportFileName(label, now ?? DateTime.now())));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// "Cancelled: entered twice" for a cancelled entry, else nothing. The
/// row stays in the file so the voucher numbers have no gaps, and the
/// Summary leaves it out of every total.
String? _status(bool voided, String? reason) {
  if (!voided) return null;
  final why = reason?.trim() ?? '';
  return why.isEmpty ? 'Cancelled' : 'Cancelled: $why';
}
