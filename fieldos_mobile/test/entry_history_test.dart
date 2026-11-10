/// Change history pulled from the server: what changed, cancels and
/// deletes, and how values are shown.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/entry_history.dart';
import 'package:fieldos_mobile/features/money/entry_history_screen.dart' show showValue;
import 'package:fieldos_mobile/sync/sync_engine.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

late AppDatabase db;

Map<String, dynamic> _expense({num amount = 2000, bool voided = false, String? editedAt}) => {
      'id': '00000000-0000-0000-0000-00000000ed01',
      'project_id': 'site-1',
      'category': 'Petty cash',
      'amount': amount,
      'incurred_on': '2026-11-03',
      'paid_to': 'Hardware shop',
      'recorded_by': 'u-sup',
      'voided': voided,
      'void_reason': voided ? 'Typed twice' : null,
      'edited_at': editedAt,
      'created_at': '2026-11-03T12:00:00+00:00',
    };

Future<void> _pull(String id, String op, Map<String, dynamic> old, Map<String, dynamic>? now, String at) =>
    db.entryHistoryDao.upsertFromRemote(entryHistoryFromSupabaseJson({
      'id': id,
      'project_id': 'site-1',
      'table_name': 'site_expenses',
      'row_id': old['id'],
      'op': op,
      'old_row': old,
      'new_row': now,
      'changed_by': 'u-pm',
      'changed_at': at,
    }));

void main() {
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('a correction, a cancel and a delete, newest first', () async {
    await _pull('h1', 'update', _expense(), _expense(amount: 1500, editedAt: '2026-11-04T09:00:00+00:00'),
        '2026-11-04T09:00:00+00:00');
    await _pull('h2', 'update', _expense(amount: 1500), _expense(amount: 1500, voided: true), '2026-11-05T09:00:00+00:00');
    await _pull('h3', 'delete', _expense(amount: 1500, voided: true), null, '2026-11-06T09:00:00+00:00');
    // Pulling the same row again doesn't repeat it.
    await _pull('h1', 'update', _expense(), _expense(amount: 1500), '2026-11-04T09:00:00+00:00');

    final items = await loadSiteHistory(db, 'site-1');
    expect(items.map((h) => h.row.id), ['h3', 'h2', 'h1']);

    final fix = items[2];
    expect(fix.kind, 'Expense');
    expect(fix.summary, 'Petty cash · Hardware shop');
    expect(fix.changes.map((c) => (c.field, c.before, c.after)), [('amount', 2000, 1500)]); // edit stamp left out
    expect(fix.cancelled, isFalse);

    final cancel = items[1];
    expect(cancel.cancelled, isTrue);
    expect(cancel.changes.map((c) => c.field), ['void_reason', 'voided']);

    final gone = items[0];
    expect(gone.deleted, isTrue);
    expect(gone.changes, isEmpty);
    expect(gone.amountBefore, 1500);

    expect(await db.entryHistoryDao.changedRows(['00000000-0000-0000-0000-00000000ed01', 'other']),
        {'00000000-0000-0000-0000-00000000ed01'});
    expect((await db.entryHistoryDao.forRow('00000000-0000-0000-0000-00000000ed01')).map((h) => h.id), ['h1', 'h2', 'h3']);
    expect(await db.entryHistoryDao.changedRows(const []), isEmpty);
  });

  test('who changed it maps to this phone\'s own id like every other user column', () {
    expect(SyncEngine.userIdColumns, contains('changed_by'));
  });

  test('values read the way the app shows them', () {
    expect(showValue('amount', 1500), '₹1,500');
    expect(showValue('quantity', 2.5), '2.5');
    expect(showValue('note', null), '(empty)');
    expect(showValue('voided', true), 'Yes');
    expect(showValue('incurred_on', '2026-11-03'), isNot('2026-11-03'));
  });
}
