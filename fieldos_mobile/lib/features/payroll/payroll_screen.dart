/// Staff salaries: monthly staff (engineers, supervisors, accounts,
/// drivers) with their salary, advances, and each month's payslips with
/// PF, ESI and professional tax worked out, a payslip PDF, and the net pay
/// put into the site's money book when it is paid.
///
/// Salaries are private, so only owners and project managers see this.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/attendance/staff_attendance.dart' show StaffMonth, staffMonth;
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart' show billingProfileProvider;
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';
import 'package:fieldos_mobile/features/payroll/payslip_pdf.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart' show CloudMember;

typedef PayrollData = ({
  List<StaffMember> staff,
  List<StaffAdvance> advances,
  List<PayrollLine> lines,
  List<Project> sites,
});

final payrollDataProvider = FutureProvider.autoDispose.family<PayrollData, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final dao = db.payrollDao;
  return (
    staff: await dao.staffFor(companyId),
    advances: await dao.advancesFor(companyId),
    lines: await dao.linesFor(companyId),
    sites: await db.projectDao.forCompany(companyId),
  );
});

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', ''));
String _days(double d) => d == d.roundToDouble() ? d.toInt().toString() : fmtQty(d);

/// "November 2026" in the app's language.
String monthLabel(String key) {
  final d = monthStart(key);
  return '${tr(const [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
    'December'
  ][d.month - 1])} ${d.year}';
}

class StaffSalariesScreen extends ConsumerStatefulWidget {
  const StaffSalariesScreen({super.key, required this.companyId, required this.userId, this.month});
  final String companyId;
  final String userId;
  final String? month;

  @override
  ConsumerState<StaffSalariesScreen> createState() => _StaffSalariesScreenState();
}

class _StaffSalariesScreenState extends ConsumerState<StaffSalariesScreen> {
  late String _month = widget.month ?? monthKey(DateTime.now());

  void _refresh() => ref.invalidate(payrollDataProvider(widget.companyId));

  Future<void> _addStaff(PayrollData d) async {
    if (await showStaffForm(context, ref, companyId: widget.companyId, sites: d.sites) != null) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(payrollDataProvider(widget.companyId));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Staff salaries')),
          bottom: TabBar(tabs: [Tab(text: tr('Month')), Tab(text: tr('Staff'))]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
          data: (d) => TabBarView(children: [
            d.staff.isEmpty
                ? EmptyState(
                    icon: Icons.badge_outlined,
                    title: tr('No staff yet'),
                    message: tr('Add the people on a monthly salary. Each month FieldOS works out their pay for the days '
                        'worked, PF, ESI, professional tax and advance recovery, and makes the payslips.'),
                    actionLabel: tr('Add staff'),
                    onAction: () => _addStaff(d),
                  )
                : _MonthTab(
                    data: d,
                    month: _month,
                    companyId: widget.companyId,
                    userId: widget.userId,
                    onMonth: (m) => setState(() => _month = m),
                    onChanged: _refresh,
                  ),
            _StaffTab(data: d, companyId: widget.companyId, userId: widget.userId, onAdd: () => _addStaff(d), onChanged: _refresh),
          ]),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.bodySmall),
      Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _MonthTab extends ConsumerWidget {
  const _MonthTab({
    required this.data,
    required this.month,
    required this.companyId,
    required this.userId,
    required this.onMonth,
    required this.onChanged,
  });
  final PayrollData data;
  final String month;
  final String companyId;
  final String userId;
  final ValueChanged<String> onMonth;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = [for (final l in data.lines) if (l.month == month) l];
    final staff = {for (final s in data.staff) s.id: s};
    lines.sort((a, b) => (staff[a.staffId]?.name ?? '').toLowerCase().compareTo((staff[b.staffId]?.name ?? '').toLowerCase()));
    final have = {for (final l in lines) l.staffId};
    final start = monthStart(month);
    final next = DateTime(start.year, start.month + 1);
    final missing = data.staff
        .where((s) => s.active && !have.contains(s.id) && (s.joinedOn == null || s.joinedOn!.isBefore(next)))
        .length;
    final t = payrollTotals(lines);
    final current = monthKey(DateTime.now());
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
      Row(children: [
        IconButton(
            key: const Key('month-prev'),
            tooltip: tr('Previous month'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onMonth(shiftMonth(month, -1))),
        Expanded(
            child: Text(monthLabel(month),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(
            key: const Key('month-next'),
            tooltip: tr('Next month'),
            icon: const Icon(Icons.chevron_right),
            onPressed: month.compareTo(current) >= 0 ? null : () => onMonth(shiftMonth(month, 1))),
      ]),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 24, runSpacing: 10, children: [
            _Figure(label: tr('Net to pay'), value: rupees(t.net)),
            _Figure(label: tr('Paid'), value: '${t.paid}/${t.people}'),
            _Figure(label: tr('Gross'), value: rupees(t.gross)),
            if (t.pf > 0) _Figure(label: tr('PF to deposit'), value: rupees(t.pf)),
            if (t.esi > 0) _Figure(label: tr('ESI to deposit'), value: rupees(t.esi)),
            if (t.pt > 0) _Figure(label: tr('Professional tax'), value: rupees(t.pt)),
            _Figure(label: tr('Cost to company'), value: rupees(t.cost)),
          ]),
        ),
      ),
      if (missing > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            key: const Key('make-month'),
            icon: const Icon(Icons.playlist_add_check),
            label: Text(lines.isEmpty
                ? tr('Make this month\'s salaries')
                : trf('Add {n} more people', {'n': missing})),
            onPressed: () async {
              final n = await ref.read(appDatabaseProvider).payrollDao.makeMonth(companyId, month, by: userId);
              onChanged();
              if (context.mounted) showSnack(context, trf('{n} payslips made', {'n': n}));
            },
          ),
        ),
      if (lines.isEmpty && missing == 0)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No salaries for this month.'), textAlign: TextAlign.center),
        ),
      for (final l in lines)
        ListTile(
          key: Key('line-${l.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(staff[l.staffId]?.name ?? '?'),
          subtitle: Text([
            trf('{paid} of {days} days', {'paid': _days(l.paidDays), 'days': l.daysInMonth}),
            trf('Gross {amount}', {'amount': rupees(l.gross)}),
            if (l.advanceRecovery > 0) trf('Advance {amount}', {'amount': rupees(l.advanceRecovery)}),
          ].join(' · ')),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rupees(l.net), style: const TextStyle(fontWeight: FontWeight.w700)),
            StatusPill(l.status == 'paid' ? 'Paid' : 'Draft', tone: l.status == 'paid' ? PillTone.ok : PillTone.warn),
          ]),
          onTap: () async {
            final s = staff[l.staffId];
            if (s == null) return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => PayslipSheet(line: l, staff: s, data: data, companyId: companyId, userId: userId),
            );
            onChanged();
          },
        ),
    ]);
  }
}

/// One payslip: change the days or recovery while it is a draft, share
/// the PDF, mark it paid.
class PayslipSheet extends ConsumerStatefulWidget {
  const PayslipSheet(
      {super.key, required this.line, required this.staff, required this.data, required this.companyId, required this.userId});
  final PayrollLine line;
  final StaffMember staff;
  final PayrollData data;
  final String companyId;
  final String userId;

  @override
  ConsumerState<PayslipSheet> createState() => _PayslipSheetState();
}

class _PayslipSheetState extends ConsumerState<PayslipSheet> {
  late PayrollLine _line = widget.line;
  late final _daysCtl = TextEditingController(text: _days(widget.line.paidDays));
  late final _advance = TextEditingController(text: fmtQty(widget.line.advanceRecovery));
  late final _other = TextEditingController(text: fmtQty(widget.line.otherDeduction));
  String? _error;
  bool _busy = false;
  StaffMonth? _attendance;

  bool get _paid => _line.status == 'paid';

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  /// Their check-ins this month, when the salary is linked to a login.
  Future<void> _loadAttendance() async {
    final login = widget.staff.userId;
    if (login == null) return;
    final rows = await ref.read(appDatabaseProvider).staffAttendanceDao.forUsers([login]);
    final m = staffMonth(rows, widget.line.month, now: DateTime.now(), joinedOn: widget.staff.joinedOn);
    if (mounted && m.hasAny) {
      setState(() {
        _attendance = m;
      });
    }
  }

  double get _owed =>
      advanceOwed(widget.staff.id, widget.data.advances, widget.data.lines, exceptLineId: _line.id);

  PayCalc? get _preview {
    final d = _num(_daysCtl.text);
    if (d == null || d < 0 || d > _line.daysInMonth) return null;
    return computePay(widget.staff,
        days: _line.daysInMonth,
        paidDays: d,
        advanceWanted: _num(_advance.text) ?? 0,
        advanceOwed: _owed,
        otherDeduction: _num(_other.text) ?? 0);
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ArgumentError catch (e) {
      setState(() => _error = tr('${e.message}'));
    } catch (e, st) {
      setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
        final d = _num(_daysCtl.text);
        if (d == null) throw ArgumentError(trf('Paid days are 0 to {n}.', {'n': _line.daysInMonth}));
        final l = await ref.read(appDatabaseProvider).payrollDao.recalculate(_line.id,
            paidDays: d, advanceRecovery: _num(_advance.text) ?? 0, otherDeduction: _num(_other.text) ?? 0);
        setState(() => _line = l);
        _advance.text = fmtQty(l.advanceRecovery);
      });

  Future<void> _pdf() => _run(() async {
        final db = ref.read(appDatabaseProvider);
        final company = ref.read(sessionProvider).activeCompany;
        final site = widget.data.sites.where((p) => p.id == _line.projectId).firstOrNull;
        await sharePayslip(
          line: _line,
          staff: widget.staff,
          companyName: company?.name ?? '',
          siteName: site?.name,
          profile: await ref.read(billingProfileProvider(widget.companyId).future),
          branding: await loadBranding(db, widget.companyId),
        );
      });

  Future<void> _markPaid() async {
    var mode = 'bank';
    var toSite = _line.projectId != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(trf('Pay {amount}', {'amount': rupees(_line.net)})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final MapEntry(:key, :value) in payModes.entries)
                ChoiceChip(
                    key: Key('pay-$key'),
                    label: Text(tr(value)),
                    selected: mode == key,
                    onSelected: (_) => setState(() => mode = key)),
            ]),
            if (_line.projectId != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: toSite,
                onChanged: (v) => setState(() => toSite = v),
                title: Text(tr('Add to the site\'s money book')),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('pay-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Mark paid'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final l = await ref
          .read(appDatabaseProvider)
          .payrollDao
          .markPaid(_line.id, mode: mode, by: widget.userId, addSiteExpense: toSite);
      setState(() => _line = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _paid ? null : _preview;
    final l = _line;
    final theme = Theme.of(context);
    Widget row(String label, double v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
            Text(rupees(v), style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
          ]),
        );
    final gross = p?.gross ?? l.gross;
    final pf = p?.pfEmployee ?? l.pfEmployee;
    final esi = p?.esiEmployee ?? l.esiEmployee;
    final pt = p?.pt ?? l.pt;
    final adv = p?.advanceRecovery ?? l.advanceRecovery;
    final other = p?.otherDeduction ?? l.otherDeduction;
    final net = p?.net ?? l.net;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.staff.name, style: theme.textTheme.titleLarge),
          Text(monthLabel(l.month), style: theme.textTheme.bodySmall),
          if (!_paid) ...[
            if (_attendance case final a?)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.camera_front_outlined),
                  title: Text(
                      trf('From attendance: {n} days at work + {s} Sundays off', {'n': a.present, 's': a.weeklyOffs})),
                  subtitle: a.waiting > 0 ? Text(trf('{w} days still waiting for your OK', {'w': a.waiting})) : null,
                  trailing: TextButton(
                    key: const Key('slip-use-attendance'),
                    onPressed: () => setState(() {
                      _daysCtl.text = _days(a.paidDays);
                    }),
                    child: Text(trf('Use {n}', {'n': _days(a.paidDays)})),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('slip-days'),
                  controller: _daysCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: trf('Days paid (of {n})', {'n': l.daysInMonth})),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('slip-advance'),
                  controller: _advance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: tr('Advance to recover'),
                      helperText: trf('Owed {amount}', {'amount': rupees(_owed)})),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            TextField(
              key: const Key('slip-other'),
              controller: _other,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Other deduction (₹)')),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          row(tr('Gross'), gross),
          if (pf > 0) row(tr('Provident fund'), -pf),
          if (esi > 0) row(tr('ESI'), -esi),
          if (pt > 0) row(tr('Professional tax'), -pt),
          if (adv > 0) row(tr('Advance recovered'), -adv),
          if (other > 0) row(tr('Other deduction'), -other),
          const Divider(),
          row(tr('Net pay'), net, bold: true),
          if (_paid && l.paidOn != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(trf('Paid on {date}', {'date': fmtDate(l.paidOn!)}), style: theme.textTheme.bodySmall),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: FormMessage(_error!)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.end, children: [
            if (!_paid)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await ref.read(appDatabaseProvider).payrollDao.deleteDraft(l.id);
                          if (context.mounted) Navigator.pop(context);
                        }),
                child: Text(tr('Remove')),
              ),
            OutlinedButton.icon(
                key: const Key('slip-pdf'),
                onPressed: _busy ? null : _pdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(tr('Payslip'))),
            if (!_paid) ...[
              OutlinedButton(key: const Key('slip-save'), onPressed: _busy ? null : _save, child: Text(tr('Save'))),
              FilledButton(
                key: const Key('slip-pay'),
                onPressed: _busy
                    ? null
                    : () async {
                        await _save();
                        if (_error == null && mounted) await _markPaid();
                      },
                child: Text(tr('Mark paid')),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _StaffTab extends ConsumerWidget {
  const _StaffTab({required this.data, required this.companyId, required this.userId, required this.onAdd, required this.onChanged});
  final PayrollData data;
  final String companyId;
  final String userId;
  final VoidCallback onAdd;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = {for (final p in data.sites) p.id: p.name};
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        for (final s in data.staff)
          Builder(builder: (context) {
            final owed = advanceOwed(s.id, data.advances, data.lines);
            return ListTile(
              key: Key('staff-${s.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.name),
              subtitle: Text([
                if (s.designation != null) s.designation!,
                if (s.projectId != null && sites[s.projectId] != null) sites[s.projectId]!,
                if (owed > 0) trf('Advance owed {amount}', {'amount': rupees(owed)}),
              ].join(' · ')),
              trailing: s.active
                  ? Text(trf('{amount} a month', {'amount': rupees(fullMonthGross(s))}))
                  : const StatusPill('Left'),
              onTap: () async {
                final choice = await showModalBottomSheet<String>(
                  context: context,
                  useSafeArea: true,
                  builder: (ctx) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(tr('Edit')),
                          onTap: () => Navigator.pop(ctx, 'edit')),
                      ListTile(
                          key: const Key('staff-advance'),
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(tr('Give advance')),
                          onTap: () => Navigator.pop(ctx, 'advance')),
                    ]),
                  ),
                );
                if (!context.mounted) return;
                if (choice == 'edit') {
                  await showStaffForm(context, ref, companyId: companyId, sites: data.sites, staff: s);
                } else if (choice == 'advance') {
                  await _giveAdvance(context, ref, s);
                }
                onChanged();
              },
            );
          }),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'add-staff',
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(tr('Add staff')),
        ),
      ),
    ]);
  }

  Future<void> _giveAdvance(BuildContext context, WidgetRef ref, StaffMember s) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('Advance to {name}', {'name': s.name})),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('advance-amount'),
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Amount (₹)')),
          ),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('advance-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final a = _num(amount.text);
    if (ok != true || a == null || a <= 0) return;
    await ref.read(appDatabaseProvider).payrollDao.giveAdvance(staffId: s.id, amount: a, by: userId, note: note.text);
  }
}

Future<StaffMember?> showStaffForm(BuildContext context, WidgetRef ref,
    {required String companyId, required List<Project> sites, StaffMember? staff}) {
  return showModalBottomSheet<StaffMember>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StaffForm(companyId: companyId, sites: sites, staff: staff),
  );
}

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({required this.companyId, required this.sites, this.staff});
  final String companyId;
  final List<Project> sites;
  final StaffMember? staff;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  late final s = widget.staff;
  late final _name = TextEditingController(text: s?.name ?? '');
  late final _phone = TextEditingController(text: s?.phone ?? '');
  late final _designation = TextEditingController(text: s?.designation ?? '');
  late final _basic = TextEditingController(text: s == null ? '' : fmtQty(s!.basic));
  late final _hra = TextEditingController(text: s == null || s!.hra == 0 ? '' : fmtQty(s!.hra));
  late final _other = TextEditingController(text: s == null || s!.otherAllowance == 0 ? '' : fmtQty(s!.otherAllowance));
  late final _uan = TextEditingController(text: s?.uan ?? '');
  late String? _site = s?.projectId;
  late bool _pf = s?.pf ?? true;
  late bool _esi = s?.esi ?? true;
  late String _pt = s?.ptState ?? 'TS';
  late bool _active = s?.active ?? true;
  late DateTime? _joined = s?.joinedOn;
  late String? _login = s?.userId;
  String? _error;

  Future<void> _save() async {
    final dao = ref.read(appDatabaseProvider).payrollDao;
    try {
      final basic = _num(_basic.text) ?? 0;
      final hra = _num(_hra.text) ?? 0;
      final other = _num(_other.text) ?? 0;
      StaffMember? out;
      if (s == null) {
        out = await dao.addStaff(
          companyId: widget.companyId,
          name: _name.text,
          basic: basic,
          hra: hra,
          otherAllowance: other,
          pf: _pf,
          esi: _esi,
          ptState: _pt,
          phone: _phone.text,
          designation: _designation.text,
          projectId: _site,
          uan: _uan.text,
          joinedOn: _joined,
          userId: _login,
        );
      } else {
        await dao.updateStaff(s!.id,
            name: _name.text,
            basic: basic,
            hra: hra,
            otherAllowance: other,
            pf: _pf,
            esi: _esi,
            ptState: _pt,
            phone: _phone.text,
            designation: _designation.text,
            projectId: _site,
            uan: _uan.text,
            joinedOn: _joined,
            active: _active,
            userId: Value(_login));
        out = await dao.staffById(s!.id);
      }
      if (mounted) Navigator.pop(context, out);
    } on ArgumentError catch (e) {
      setState(() => _error = tr('${e.message}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gross = (_num(_basic.text) ?? 0) + (_num(_hra.text) ?? 0) + (_num(_other.text) ?? 0);
    TextField money(Key key, TextEditingController c, String label) => TextField(
          key: key,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(s == null ? tr('Add staff') : tr('Edit staff'), style: Theme.of(context).textTheme.titleLarge),
          TextField(
              key: const Key('staff-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Name'))),
          TextField(
              controller: _designation,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Job (e.g. Site engineer)'))),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Phone'))),
          if (widget.sites.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _site,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Salary charged to')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('Office (no site)'))),
                for (final p in widget.sites)
                  DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _site = v),
            ),
          money(const Key('staff-basic'), _basic, tr('Basic a month (₹)')),
          Row(children: [
            Expanded(child: money(const Key('staff-hra'), _hra, tr('HRA (₹)'))),
            const SizedBox(width: 8),
            Expanded(child: money(const Key('staff-other'), _other, tr('Other allowance (₹)'))),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(trf('{amount} a month in all', {'amount': rupees(gross)}),
                style: Theme.of(context).textTheme.bodySmall),
          ),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pf,
              onChanged: (v) => setState(() => _pf = v),
              title: Text(tr('Provident fund (PF)'))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _esi,
            onChanged: (v) => setState(() => _esi = v),
            title: Text(tr('ESI')),
            subtitle: Text(gross > esiWageLimit
                ? tr('Not cut: salary is above ₹21,000')
                : tr('Cut when the salary is ₹21,000 or less')),
          ),
          DropdownButtonFormField<String>(
            initialValue: _pt,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Professional tax')),
            items: [for (final p in ptStates) DropdownMenuItem(value: p, child: Text(tr(ptStateLabels[p]!)))],
            onChanged: (v) => setState(() => _pt = v ?? 'TS'),
          ),
          if (_pf) TextField(controller: _uan, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('UAN'))),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Joined on')),
            subtitle: Text(_joined == null ? tr('No date') : fmtDate(_joined!)),
            trailing: const Icon(Icons.event),
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _joined ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 60)));
              if (d != null) setState(() => _joined = d);
            },
          ),
          Consumer(builder: (context, ref, _) {
            final members = ref.watch(teamRosterProvider(widget.companyId)).value?.members ?? const <CloudMember>[];
            if (members.isEmpty && _login == null) return const SizedBox.shrink();
            return DropdownButtonFormField<String?>(
              key: const Key('staff-login'),
              initialValue: members.any((m) => m.userId == _login) || _login == null ? _login : null,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: tr('Their FieldOS login'),
                  helperText: tr('Their check-ins with a selfie show beside the salary.')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('Not linked'))),
                for (final m in members)
                  DropdownMenuItem<String?>(value: m.userId, child: Text(m.email, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _login = v),
            );
          }),
          if (s != null)
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text(tr('Still working here'))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: FormMessage(_error!)),
          const SizedBox(height: 12),
          FilledButton(key: const Key('staff-save'), onPressed: _save, child: Text(tr('Save'))),
        ]),
      ),
    );
  }
}
