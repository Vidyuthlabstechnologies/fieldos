/// Bills, receipts and quotations kept with an expense: photos taken sharp
/// enough to read, or a PDF that came by email or WhatsApp. Onsite's
/// reviews ask to "attach bill with expense" and "add PDF, not only
/// photo". The files stay on the phone that added them, like DPR photos.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// How many bills each of a site's expenses has.
final expenseBillCountsProvider = FutureProvider.autoDispose.family<Map<String, int>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).expenseDao.attachmentCounts(projectId));

final expenseBillsProvider = FutureProvider.autoDispose.family<List<ExpenseAttachment>, String>(
    (ref, expenseId) => ref.watch(appDatabaseProvider).expenseDao.attachmentsFor(expenseId));

/// Opens the picker for a bill: camera (kept sharp), several photos from
/// the gallery, or a PDF.
Future<List<CapturedFile>> pickBills(BuildContext context) =>
    captureCameraFirstMany(context, prefix: 'bill', sharp: true, allowPdf: true);

/// Sends a PDF bill to the share sheet, where the phone's PDF viewer,
/// WhatsApp or email can take it.
Future<void> shareBillFile(String path, {String? text}) => SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: attachmentMimeType(path))],
      text: text,
    ));

Future<void> deleteFileQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// The "Bills" block of an expense: thumbnails and PDFs, tap to open, and
/// "Attach bill" when [canChange].
class ExpenseBills extends ConsumerWidget {
  const ExpenseBills({super.key, required this.expense, required this.canChange, this.shareText});
  final SiteExpense expense;
  final bool canChange;
  final String? shareText;

  void _refresh(WidgetRef ref) {
    ref.invalidate(expenseBillsProvider(expense.id));
    ref.invalidate(expenseBillCountsProvider(expense.projectId));
  }

  Future<void> _attach(BuildContext context, WidgetRef ref) async {
    final picked = await pickBills(context);
    if (picked.isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    for (final f in picked) {
      await db.expenseDao.attach(expense.id, f.path);
    }
    _refresh(ref);
  }

  Future<void> _remove(WidgetRef ref, List<ExpenseAttachment> bills, String path) async {
    final db = ref.read(appDatabaseProvider);
    for (final b in bills.where((b) => b.filePath == path)) {
      await db.expenseDao.removeAttachment(b.id);
    }
    _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(expenseBillsProvider(expense.id)).valueOrNull ?? const <ExpenseAttachment>[];
    final here = [for (final b in all) if (File(b.filePath).existsSync()) b];
    final photos = [for (final b in here) if (!b.mimeType.endsWith('pdf')) b.filePath];
    final pdfs = [for (final b in here) if (b.mimeType.endsWith('pdf')) b];
    final elsewhere = all.length - here.length;
    if (all.isEmpty && !canChange) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text(tr('Bills'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      if (photos.isNotEmpty)
        PhotoStrip(
          paths: photos,
          shareText: shareText,
          size: 72,
          onDelete: canChange ? (path) => _remove(ref, all, path) : null,
        ),
      for (final pdf in pdfs)
        ListTile(
          key: Key('bill-pdf-${pdf.id}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(billFileName(pdf.filePath), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(tr('Tap to open or share')),
          onTap: () => shareBillFile(pdf.filePath, text: shareText),
          trailing: canChange
              ? IconButton(
                  tooltip: tr('Remove bill'),
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    if (await confirmBillRemove(context)) await _remove(ref, all, pdf.filePath);
                  },
                )
              : null,
        ),
      if (elsewhere > 0)
        Text(
          elsewhere == 1
              ? tr('1 bill is on the phone that added it.')
              : trf('{n} bills are on the phone that added them.', {'n': '$elsewhere'}),
          style: theme.textTheme.bodySmall,
        ),
      if (canChange)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('expense-attach-bill'),
            onPressed: () => _attach(context, ref),
            icon: const Icon(Icons.attach_file),
            label: Text(tr('Attach bill photo or PDF')),
          ),
        ),
    ]);
  }
}

Future<bool> confirmBillRemove(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Remove this bill?')),
      content: Text(tr('The file is deleted from this phone. The expense stays.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
      ],
    ),
  );
  return ok == true;
}

/// "bill_1731000000000_invoice.pdf" → "invoice.pdf".
String billFileName(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final m = RegExp(r'^bill_\d+_(?:\d+_)?(.+)$').firstMatch(name);
  return m?.group(1) ?? name;
}
