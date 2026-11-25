/// Pure-Dart tests for SyncOutboxDao's own mechanics -- no network needed,
/// these run instantly. The real network-touching behavior (does a pushed
/// change actually reach Postgres, does pull actually merge) is covered
/// separately in test/sync_engine_test.dart against the real local
/// Supabase instance.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  group('SyncOutboxDao', () {
    test('enqueue then pending returns it, oldest first', () async {
      final db = AppDatabase.memory();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p1',
        operation: 'insert',
        payloadJson: '{"id":"p1"}',
      );
      await db.syncOutboxDao.enqueue(
        targetTable: 'tasks',
        recordId: 't1',
        operation: 'insert',
        payloadJson: '{"id":"t1"}',
      );

      final pending = await db.syncOutboxDao.pending();
      expect(pending.length, 2);
      expect(pending.first.recordId, 'p1'); // enqueued first -> comes first
      expect(pending.last.recordId, 't1');
      expect(pending.every((e) => e.retryCount == 0), isTrue);
    });

    test('dirtyKeys lists every unsent record, parked ones too, and drops a record once it is sent', () async {
      final db = AppDatabase.memory();
      final big = '{"id":"x","note":"${'n' * 20000}"}';
      await db.syncOutboxDao.enqueue(targetTable: 'tasks', recordId: 't1', operation: 'insert', payloadJson: big);
      await db.syncOutboxDao.enqueue(targetTable: 'tasks', recordId: 't1', operation: 'update', payloadJson: big);
      await db.syncOutboxDao.enqueue(targetTable: 'issues', recordId: 'i1', operation: 'insert', payloadJson: big);
      await db.syncOutboxDao.enqueue(targetTable: 'tasks', recordId: 't2', operation: 'insert', payloadJson: big);
      final pending = await db.syncOutboxDao.pending();
      await db.syncOutboxDao.park(pending.firstWhere((e) => e.recordId == 'i1').id, 'refused');
      expect(await db.syncOutboxDao.dirtyKeys(), {'tasks:t1', 'issues:i1', 'tasks:t2'});

      await db.syncOutboxDao.markSynced(pending.firstWhere((e) => e.recordId == 't2').id);
      expect(await db.syncOutboxDao.dirtyKeys(), {'tasks:t1', 'issues:i1'}, reason: 'sent: no longer dirty');
      expect(SyncOutboxDao.key('tasks', 't1'), 'tasks:t1');
    });

    test('a write queued after the phone clock went back still goes after the one before it', () async {
      final db = AppDatabase.memory();
      // Queued while the phone's clock was a day fast...
      await db.syncOutboxDao.enqueue(
          targetTable: 'tasks', recordId: 't1', operation: 'insert', payloadJson: '{"id":"t1"}');
      await db.customStatement("UPDATE sync_outbox SET created_at = created_at + 86400");
      // ...then the network corrected it, and the task was edited.
      await db.syncOutboxDao.enqueue(
          targetTable: 'tasks', recordId: 't1', operation: 'update', payloadJson: '{"id":"t1","progress":50}');

      final pending = await db.syncOutboxDao.pending();
      expect(pending.map((e) => e.operation), ['insert', 'update'],
          reason: 'the update would be refused if it reached the server before the insert');
      await db.close();
    });

    test('markSynced removes the entry', () async {
      final db = AppDatabase.memory();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p1',
        operation: 'insert',
        payloadJson: '{"id":"p1"}',
      );
      final entry = (await db.syncOutboxDao.pending()).single;

      await db.syncOutboxDao.markSynced(entry.id);

      expect(await db.syncOutboxDao.pending(), isEmpty);
    });

    test('recordFailure increments retryCount and stores the error, entry stays queued', () async {
      final db = AppDatabase.memory();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p1',
        operation: 'insert',
        payloadJson: '{"id":"p1"}',
      );
      final entry = (await db.syncOutboxDao.pending()).single;

      await db.syncOutboxDao.recordFailure(entry.id, 'network unreachable');
      final afterOneFailure = (await db.syncOutboxDao.pending()).single;
      expect(afterOneFailure.retryCount, 1);
      expect(afterOneFailure.lastError, 'network unreachable');

      await db.syncOutboxDao.recordFailure(entry.id, 'network unreachable again');
      final afterTwoFailures = (await db.syncOutboxDao.pending()).single;
      expect(afterTwoFailures.retryCount, 2);
    });

    test('an entry parked after exceeding the retry limit stops appearing in pending()', () async {
      final db = AppDatabase.memory();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p1',
        operation: 'insert',
        payloadJson: '{"id":"p1"}',
      );
      final entry = (await db.syncOutboxDao.pending()).single;

      for (var i = 0; i < syncOutboxMaxRetries; i++) {
        await db.syncOutboxDao.recordFailure(entry.id, 'still failing');
      }

      // Exhausted its retries -- must fall out of pending() (so a broken
      // entry can't spin forever) but must NOT be silently deleted --
      // parked() is where a future "why didn't this sync" UI would look.
      expect(await db.syncOutboxDao.pending(), isEmpty);
      final parked = await db.syncOutboxDao.parked();
      expect(parked.length, 1);
      expect(parked.first.retryCount, syncOutboxMaxRetries);
    });

    test('pendingCount reflects only entries still worth retrying', () async {
      final db = AppDatabase.memory();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p1',
        operation: 'insert',
        payloadJson: '{}',
      );
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: 'p2',
        operation: 'insert',
        payloadJson: '{}',
      );
      expect(await db.syncOutboxDao.pendingCount(), 2);

      final first = (await db.syncOutboxDao.pending()).first;
      await db.syncOutboxDao.markSynced(first.id);
      expect(await db.syncOutboxDao.pendingCount(), 1);
    });
  });
}
