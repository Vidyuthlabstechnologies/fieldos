/// Small pieces the commercial screens share.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';

double? parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim());

class NumField extends StatelessWidget {
  const NumField({super.key, required this.controller, required this.label, this.suffix, this.helper, this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? helper;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
        onChanged: onChanged,
      );
}

/// A label and a value on one line.
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.strong = false, this.color});
  final String label;
  final String value;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (strong ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(width: 12),
        Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
      ]),
    );
  }
}

String qtyUnit(double q, String? unit) => '${fmtQty(q)} ${unit ?? ''}'.trim();

String originLabel(String origin) => switch (origin) {
      'claim_over_order' => tr('Claim beyond the order'),
      'client_instruction' => tr('Client instruction'),
      'design_change' => tr('Design change'),
      'site_condition' => tr('Site condition'),
      _ => tr('Other'),
    };

const variationOrigins = ['client_instruction', 'design_change', 'site_condition', 'claim_over_order', 'other'];

(String, PillTone) variationPill(VariationState s) => switch (s) {
      VariationState.pending => (tr('Pending'), PillTone.warn),
      VariationState.approved => (tr('Approved'), PillTone.ok),
      VariationState.rejected => (tr('Rejected'), PillTone.danger),
    };

(String, PillTone) claimPill(ClaimPosition c) {
  if (c.settled) {
    if (c.rejected > 0 && c.accepted > 0) {
      return (trf('{a} accepted, {r} rejected', {'a': fmtQty(c.accepted), 'r': fmtQty(c.rejected)}), PillTone.warn);
    }
    if (c.rejected > 0) return (tr('Rejected'), PillTone.danger);
    return (tr('Certified'), PillTone.ok);
  }
  if (c.eligibleAfterApproval) return (trf('{q} approved, to certify', {'q': fmtQty(c.open)}), PillTone.warn);
  if (c.heldForVariation) return (trf('{q} waiting for a variation decision', {'q': fmtQty(c.open)}), PillTone.warn);
  if (c.untouched) return (tr('To certify'), PillTone.warn);
  return (trf('{q} still to decide', {'q': fmtQty(c.open)}), PillTone.warn);
}

Future<String?> askText(BuildContext context, {required String title, String? label, String? initial}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
      ],
    ),
  );
  return ok == true ? c.text.trim() : null;
}

/// The budget line picker: a dropdown over the site's cost codes.
class CostCodePicker extends StatelessWidget {
  const CostCodePicker({super.key, required this.codes, required this.value, required this.onChanged});
  final List<CostCode> codes;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Budget line')),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('Not on a budget line'))),
          for (final c in codes) DropdownMenuItem(value: c.id, child: Text('${c.code} ${c.name}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}
