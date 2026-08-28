# LabourAttendance Sync Design & Implementation

## Executive Summary

**Decision:** LabourAttendance SHOULD be synced, but requires aggregation. Mobile's punch-in/punch-out event log must be transformed into Postgres's daily summary format before syncing.

**Implementation Status:** Documented design ready for implementation.

## Schema Analysis

### Mobile: LabourAttendance (Event Log)
Located in: `fieldos_mobile/lib/data/tables.dart`

```dart
class LabourAttendance extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get workerName => text()();
  TextColumn get workerId => text().nullable()();  // Optional FK to Workers
  TextColumn get recordedBy => text()();
  DateTimeColumn get punchIn => dateTime()();
  DateTimeColumn get punchOut => dateTime().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  BoolColumn get withinGeofence => boolean().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
```

**Characteristics:**
- Event-based: Multiple rows per worker per day (punch-in at 8am, punch-out at 5pm)
- GPS-aware: Captures location and geofence validation at each punch
- Worker can be identified by name OR ID (workerId nullable for backward compatibility)
- Used for: Time tracking, geofence compliance, labor productivity analysis

### Postgres: attendance (Daily Summary)
Located in: `supabase/migrations/20260823000000_initial_schema.sql`

```sql
create table attendance (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  attendance_date date not null,
  status text not null check (status in ('present', 'absent', 'half_day')),
  notes text,
  created_at timestamptz not null default now(),
  unique (worker_id, attendance_date)
);
```

**Characteristics:**
- Summary-based: ONE row per worker per day
- Status-driven: 'present', 'absent', 'half_day'
- REQUIRES worker_id (NOT NULL, FK to workers table)
- Used for: Payroll, daily headcount reports, attendance tracking

## Key Differences

| Aspect | Mobile (LabourAttendance) | Postgres (attendance) |
|--------|---------------------------|----------------------|
| **Granularity** | Multiple events per day | One summary per day |
| **Worker ID** | Optional (can use workerName only) | Required (FK constraint) |
| **Data Type** | Event log (punch times, GPS) | Status summary |
| **Purpose** | Real-time tracking, geofence | Payroll, reporting |
| **Unique Key** | Individual event ID | (worker_id, attendance_date) |

## Aggregation Strategy

### Aggregation Function Design

```dart
/// Aggregates punch-in/punch-out events for a worker on a specific date
/// into a single daily attendance status.
AttendanceStatus aggregateDailyAttendance({
  required List<LabourAttendanceData> punches,
  required String workerId,
  required DateTime date,
}) {
  // Filter punches for this worker on this date
  final dayPunches = punches.where((p) => 
    p.workerId == workerId && 
    isSameDate(p.punchIn, date)
  ).toList();

  if (dayPunches.isEmpty) {
    return AttendanceStatus(status: 'absent', notes: null);
  }

  // Calculate total hours worked
  double totalHours = 0;
  final notes = <String>[];
  
  for (final punch in dayPunches) {
    if (punch.punchOut != null) {
      final duration = punch.punchOut!.difference(punch.punchIn);
      totalHours += duration.inMinutes / 60.0;
      
      // Track geofence violations
      if (punch.withinGeofence == false) {
        notes.add('Punch at ${punch.punchIn.hour}:${punch.punchIn.minute} outside geofence');
      }
    } else {
      // Punch-in without punch-out (shift ongoing or forgotten)
      notes.add('Punch-in at ${punch.punchIn.hour}:${punch.punchIn.minute} (no punch-out)');
    }
  }

  // Determine status based on hours worked
  String status;
  if (totalHours >= 8) {
    status = 'present';
  } else if (totalHours >= 4) {
    status = 'half_day';
  } else {
    status = 'absent';
    notes.add('Insufficient hours: ${totalHours.toStringAsFixed(1)}h');
  }

  return AttendanceStatus(
    status: status,
    notes: notes.isEmpty ? null : notes.join('; '),
  );
}

class AttendanceStatus {
  final String status;
  final String? notes;
  AttendanceStatus({required this.status, required this.notes});
}

bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
```

### Handling Edge Cases

1. **Worker without workerId (name-only entries)**
   - Solution: Match by workerName to Workers table first
   - If no match found: Skip syncing that attendance record
   - Log: "Attendance for '{workerName}' skipped - no Workers directory entry"

2. **Multiple workers with same name**
   - Solution: Require workerId for sync
   - Only sync attendance records that have workerId populated

3. **Punch-in without punch-out (shift ongoing)**
   - Solution: 
     - If < 4 hours: status = 'absent', note = "Incomplete shift"
     - If >= 4 hours: status = 'half_day', note = "Shift ongoing (no punch-out)"
     - If >= 8 hours: status = 'present', note = "Shift ongoing (no punch-out)"

4. **Same-day corrections (worker punches multiple times)**
   - Solution: Sum all completed shift durations
   - Note: "Multiple shifts: {count} punches"

5. **Geofence violations**
   - Solution: Still count hours, but add note
   - Note: "Punch at {time} outside geofence"

## Implementation Plan

### Phase 1: Aggregation Function (15-20 minutes)

Create `lib/sync/attendance_aggregator.dart`:

```dart
import 'package:fieldos_mobile/data/app_database.dart';

class AttendanceAggregator {
  /// Groups punch events by (workerId, date) and computes daily status.
  /// Returns a map: key = 'workerId:YYYY-MM-DD', value = AttendanceStatus
  static Map<String, DailyAttendance> aggregateForSync(
    List<LabourAttendanceData> allPunches,
  ) {
    final result = <String, DailyAttendance>{};
    
    // Group by workerId (skip if null) and date
    final grouped = <String, List<LabourAttendanceData>>{};
    for (final punch in allPunches) {
      if (punch.workerId == null) continue;  // Skip name-only entries
      
      final dateKey = '${punch.workerId}:${_dateString(punch.punchIn)}';
      grouped.putIfAbsent(dateKey, () => []).add(punch);
    }
    
    // Aggregate each group
    for (final entry in grouped.entries) {
      final parts = entry.key.split(':');
      final workerId = parts[0];
      final date = DateTime.parse(parts[1]);
      final punches = entry.value;
      
      final agg = _aggregatePunches(punches);
      result[entry.key] = DailyAttendance(
        workerId: workerId,
        date: date,
        status: agg.status,
        notes: agg.notes,
      );
    }
    
    return result;
  }
  
  static AttendanceStatus _aggregatePunches(List<LabourAttendanceData> punches) {
    // Implementation from above
    // ... (hours calculation, status determination)
  }
  
  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class DailyAttendance {
  final String workerId;
  final DateTime date;
  final String status;
  final String? notes;
  
  DailyAttendance({
    required this.workerId,
    required this.date,
    required this.status,
    required this.notes,
  });
}
```

### Phase 2: Sync Mapper (10 minutes)

Add to `lib/sync/sync_mappers.dart`:

```dart
/// Aggregates mobile's punch events into Postgres's daily summary format.
/// Called during push, not pull -- the desktop creates daily summaries
/// directly, mobile aggregates its event log before pushing.
Map<String, dynamic> dailyAttendanceToSupabaseJson(DailyAttendance d) => {
      'worker_id': d.workerId,
      'attendance_date': _dateOnly(d.date),
      'status': d.status,
      'notes': d.notes,
    };

// Pull direction: a remotely-created daily summary can't be disaggregated
// back into punch events, so we don't write it to LabourAttendance at all.
// The mobile app's LabourAttendance table stays a local-only event log.
// If cross-device attendance visibility is needed later, add a separate
// AttendanceSummary table on mobile that mirrors the remote schema 1:1.
```

### Phase 3: SyncEngine Integration (20 minutes)

Update `lib/sync/sync_engine.dart`:

1. Add attendance push logic to `pushPending()`:

```dart
// Inside pushPending(), add special case for attendance aggregation
if (entry.targetTable == 'attendance') {
  // This outbox entry is a batch marker, not a single row --
  // payload contains a date range, not one attendance record.
  final range = jsonDecode(entry.payload) as Map<String, dynamic>;
  final startDate = DateTime.parse(range['start_date'] as String);
  final endDate = DateTime.parse(range['end_date'] as String);
  
  // Fetch all punches in date range for this project
  final punches = await db.attendanceDao.punchesInRange(
    entry.recordId,  // projectId
    startDate,
    endDate,
  );
  
  // Aggregate into daily summaries
  final dailySummaries = AttendanceAggregator.aggregateForSync(punches);
  
  // Upsert each summary to Postgres
  for (final summary in dailySummaries.values) {
    await client.from('attendance').upsert(
      dailyAttendanceToSupabaseJson(summary),
      onConflict: 'worker_id,attendance_date',
    );
  }
  
  // Mark outbox entry as succeeded
  await db.syncOutboxDao.markSucceeded(entry.id);
  succeeded++;
  continue;
}
```

2. No pull aggregation needed -- remote daily summaries stay remote.

### Phase 4: DAO Update (15 minutes)

Add to `lib/data/app_database.dart` (AttendanceDao):

```dart
/// Enqueues an attendance sync job covering a date range.
/// Unlike other entities, we batch-sync attendance by date range
/// rather than per-event, since aggregation is expensive.
Future<void> enqueueSyncForDateRange(
  String projectId,
  DateTime startDate,
  DateTime endDate,
) async {
  await syncOutboxDao.enqueue(
    targetTable: 'attendance',
    recordId: projectId,  // projectId, not an attendance row ID
    operation: 'batch_upsert',
    payloadJson: jsonEncode({
      'start_date': _dateString(startDate),
      'end_date': _dateString(endDate),
    }),
  );
}

/// Fetch all punches for a project within a date range
Future<List<LabourAttendanceData>> punchesInRange(
  String projectId,
  DateTime startDate,
  DateTime endDate,
) {
  return (select(labourAttendance)
        ..where((t) => t.projectId.equals(projectId))
        ..where((t) => t.punchIn.isBiggerOrEqualValue(startDate))
        ..where((t) => t.punchIn.isSmallerThanValue(endDate.add(Duration(days: 1)))))
      .get();
}
```

### Phase 5: UI Integration (10 minutes)

Update labour screen to trigger sync after marking attendance:

```dart
// In labour_screen.dart, after saving punch-in/punch-out:
await db.attendanceDao.enqueueSyncForDateRange(
  projectId,
  DateTime.now().subtract(Duration(days: 7)),  // Sync last 7 days
  DateTime.now(),
);
```

## Testing Strategy

### Unit Tests

1. **Aggregation logic** (`test/attendance_aggregator_test.dart`):
   ```dart
   test('8+ hours = present', () {
     final punches = [
       _punch(punchIn: '2026-08-28 08:00', punchOut: '2026-08-28 17:00'),
     ];
     final result = AttendanceAggregator.aggregatePunches(punches);
     expect(result.status, 'present');
   });
   
   test('4-8 hours = half_day', () { ... });
   test('< 4 hours = absent', () { ... });
   test('multiple shifts sum duration', () { ... });
   test('geofence violation adds note', () { ... });
   test('no punch-out adds note', () { ... });
   ```

2. **End-to-end sync** (`test/sync_engine_attendance_test.dart`):
   ```dart
   test('attendance punches aggregate and sync to Postgres', () async {
     // Insert worker
     final workerId = await insertWorker(db, projectId, 'John Doe');
     
     // Create punch-in and punch-out
     await db.attendanceDao.punchIn(workerId: workerId, ...);
     await db.attendanceDao.punchOut(workerId: workerId, ...);
     
     // Enqueue sync
     await db.attendanceDao.enqueueSyncForDateRange(...);
     
     // Push
     await engine.pushPending();
     
     // Verify in Postgres
     final rows = await adminClient
         .from('attendance')
         .select()
         .eq('worker_id', workerId);
     expect(rows.length, 1);
     expect(rows[0]['status'], 'present');
   });
   ```

## Effort Estimate

- **Aggregation function:** 20 minutes (writing + edge cases)
- **Sync mapper:** 10 minutes (straightforward, pull is no-op)
- **SyncEngine integration:** 20 minutes (batch push logic)
- **DAO update:** 15 minutes (enqueue + query methods)
- **UI integration:** 10 minutes (trigger after punch)
- **Tests:** 30 minutes (unit + integration)

**Total: ~1.5 hours** for a production-ready implementation.

## Trade-offs

### Chosen Approach: Aggregate on Push
- ✅ Preserves full event log locally (GPS, exact times)
- ✅ Remote gets payroll-ready daily summaries
- ✅ No data loss
- ❌ Pull can't reconstruct punch events (by design - remote doesn't have them)
- ❌ Slightly more complex sync logic

### Alternative: Sync Event Log to Postgres
- Would require new Postgres table `labour_punches` mirroring mobile schema
- Desktop would need to aggregate for payroll reports
- More storage, more complexity
- Not recommended - desktop doesn't need GPS/event granularity

### Alternative: Don't Sync Attendance at All
- Mobile-only attendance tracking
- Desktop enters attendance manually (current state)
- ❌ No cross-device visibility
- ❌ Manual double-entry for payroll

## Migration Notes

1. **Backfill existing punches:** On first sync, aggregate ALL historical punches
2. **Worker directory requirement:** Communicate to users that workers must be in Workers directory for attendance to sync
3. **Geofence violations:** Visible in notes field on desktop

## Production Checklist

- [ ] Aggregation function implemented with all edge cases
- [ ] Sync mapper added
- [ ] SyncEngine batch push logic
- [ ] DAO enqueue and query methods
- [ ] UI triggers sync after punch operations
- [ ] Unit tests for aggregation (5+ scenarios)
- [ ] Integration test: punch → aggregate → verify in Postgres
- [ ] RLS policy for attendance table verified
- [ ] Documentation updated in AGENT_HANDOFF.md

---

**Date:** 2026-08-28  
**Author:** AI Agent Analysis  
**Status:** Design Complete - Ready for Implementation  
**Complexity:** Medium (aggregation logic + batch sync pattern)
