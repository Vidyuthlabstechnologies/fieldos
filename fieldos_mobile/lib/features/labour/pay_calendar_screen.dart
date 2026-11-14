/// The company's rest day and public holidays, for the Malaysia app's
/// wage sheet: work on them is paid at the Employment Act's rates
/// (see [PayCalendar]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class PayCalendarScreen extends ConsumerStatefulWidget {
  const PayCalendarScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<PayCalendarScreen> createState() => _PayCalendarScreenState();
}

class _PayCalendarScreenState extends ConsumerState<PayCalendarScreen> {
  PayCalendar? _cal;

  @override
  void initState() {
    super.initState();
    loadPayCalendar(ref.read(appDatabaseProvider), widget.companyId).then((c) {
      if (mounted) setState(() => _cal = c);
    });
  }

  Future<void> _save(PayCalendar c) async {
    final db = ref.read(appDatabaseProvider);
    await db.settingsDao.set(restDayKey(widget.companyId), '${c.restDays.first}');
    final days = c.holidays.toList()..sort();
    await db.settingsDao.set(publicHolidaysKey(widget.companyId), days.map(markDay).join(','));
    setState(() => _cal = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _cal;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Rest day and public holidays'))),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              Text(
                tr('Work on the rest day pays 1 day for up to half the normal hours and 2 days for more. Work on a '
                    'public holiday pays 2 days on top of the holiday pay. A day you mark by hand keeps your mark.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: const Key('rest-day'),
                initialValue: c.restDays.first,
                decoration: InputDecoration(labelText: tr('Rest day')),
                items: [
                  DropdownMenuItem(value: DateTime.sunday, child: Text(tr('Sunday'))),
                  DropdownMenuItem(value: DateTime.friday, child: Text(tr('Friday (Kelantan, Terengganu, Kedah)'))),
                  DropdownMenuItem(value: DateTime.saturday, child: Text(tr('Saturday'))),
                ],
                onChanged: (v) => v == null ? null : _save(PayCalendar(restDays: {v}, holidays: c.holidays)),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Text(tr('Public holidays'), style: theme.textTheme.titleSmall)),
                TextButton.icon(
                  key: const Key('add-holiday'),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add')),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await pickDate(context, initial: now, first: DateTime(now.year - 1), last: DateTime(now.year + 2));
                    if (d != null) _save(PayCalendar(restDays: c.restDays, holidays: {...c.holidays, DateTime(d.year, d.month, d.day)}));
                  },
                ),
              ]),
              Text(tr('Add the federal and state holidays your company gives, from the gazette for your state.'),
                  style: theme.textTheme.bodySmall),
              for (final d in c.holidays.toList()..sort())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(fmtDate(d)),
                  trailing: IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(PayCalendar(restDays: c.restDays, holidays: {...c.holidays}..remove(d))),
                  ),
                ),
            ]),
    );
  }
}
