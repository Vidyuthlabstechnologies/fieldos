/// The company's overtime pay, for the wage sheet: the rate for an
/// overtime hour where the company may choose it, and in the US app the
/// state, which decides whether California's daily overtime applies
/// (see [OvertimePolicy]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class OvertimeSettingsScreen extends ConsumerStatefulWidget {
  const OvertimeSettingsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<OvertimeSettingsScreen> createState() => _OvertimeSettingsScreenState();
}

class _OvertimeSettingsScreenState extends ConsumerState<OvertimeSettingsScreen> {
  OvertimePolicy? _policy;
  final _rate = TextEditingController();
  String? _rateError;

  @override
  void initState() {
    super.initState();
    loadOvertimePolicy(ref.read(appDatabaseProvider), widget.companyId).then((p) {
      if (!mounted) return;
      _rate.text = fmtQty(p.multiplier);
      setState(() => _policy = p);
    });
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _saveRate(String typed) async {
    final m = double.tryParse(westernDigits(typed.trim()).replaceAll(',', '.'));
    if (m == null || !validOvertimeMultiplier(m)) {
      setState(() => _rateError = tr('Enter a number from 1 to 5'));
      return;
    }
    setState(() => _rateError = null);
    await saveOvertimeMultiplier(ref.read(appDatabaseProvider), widget.companyId, m);
  }

  Future<void> _saveState(String? code) async {
    await saveUsState(ref.read(appDatabaseProvider), widget.companyId, code);
    final p = await loadOvertimePolicy(ref.read(appDatabaseProvider), widget.companyId);
    if (mounted) setState(() => _policy = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _policy;
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Overtime pay'))),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              if (overtimeRateEditable) ...[
                TextField(
                  key: const Key('overtime-rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Overtime rate (×)'), suffixText: '×', errorText: _rateError),
                  onChanged: _saveRate,
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (!market.payHourly)
                      trf('Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.',
                          {'h': fmtQty(normalDayHours)}),
                    trf('Overtime hours are paid at the hourly rate times this number. Default: {rate}.',
                        {'rate': fmtQty(market.overtime.multiplier)}),
                  ].join(' '),
                  style: small,
                ),
              ],
              if (currentMarket == Market.us) ...[
                DropdownButtonFormField<String>(
                  key: const Key('us-state'),
                  initialValue: p.usState == 'CA' ? 'CA' : '',
                  decoration: InputDecoration(labelText: tr('State')),
                  items: [
                    DropdownMenuItem(value: 'CA', child: Text(tr('California'))),
                    DropdownMenuItem(value: '', child: Text(tr('Another state'))),
                  ],
                  onChanged: _saveState,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('California pays 1.5× past 8 hours in a day and 2× past 12. The 7th day worked in a row in a '
                      'week pays 1.5× for the first 8 hours and 2× after. Other states pay 1.5× past 40 hours a week.'),
                  style: small,
                ),
              ],
            ]),
    );
  }
}
