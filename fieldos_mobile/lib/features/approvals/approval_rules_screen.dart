/// Settings > Approval rules (owner only): for purchase requests, expenses
/// and purchase orders, the amount above which a project manager must
/// approve, and the amount above which the owner must too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain_ui.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class ApprovalRulesScreen extends ConsumerStatefulWidget {
  const ApprovalRulesScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<ApprovalRulesScreen> createState() => _ApprovalRulesScreenState();
}

class _ApprovalRulesScreenState extends ConsumerState<ApprovalRulesScreen> {
  final _fields = {
    for (final k in ApprovalKind.all)
      for (final l in ApprovalLevel.order) '$k|$l': TextEditingController(),
  };
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _value(String key) {
    final t = _fields[key]!.text.trim().replaceAll(',', '');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _save() async {
    for (final k in ApprovalKind.all) {
      for (final l in ApprovalLevel.order) {
        final t = _fields['$k|$l']!.text.trim();
        if (t.isNotEmpty && (_value('$k|$l') == null || _value('$k|$l')! < 0)) {
          showSnack(context, tr('Enter amounts in rupees, or leave blank.'), error: true);
          return;
        }
      }
      final pm = _value('$k|${ApprovalLevel.projectManager}');
      final owner = _value('$k|${ApprovalLevel.owner}');
      if (pm != null && owner != null && owner < pm) {
        showSnack(context, tr("The owner's amount should not be below the project manager's."), error: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final dao = ref.read(appDatabaseProvider).approvalChainDao;
      final by = ref.read(sessionProvider).user?.id ?? '';
      for (final k in ApprovalKind.all) {
        for (final l in ApprovalLevel.order) {
          await dao.setRule(widget.companyId, kind: k, role: l, above: _value('$k|$l'), by: by);
        }
      }
      ref.invalidate(approvalRulesProvider(widget.companyId));
      if (mounted) {
        showSnack(context, tr('Approval rules saved'));
        Navigator.pop(context);
      }
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(approvalRulesProvider(widget.companyId));
    final list = rules.value;
    if (!_loaded && list != null) {
      _loaded = true;
      for (final r in list) {
        _fields['${r.kind}|${r.role}']?.text = fmtQty(r.aboveAmount);
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Approval rules'))),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('Above these amounts, a project manager approves first, then the owner. '
                      'Leave a box blank for no approval. Rules cover what is recorded from now on.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                for (final k in ApprovalKind.all) ...[
                  const SizedBox(height: 20),
                  Text(ApprovalKind.label(k), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: Key('rule-$k-pm'),
                    controller: _fields['$k|${ApprovalLevel.projectManager}'],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Project manager approves above (₹)')),
                  ),
                  TextField(
                    key: Key('rule-$k-owner'),
                    controller: _fields['$k|${ApprovalLevel.owner}'],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Owner also approves above (₹)')),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: _saving ? null : _save, child: Text(tr('Save'))),
              ],
            ),
    );
  }
}
