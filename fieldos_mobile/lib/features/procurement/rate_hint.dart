/// A one-line check under a quote or bill: is this rate above what the
/// company usually pays for the same material? Cement at ₹420 a bag when
/// the last six deliveries averaged ₹390 is ₹1,200 extra on 40 bags, and
/// the owner should hear about it before the order, not after.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', ''));

/// The words for a check, kept apart so they can be tested.
String rateCheckLine(RateCheck c, {required String? unit, double? qty}) {
  final per = (unit ?? '').trim().isEmpty ? tr('unit') : unit!.trim();
  final usual = rupees(c.usual, paise: true);
  if (c.high) {
    final pct = c.diffPct.round();
    final extra = qty == null ? null : c.extraOn(qty);
    return extra == null || extra < 1
        ? trf('{pct}% above your usual {usual} per {unit}', {'pct': pct, 'usual': usual, 'unit': per})
        : trf('{pct}% above your usual {usual} per {unit}: {extra} extra on this order',
            {'pct': pct, 'usual': usual, 'unit': per, 'extra': rupees(extra)});
  }
  if (c.low) {
    return trf('{pct}% below your usual {usual} per {unit}. A good price.', {'pct': (-c.diffPct).round(), 'usual': usual, 'unit': per});
  }
  return trf('In line with your usual {usual} per {unit}', {'usual': usual, 'unit': per});
}

class RateHint extends ConsumerWidget {
  const RateHint({
    super.key,
    required this.companyId,
    required this.material,
    required this.unit,
    required this.qty,
    required this.amount,
    this.fixedMaterial,
    this.fixedUnit,
    this.fixedQty,
  });

  final String companyId;

  /// Live fields; any may be null when the dialog fixes that value.
  final TextEditingController? material;
  final TextEditingController? unit;
  final TextEditingController? qty;
  final TextEditingController amount;
  final String? fixedMaterial;
  final String? fixedUnit;
  final double? fixedQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(companyReceiptsProvider(companyId)).value;
    if (history == null) return const SizedBox.shrink();
    final suppliers = ref.watch(suppliersProvider(companyId)).value ?? const <Supplier>[];
    return ListenableBuilder(
      listenable: Listenable.merge([material, unit, qty, amount]),
      builder: (context, _) {
        final u = unit?.text ?? fixedUnit;
        final q = qty == null ? fixedQty : _num(qty!.text);
        final check = checkRate(
          material: material?.text ?? fixedMaterial ?? '',
          unit: u,
          qty: q,
          amount: _num(amount.text),
          history: history,
        );
        if (check == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final tone = check.high ? PillTone.danger : PillTone.ok;
        final color = toneColor(context, tone);
        final best = check.best;
        final bestName = best == null ? null : suppliers.where((s) => s.id == best.supplierId).firstOrNull?.name;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(check.high ? Icons.trending_up : Icons.verified_outlined, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rateCheckLine(check, unit: u, qty: q),
                    key: const Key('rate-hint'), style: theme.textTheme.bodySmall?.copyWith(color: color)),
                if (check.high && best != null && best.rate < check.rate)
                  Text(
                    bestName == null
                        ? trf('Lowest recent: {rate} on {date}', {'rate': rupees(best.rate, paise: true), 'date': fmtDate(best.on, short: true)})
                        : trf('Lowest recent: {rate} from {supplier} on {date}', {
                            'rate': rupees(best.rate, paise: true),
                            'supplier': bestName,
                            'date': fmtDate(best.on, short: true),
                          }),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
