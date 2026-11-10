/// "Export to Excel": builds the file on this phone and opens the share
/// sheet (WhatsApp, Gmail, Drive, Files), so the customer always has their
/// own copy of their records.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_export.dart';
import 'package:fieldos_mobile/features/export/audit_trail.dart';
import 'package:fieldos_mobile/features/export/data_export.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Exports one site.
Future<void> exportProjectToExcel(BuildContext context, WidgetRef ref, Project project) =>
    _export(context, ref, ExportScope.project(project.id), label: project.name);

/// Exports every site of the company that is open now (the demo site is
/// left out).
Future<void> exportCompanyToExcel(BuildContext context, WidgetRef ref) async {
  final company = ref.read(sessionProvider).activeCompany;
  if (company == null) {
    showSnack(context, 'There is nothing to export yet.');
    return;
  }
  await _export(context, ref, ExportScope.company(company.id), label: company.name);
}

Future<void> _export(BuildContext context, WidgetRef ref, ExportScope scope, {required String label}) async {
  final db = ref.read(appDatabaseProvider);
  final showMoneyIn = canSeeMoneyIn(ref.read(sessionProvider).role);
  final nav = Navigator.of(context, rootNavigator: true);
  final box = context.findRenderObject() as RenderBox?;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 18),
          Expanded(child: Text(tr('Making the Excel file…'))),
        ],
      ),
    ),
  );
  try {
    final file = await writeExportFile(db, scope, label: label, showMoneyIn: showMoneyIn);
    nav.pop();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: trf('{name}: all records from FieldOS', {'name': label}),
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (e, st) {
    if (nav.canPop()) nav.pop();
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}

/// "Send to your accountant": Tally vouchers or a Zoho Books CSV for a
/// period, shared from the phone.
Future<void> showAccountsExport(BuildContext context, WidgetRef ref) async {
  final company = ref.read(sessionProvider).activeCompany;
  if (company == null) return;
  final now = DateTime.now();
  final fy = financialYear(now);
  final periods = <(String, DateTime?, DateTime?)>[
    (tr('This month'), DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
    (tr('Last month'), DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
    (tr('This financial year'), fy.$1, fy.$2),
    (tr('Everything'), null, null),
  ];
  var pick = 0;
  final format = await showModalBottomSheet<AccountsFormat>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Send to your accountant'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tr('Every expense as a payment voucher and every client payment as a receipt, with GST split out.'),
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < periods.length; i++)
                ChoiceChip(label: Text(periods[i].$1), selected: pick == i, onSelected: (_) => setSheet(() => pick = i)),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('accounts-tally'),
              icon: const Icon(Icons.account_balance_outlined),
              label: Text(tr('Tally vouchers (XML)')),
              onPressed: () => Navigator.pop(ctx, AccountsFormat.tally),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('accounts-zoho'),
              icon: const Icon(Icons.table_rows_outlined),
              label: Text(tr('Zoho Books expenses (CSV)')),
              onPressed: () => Navigator.pop(ctx, AccountsFormat.zoho),
            ),
          ]),
        ),
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  final (_, from, to) = periods[pick];
  try {
    final out = await writeAccountsExport(ref.read(appDatabaseProvider),
        companyId: company.id, companyName: company.name, format: format, from: from, to: to);
    final export = out.export;
    if (export.vouchers == 0) {
      if (context.mounted) showSnack(context, 'No money entries in this period.');
      return;
    }
    final note = format == AccountsFormat.tally
        ? '${company.name}: ${export.vouchers} vouchers for Tally, checked before sending.\n'
            'First import the ledgers file (Gateway > Import > Masters), then the vouchers (Import > Vouchers). '
            'Ledgers: ${export.ledgers.join(', ')}.'
        : '${company.name}: ${export.vouchers} expenses for Zoho Books (Purchases > Expenses > Import), checked before sending.';
    await SharePlus.instance.share(ShareParams(
      files: [
        if (out.ledgersFile != null) XFile(out.ledgersFile!.path, mimeType: 'application/xml'),
        XFile(out.file.path, mimeType: format == AccountsFormat.tally ? 'application/xml' : 'text/csv'),
      ],
      text: note,
      subject: note.split('\n').first,
    ));
  } on AccountsExportProblem catch (e) {
    if (context.mounted) {
      showSnack(context, trf('The export did not pass its check, so it was not sent: {why}', {'why': e.check.problems.first}),
          error: true);
    }
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}

/// Settings > Audit trail: every decision and change of money on the
/// company's sites, as a CSV for an auditor. Owners and managers.
Future<void> shareAuditTrail(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider);
  final company = session.activeCompany;
  if (company == null || !canSeeMoneyIn(session.role)) return;
  try {
    final db = ref.read(appDatabaseProvider);
    final events = await buildAuditTrail(db, company.id);
    if (events.isEmpty) {
      if (context.mounted) showSnack(context, tr('Nothing has been recorded yet.'));
      return;
    }
    final roster = await ref.read(teamRosterProvider(company.id).future);
    final me = session.user;
    String nameOf(String id) {
      if (me != null && (id == me.id || id == roster.myUserId)) return me.name;
      final m = roster.byId(id);
      return m == null ? id : m.email;
    }

    final sites = {for (final p in await db.projectDao.forCompany(company.id)) p.id: p.name};
    final dir = await getTemporaryDirectory();
    final safe = company.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File(p.join(dir.path, '${safe}_audit_trail.csv'));
    await file.writeAsString(auditCsv(events, nameOf: nameOf, siteName: sites), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      text: '${company.name}: audit trail, ${events.length} entries.',
    ));
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}
