/// "Export to Excel": builds the file on this phone and opens the share
/// sheet (WhatsApp, Gmail, Drive, Files), so the customer always has their
/// own copy of their records.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/data_export.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
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
