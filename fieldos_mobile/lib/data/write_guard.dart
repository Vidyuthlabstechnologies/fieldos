/// Read-only mode for the whole local database.
///
/// A phone on a company plan that has not reached the server for over 7
/// days (lib/services/company_plan.dart) may still open every screen, but
/// may not change anything until it is back online. Rather than every
/// screen checking, every write to the database goes through [WriteGuard]
/// (a drift [QueryInterceptor] installed by AppDatabase) and is refused
/// with [ReadOnlyModeException] while [WriteGuard.readOnly] is on.
///
/// Still allowed in read-only mode, so the phone can recover:
///  - the app's settings table (sync cursor, the plan answer, the cloud
///    session, the language);
///  - anything run inside [WriteGuard.serverSync]: the sync engine's pulls
///    from the server, its outbox bookkeeping and live updates. These are
///    the server's data, not the person's changes.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fieldos_mobile/l10n/language.dart';

/// A write refused because the phone is in read-only mode.
class ReadOnlyModeException implements Exception {
  const ReadOnlyModeException([this.reason = ReadOnlyReason.offlineTooLong]);

  final ReadOnlyReason reason;

  String get message => readOnlyMessage(reason);

  @override
  String toString() => message;
}

enum ReadOnlyReason {
  /// No good answer from the server for over 7 days (or the phone's clock
  /// moved back past the last answer).
  offlineTooLong,

  /// The remembered company plan's last day has passed, and the phone is
  /// offline so it can't check for a renewal.
  planEnded,
}

/// The banner's words, and what a refused change says.
String readOnlyMessage(ReadOnlyReason reason) => switch (reason) {
      ReadOnlyReason.offlineTooLong =>
        tr('Offline for over 7 days. Connect to the internet to keep making changes. You can still view everything.'),
      ReadOnlyReason.planEnded =>
        tr('Your company plan has ended. Connect to the internet to check it. You can still view everything.'),
    };

class WriteGuard extends QueryInterceptor {
  WriteGuard();

  /// Tables a read-only phone still writes: its own settings.
  static const allowedTables = {'app_settings'};

  static final Object _serverSyncKey = Object();

  /// Runs [body] as server bookkeeping: its writes go through in read-only
  /// mode. Zones follow every await inside [body], including drift
  /// transactions it opens.
  static Future<T> serverSync<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_serverSyncKey: true});

  static bool get _inServerSync => Zone.current[_serverSyncKey] == true;

  /// On while the phone is read-only; the app's banner listens to it.
  final ValueNotifier<ReadOnlyReason?> state = ValueNotifier(null);

  bool get readOnly => state.value != null;

  /// Turns read-only mode on (with why) or off (null).
  set reason(ReadOnlyReason? reason) {
    changes++;
    state.value = reason;
  }

  /// Counts [reason] changes, so a late reset can tell it is stale.
  int changes = 0;

  static final _insert =
      RegExp(r'^\s*(?:insert|replace)(?:\s+or\s+\w+)?\s+into\s+["`\[]?(\w+)', caseSensitive: false);
  static final _update = RegExp(r'^\s*update(?:\s+or\s+\w+)?\s+["`\[]?(\w+)', caseSensitive: false);
  static final _delete = RegExp(r'^\s*delete\s+from\s+["`\[]?(\w+)', caseSensitive: false);
  static final _with = RegExp(r'^\s*with\b', caseSensitive: false);
  static final _dmlWord = RegExp(r'\b(insert|update|delete|replace)\b', caseSensitive: false);

  /// Whether [sql] changes data in a table other than [allowedTables].
  static bool changesData(String sql) {
    for (final rx in [_insert, _update, _delete]) {
      final m = rx.firstMatch(sql);
      if (m != null) return !allowedTables.contains(m.group(1)!.toLowerCase());
    }
    // A CTE that writes: refuse unless it only touches allowed tables.
    if (_with.hasMatch(sql) && _dmlWord.hasMatch(sql)) {
      return !allowedTables.any((t) => sql.toLowerCase().contains(t));
    }
    return false;
  }

  void _check(String sql) {
    final reason = state.value;
    if (reason == null || _inServerSync) return;
    if (changesData(sql)) throw ReadOnlyModeException(reason);
  }

  @override
  Future<int> runInsert(QueryExecutor executor, String statement, List<Object?> args) async {
    _check(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(QueryExecutor executor, String statement, List<Object?> args) async {
    _check(statement);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(QueryExecutor executor, String statement, List<Object?> args) async {
    _check(statement);
    return executor.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(QueryExecutor executor, String statement, List<Object?> args) async {
    _check(statement);
    return executor.runCustom(statement, args);
  }

  /// insertReturning and friends come through here.
  @override
  Future<List<Map<String, Object?>>> runSelect(QueryExecutor executor, String statement, List<Object?> args) async {
    _check(statement);
    return executor.runSelect(statement, args);
  }

  @override
  Future<void> runBatched(QueryExecutor executor, BatchedStatements statements) async {
    for (final s in statements.statements) {
      _check(s);
    }
    return executor.runBatched(statements);
  }
}
