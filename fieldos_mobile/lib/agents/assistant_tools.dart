/// The actions the AI assistant can take, run here on the phone against the
/// site data (FieldOS keeps its data on the phone, offline-first; the server
/// only decides which action to take). The list of actions and what each
/// takes is defined once, on the server (supabase/functions/ai-assistant/
/// tools.ts); this file is the other half and must use the same names.
///
/// Reading actions run straight away. Changing actions ([writeTools]) are
/// shown to the person on a confirm card first, and run only after a tap.
/// Every write goes through the same DAO calls the screens use, so it is
/// queued for team sync exactly as if it had been typed in by hand.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// 2026-11-09, the way site_expenses stores its day.
String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const writeTools = {
  'create_project',
  'add_expense',
  'record_payment_received',
  'add_task',
  'update_task',
  'add_worker',
  'mark_attendance',
  'report_issue',
  'add_daily_report',
  'record_material_received',
  'record_material_used',
};

const expenseCategories = ['Material', 'Labour', 'Transport', 'Equipment hire', 'Food & tea', 'Fuel', 'Other'];
const _paymentModes = {'cash', 'upi', 'bank', 'cheque'};

/// A wrong or missing value from the model; goes back to it as an error
/// result so it can ask the person or try again.
class ToolInputError implements Exception {
  ToolInputError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A button the assistant offered: which screen, and for which project.
class ScreenLink {
  const ScreenLink(this.screen, {this.projectId});
  final String screen;
  final String? projectId;
}

/// What a tool did: the JSON text for the model, and anything the app
/// should show or refresh.
class ToolOutcome {
  const ToolOutcome(this.result, {this.isError = false, this.link, this.changedProjectId, this.changedProjects = false});
  final String result;
  final bool isError;
  final ScreenLink? link;
  final String? changedProjectId;
  final bool changedProjects;
}

class AssistantTools {
  AssistantTools({required this.db, required this.companyId, required this.userId, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final String companyId;

  /// The local user id, as the screens record it (recordedBy, createdBy).
  final String userId;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  DateTime get _now => _clock();

  /// Runs one tool. A bad input or a failure becomes an error result the
  /// model can read, never an exception out of here.
  Future<ToolOutcome> run(String name, Map<String, dynamic> input) async {
    try {
      return await _run(name, input);
    } on ToolInputError catch (e) {
      return ToolOutcome(jsonEncode({'error': e.message}), isError: true);
    } catch (e) {
      return ToolOutcome(jsonEncode({'error': 'Could not do that on the phone: $e'}), isError: true);
    }
  }

  Future<ToolOutcome> _run(String name, Map<String, dynamic> i) async {
    switch (name) {
      case 'list_projects':
        final ps = await db.projectDao.forCompany(companyId);
        return _ok([for (final p in ps) {'id': p.id, 'name': p.name, 'client': p.clientName, 'status': p.status}]);
      case 'project_overview':
        return _ok(await _overview(await _project(i)));
      case 'list_workers':
        return _ok(await _workers(await _project(i)));
      case 'list_tasks':
        return _ok(await _tasks(i));
      case 'list_money':
        return _ok(await _money(await _project(i), (_num(i, 'days') ?? 30).clamp(1, 366).toInt()));
      case 'list_issues':
        final p = await _project(i);
        final issues = (await db.issueDao.forProject(p.id)).where((x) => x.status == 'open' || x.status == 'in_progress');
        return _ok([
          for (final x in issues) {'description': x.description, 'severity': x.severity, 'since': isoDay(x.createdAt)}
        ]);
      case 'pending_approvals':
        return _ok(await _approvals());
      case 'stock_summary':
        return _ok(await _stock(await _project(i)));
      case 'open_screen':
        final screen = _str(i, 'screen', required: true)!;
        final pid = _str(i, 'project_id');
        if (_projectScreens.contains(screen)) {
          if (pid == null) throw ToolInputError('project_id is needed for the $screen screen.');
          await _project(i);
        }
        return ToolOutcome(jsonEncode({'shown': 'A button to open $screen is on the screen now.'}),
            link: ScreenLink(screen, projectId: pid));
    }
    if (writeTools.contains(name)) return _write(name, i);
    throw ToolInputError('Unknown action $name.');
  }

  static const _projectScreens = {
    'project', 'tasks', 'daily_reports', 'issues', 'team_chat', 'purchasing', 'labour', 'money', 'equipment', //
    'inspections', 'documents', 'workers', 'estimation',
  };

  // ---------------------------------------------------------------------------
  // Confirm cards

  /// One line for the confirm card, in the app's language, of what [name]
  /// would save. Throws [ToolInputError] for an input that can't be saved,
  /// so a broken action never reaches the card.
  Future<String> describe(String name, Map<String, dynamic> i) async {
    switch (name) {
      case 'create_project':
        return trf('New project: {name}', {'name': _text(i, 'name', 200)});
      case 'add_expense':
        final p = await _project(i);
        return trf('Expense {amount} for {category} at {site}', {
          'amount': rupees(_money1(i)),
          'category': tr(_category(i)),
          'site': p.name,
        }) +
            _noteSuffix(i);
      case 'record_payment_received':
        final p = await _project(i);
        return trf('Payment received {amount} from {party} at {site}',
            {'amount': rupees(_money1(i)), 'party': _text(i, 'from_party', 120), 'site': p.name});
      case 'add_task':
        final p = await _project(i);
        final due = _date(i, 'due_date');
        return trf('New task at {site}: {title}', {'site': p.name, 'title': _text(i, 'title', 200)}) +
            (due == null ? '' : ' · ${fmtDate(due)}');
      case 'update_task':
        final t = await _task(i);
        final done = i['done'] == true || (_num(i, 'progress') ?? 0) >= 100;
        return done
            ? trf('Mark done: {title}', {'title': t.title})
            : trf('Set {title} to {p}%', {'title': t.title, 'p': _progress(i)});
      case 'add_worker':
        final p = await _project(i);
        return trf('Add worker {name} at {site}', {'name': _text(i, 'name', 120), 'site': p.name});
      case 'mark_attendance':
        final p = await _project(i);
        final names = _names(i);
        return trf('Mark present at {site}: {names}', {'site': p.name, 'names': names.join(', ')});
      case 'report_issue':
        final p = await _project(i);
        return trf('Problem at {site}: {text}', {'site': p.name, 'text': _text(i, 'description', 1000)});
      case 'add_daily_report':
        final p = await _project(i);
        return trf("Today's report for {site}: {text}", {'site': p.name, 'text': _text(i, 'work_summary', 4000)});
      case 'record_material_received':
        final p = await _project(i);
        return trf('Material received at {site}: {qty} {material}', {
          'site': p.name,
          'qty': '${fmtQty(_qty(i))} ${_str(i, 'unit') ?? ''}'.trim(),
          'material': _text(i, 'material', 200),
        });
      case 'record_material_used':
        final p = await _project(i);
        return trf('Material used at {site}: {qty} {material}', {
          'site': p.name,
          'qty': '${fmtQty(_qty(i))} ${_str(i, 'unit') ?? ''}'.trim(),
          'material': _text(i, 'material', 200),
        });
    }
    throw ToolInputError('Unknown action $name.');
  }

  String _noteSuffix(Map<String, dynamic> i) {
    final n = _str(i, 'note');
    return n == null ? '' : ' · $n';
  }

  // ---------------------------------------------------------------------------
  // Writes

  Future<ToolOutcome> _write(String name, Map<String, dynamic> i) async {
    switch (name) {
      case 'create_project':
        final client = _str(i, 'client_name');
        final p = await db.projectDao.create(ProjectsCompanion.insert(
          id: _uuid.v4(),
          companyId: companyId,
          name: _text(i, 'name', 200),
          clientName: Value(client == null ? null : _cut(client, 200)),
          status: const Value('active'),
        ));
        return ToolOutcome(jsonEncode({'saved': true, 'project_id': p.id, 'name': p.name}), changedProjects: true);
      case 'add_expense':
        final p = await _project(i);
        final amount = _money1(i);
        await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          category: _category(i),
          amount: amount,
          incurredOn: isoDay(_date(i, 'date') ?? _now),
          recordedBy: userId,
          note: Value(_str(i, 'note') == null ? null : _cut(_str(i, 'note')!, 300)),
        ));
        return _saved(p.id, {'amount': amount, 'category': _category(i)});
      case 'record_payment_received':
        final p = await _project(i);
        final mode = _str(i, 'mode', required: true)!;
        if (!_paymentModes.contains(mode)) throw ToolInputError('mode must be cash, upi, bank or cheque.');
        await db.paymentDao.create(PaymentsReceivedCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          amount: _money1(i),
          receivedOn: _date(i, 'date') ?? _now,
          fromParty: _text(i, 'from_party', 120),
          mode: mode,
          recordedBy: userId,
          note: Value(_str(i, 'note') == null ? null : _cut(_str(i, 'note')!, 300)),
        ));
        return _saved(p.id, {'amount': _money1(i)});
      case 'add_task':
        final p = await _project(i);
        final priority = _str(i, 'priority') ?? 'normal';
        final t = await db.taskDao.create(TasksCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          title: _text(i, 'title', 200),
          dueDate: Value(_date(i, 'due_date')),
          priority: Value(const {'low', 'normal', 'high'}.contains(priority) ? priority : 'normal'),
        ));
        return _saved(p.id, {'task_id': t.id});
      case 'update_task':
        final t = await _task(i);
        if (i['done'] == true || (_num(i, 'progress') ?? 0) >= 100) {
          await db.taskDao.updateStatus(t.id, 'done');
        } else {
          await db.taskDao.setProgress(t.id, _progress(i));
        }
        return _saved(t.projectId, {'task_id': t.id});
      case 'add_worker':
        final p = await _project(i);
        final wage = _num(i, 'daily_wage');
        final w = await db.workerDao.create(WorkersCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          name: _text(i, 'name', 120),
          role: Value(_str(i, 'trade') == null ? null : _cut(_str(i, 'trade')!, 100)),
          phone: Value(_str(i, 'phone') == null ? null : _cut(_str(i, 'phone')!, 30)),
          dailyWage: Value(wage != null && wage > 0 && wage < 100000 ? wage.toDouble() : null),
          status: const Value('active'),
        ));
        return _saved(p.id, {'worker_id': w.id});
      case 'mark_attendance':
        return _markAttendance(await _project(i), _names(i));
      case 'report_issue':
        final p = await _project(i);
        final sev = _str(i, 'severity') ?? 'medium';
        await db.issueDao.create(IssuesCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          description: _text(i, 'description', 1000),
          severity: Value(const {'low', 'medium', 'high'}.contains(sev) ? sev : 'medium'),
          status: const Value('open'),
        ));
        return _saved(p.id, {});
      case 'add_daily_report':
        final p = await _project(i);
        final men = _num(i, 'manpower_count');
        final weather = _str(i, 'weather');
        await db.dprDao.create(DprEntriesCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          createdBy: userId,
          entryDate: _now,
          workSummary: _text(i, 'work_summary', 4000),
          manpowerCount: Value(men == null ? 0 : men.clamp(0, 10000).toInt()),
          weather: Value(weather == null ? null : _cut(weather, 50)),
        ));
        return _saved(p.id, {});
      case 'record_material_received':
        final p = await _project(i);
        final amount = _num(i, 'amount');
        await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          materialName: _text(i, 'material', 200),
          quantity: _qty(i),
          unit: Value(_str(i, 'unit') == null ? null : _cut(_str(i, 'unit')!, 20)),
          amount: amount != null && amount > 0 ? amount.toDouble() : 0,
          receivedBy: userId,
          receivedOn: _now,
        ));
        return _saved(p.id, {});
      case 'record_material_used':
        final p = await _project(i);
        await db.materialDao.recordUsage(MaterialUsageCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          materialName: _text(i, 'material', 200),
          quantity: _qty(i),
          unit: Value(_str(i, 'unit') == null ? null : _cut(_str(i, 'unit')!, 20)),
          recordedBy: userId,
          usedOn: _now,
        ));
        return _saved(p.id, {});
    }
    throw ToolInputError('Unknown action $name.');
  }

  ToolOutcome _saved(String projectId, Map<String, Object?> extra) =>
      ToolOutcome(jsonEncode({'saved': true, ...extra}), changedProjectId: projectId);

  Future<ToolOutcome> _markAttendance(Project p, List<String> names) async {
    final workers = await db.workerDao.forProject(p.id);
    final todays = (await db.attendanceDao.forProject(p.id)).where((a) => isSameDay(a.punchIn, _now)).toList();
    final marked = <String>[], already = <String>[], walkIn = <String>[];
    for (final raw in names) {
      final name = _cut(raw.trim(), 120);
      if (name.isEmpty) continue;
      final w = workers.where((w) => w.name.trim().toLowerCase() == name.toLowerCase()).firstOrNull;
      final shown = w?.name ?? name;
      final isIn = todays.any((a) =>
          (w != null && a.workerId == w.id) || a.workerName.trim().toLowerCase() == shown.trim().toLowerCase());
      if (isIn) {
        already.add(shown);
        continue;
      }
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: _uuid.v4(),
        projectId: p.id,
        workerName: shown,
        workerId: w == null ? const Value.absent() : Value(w.id),
        recordedBy: userId,
        punchIn: _now,
      ));
      (w == null ? walkIn : marked).add(shown);
    }
    return ToolOutcome(
      jsonEncode({'saved': true, 'marked_present': marked, 'walk_in_workers': walkIn, 'already_present': already}),
      changedProjectId: p.id,
    );
  }

  // ---------------------------------------------------------------------------
  // Reads

  Future<Map<String, Object?>> _overview(Project p) async {
    final tasks = await db.taskDao.forProject(p.id);
    final open = tasks.where((t) => t.status != 'done').toList();
    final today = DateTime(_now.year, _now.month, _now.day);
    final late = open.where((t) => t.dueDate != null && t.dueDate!.isBefore(today)).length;
    final present = {
      for (final a in await db.attendanceDao.forProject(p.id))
        if (isSameDay(a.punchIn, _now)) a.workerName.trim().toLowerCase()
    }.length;
    final expenses = await db.expenseDao.forProject(p.id);
    final monthKey = isoDay(_now).substring(0, 7);
    final payments = await db.paymentDao.forProject(p.id);
    final dprs = await db.dprDao.forProject(p.id);
    final cost = await ProjectCostSummary.forProject(db, p);
    final lastDpr = dprs.isEmpty ? null : dprs.map((d) => d.entryDate).reduce((a, b) => a.isAfter(b) ? a : b);
    return {
      'name': p.name,
      'client': p.clientName,
      'status': p.status,
      'workers_on_list': (await db.workerDao.forProject(p.id)).where((w) => w.status == 'active').length,
      'present_today': present,
      'open_tasks': open.length,
      'late_tasks': late,
      'open_issues': cost.openIssues,
      'spent_total': _round(expenses.fold<double>(0, (s, e) => s + e.amount)),
      'spent_this_month':
          _round(expenses.where((e) => e.incurredOn.startsWith(monthKey)).fold<double>(0, (s, e) => s + e.amount)),
      'received_from_client': _round(payments.fold<double>(0, (s, x) => s + x.amount)),
      'budget': _round(cost.budget),
      'actual_cost': _round(cost.actual),
      'budget_status': cost.status,
      'last_daily_report': lastDpr == null ? null : isoDay(lastDpr),
      'daily_report_done_today': lastDpr != null && isSameDay(lastDpr, _now),
    };
  }

  Future<List<Map<String, Object?>>> _workers(Project p) async {
    final present = {
      for (final a in await db.attendanceDao.forProject(p.id))
        if (isSameDay(a.punchIn, _now)) ...[a.workerId ?? '', a.workerName.trim().toLowerCase()]
    };
    return [
      for (final w in await db.workerDao.forProject(p.id))
        if (w.status == 'active')
          {
            'id': w.id,
            'name': w.name,
            'trade': w.role,
            'daily_wage': w.dailyWage,
            'phone': w.phone,
            'present_today': present.contains(w.id) || present.contains(w.name.trim().toLowerCase()),
          }
    ];
  }

  Future<List<Map<String, Object?>>> _tasks(Map<String, dynamic> i) async {
    final pid = _str(i, 'project_id');
    final projects = await db.projectDao.forCompany(companyId);
    final names = {for (final p in projects) p.id: p.name};
    final List<Task> tasks;
    if (pid != null) {
      final p = await _project(i);
      tasks = await db.taskDao.forProject(p.id);
    } else {
      tasks = [for (final p in projects) ...await db.taskDao.forProject(p.id)];
    }
    final onlyOpen = i['only_open'] == true;
    return [
      for (final t in tasks)
        if (!onlyOpen || t.status != 'done')
          {
            'id': t.id,
            'project': names[t.projectId],
            'title': t.title,
            'status': t.status,
            'progress': t.progress,
            'due': t.dueDate == null ? null : isoDay(t.dueDate!),
            'priority': t.priority,
          }
    ].take(100).toList();
  }

  Future<Map<String, Object?>> _money(Project p, int days) async {
    final from = DateTime(_now.year, _now.month, _now.day).subtract(Duration(days: days - 1));
    final expenses = (await db.expenseDao.forProject(p.id)).where((e) => e.incurredOn.compareTo(isoDay(from)) >= 0).toList()
      ..sort((a, b) => b.incurredOn.compareTo(a.incurredOn));
    final payments = (await db.paymentDao.forProject(p.id)).where((x) => !x.receivedOn.isBefore(from)).toList()
      ..sort((a, b) => b.receivedOn.compareTo(a.receivedOn));
    return {
      'from': isoDay(from),
      'spent': _round(expenses.fold<double>(0, (s, e) => s + e.amount)),
      'received': _round(payments.fold<double>(0, (s, x) => s + x.amount)),
      'expenses': [
        for (final e in expenses.take(50)) {'date': e.incurredOn, 'amount': e.amount, 'category': e.category, 'note': e.note}
      ],
      'payments': [
        for (final x in payments.take(30))
          {'date': isoDay(x.receivedOn), 'amount': x.amount, 'from': x.fromParty, 'mode': x.mode}
      ],
    };
  }

  Future<List<Map<String, Object?>>> _approvals() async {
    final projects = {for (final p in await db.projectDao.forCompany(companyId)) p.id: p.name};
    return [
      for (final a in await db.approvalDao.pendingFor(null))
        if (projects.containsKey(a.projectId))
          {'what': a.entityType, 'project': projects[a.projectId], 'note': a.decisionNote, 'since': isoDay(a.createdAt)}
    ];
  }

  Future<List<Map<String, Object?>>> _stock(Project p) async {
    final rows = <String, ({String name, String? unit, double inQty, double outQty})>{};
    for (final r in await db.materialDao.forProject(p.id)) {
      final k = _stockKey(r.materialName, r.unit);
      final o = rows[k];
      rows[k] = (name: o?.name ?? r.materialName, unit: o?.unit ?? r.unit, inQty: (o?.inQty ?? 0) + r.quantity, outQty: o?.outQty ?? 0);
    }
    for (final u in await db.materialDao.usageForProject(p.id)) {
      final k = _stockKey(u.materialName, u.unit);
      final o = rows[k];
      rows[k] = (name: o?.name ?? u.materialName, unit: o?.unit ?? u.unit, inQty: o?.inQty ?? 0, outQty: (o?.outQty ?? 0) + u.quantity);
    }
    return [
      for (final r in rows.values)
        {'material': r.name, 'unit': r.unit, 'received': r.inQty, 'used': r.outQty, 'left': r.inQty - r.outQty}
    ];
  }

  /// Same material in another unit stays its own line, as on the Stock screen.
  static String _stockKey(String name, String? unit) =>
      '${name.trim().toLowerCase()}|${(unit ?? '').trim().toLowerCase()}';

  // ---------------------------------------------------------------------------
  // Inputs

  ToolOutcome _ok(Object data) => ToolOutcome(jsonEncode(data));

  /// The project named in the input, only if it is this company's.
  Future<Project> _project(Map<String, dynamic> i) async {
    final id = _str(i, 'project_id', required: true)!;
    final p = await db.projectDao.byId(id);
    if (p == null || p.companyId != companyId) {
      throw ToolInputError('No project with id $id. Call list_projects for the ids.');
    }
    return p;
  }

  Future<Task> _task(Map<String, dynamic> i) async {
    final id = _str(i, 'task_id', required: true)!;
    for (final p in await db.projectDao.forCompany(companyId)) {
      for (final t in await db.taskDao.forProject(p.id)) {
        if (t.id == id) return t;
      }
    }
    throw ToolInputError('No task with id $id. Call list_tasks for the ids.');
  }

  static String? _str(Map<String, dynamic> i, String key, {bool required = false}) {
    final v = i[key];
    final s = v is String ? v.trim() : (v is num ? '$v' : null);
    if (s == null || s.isEmpty) {
      if (required) throw ToolInputError('$key is missing.');
      return null;
    }
    return s;
  }

  static String _text(Map<String, dynamic> i, String key, int max) => _cut(_str(i, key, required: true)!, max);

  static String _cut(String s, int max) => s.length > max ? s.substring(0, max) : s;

  static num? _num(Map<String, dynamic> i, String key) {
    final v = i[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v.replaceAll(',', '').trim());
    return null;
  }

  static double _money1(Map<String, dynamic> i) {
    final v = _num(i, 'amount');
    if (v == null || v <= 0) throw ToolInputError('amount must be more than 0 rupees.');
    if (v >= 1e10) throw ToolInputError('amount looks too large; check it with the person.');
    return v.toDouble();
  }

  static double _qty(Map<String, dynamic> i) {
    final v = _num(i, 'quantity');
    if (v == null || v <= 0 || v >= 1e9) throw ToolInputError('quantity must be more than 0.');
    return v.toDouble();
  }

  static int _progress(Map<String, dynamic> i) {
    final v = _num(i, 'progress');
    if (v == null) throw ToolInputError('progress (0 to 100) or done is needed.');
    return v.clamp(0, 100).round();
  }

  static String _category(Map<String, dynamic> i) {
    final c = _str(i, 'category', required: true)!;
    return expenseCategories.firstWhere((x) => x.toLowerCase() == c.toLowerCase(), orElse: () => 'Other');
  }

  static List<String> _names(Map<String, dynamic> i) {
    final v = i['worker_names'];
    final names = v is List ? [for (final n in v) if (n is String && n.trim().isNotEmpty) n.trim()] : <String>[];
    if (names.isEmpty) throw ToolInputError('worker_names is empty.');
    if (names.length > 300) throw ToolInputError('At most 300 workers at once.');
    return names;
  }

  DateTime? _date(Map<String, dynamic> i, String key) {
    final s = _str(i, key);
    if (s == null) return null;
    final d = DateTime.tryParse(s);
    if (d == null) throw ToolInputError('$key must be YYYY-MM-DD.');
    if (d.year < 2000 || d.year > 2100) throw ToolInputError('$key looks wrong.');
    return DateTime(d.year, d.month, d.day, _now.hour, _now.minute);
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
