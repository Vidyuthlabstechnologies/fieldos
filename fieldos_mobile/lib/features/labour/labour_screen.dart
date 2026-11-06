/// Labour attendance with GPS geofencing. A punch captures coordinates and is
/// flagged `withinGeofence` when it falls inside the project's configured
/// geofence — so site supervisors can see who clocked in on-site vs off-site,
/// feeding the cost engine's labour-productivity view.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/attendance_list.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';

/// Great-circle distance in metres between two coordinates.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _rad(double deg) => deg * pi / 180;

class LabourView extends ConsumerStatefulWidget {
  const LabourView(
      {super.key, required this.projectId, required this.companyId, required this.userId});
  final String projectId;
  final String companyId;
  final String userId;

  @override
  ConsumerState<LabourView> createState() => _LabourViewState();
}

class _LabourViewState extends ConsumerState<LabourView> {
  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(attendanceProvider(widget.projectId));
    final geofence = ref.watch(geofenceProvider(widget.projectId));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _GeofenceCard(projectId: widget.projectId),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Punch in'),
              onPressed: () => _punchIn(context, ref, geofence),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.groups),
              label: const Text('Mark many'),
              onPressed: () => _punchInMany(context, ref, geofence),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.payments),
          label: const Text('Wage sheet'),
          onPressed: () async {
            final project = await ref.read(appDatabaseProvider).projectDao.byId(widget.projectId);
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WageSheetScreen(
                  projectId: widget.projectId, projectName: project?.name ?? 'Site', userId: widget.userId),
            ));
          },
        ),
        const SizedBox(height: 12),
        attendance.when(
          data: (rows) => rows.isEmpty
              ? const EmptyState(
                  icon: Icons.how_to_reg_outlined,
                  title: 'No attendance yet',
                  message: 'Punch workers in when they reach the site. The wage sheet counts their days from this.',
                  compact: true,
                )
              : AttendanceList(
                  rows: rows,
                  onPunchOut: (a) => _punchOut(context, ref, a),
                  onSetOutTime: (a) => _setOutTime(context, ref, a),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
        ),
      ],
    );
  }

  Future<void> _punchIn(BuildContext context, WidgetRef ref, AsyncValue<ProjectGeofence?> geofence) async {
    final name = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final workers = await ref.read(workersProvider(widget.projectId).future);
    final activeWorkers = workers.where((w) => w.status == 'active').toList();
    String? selectedWorkerId;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Punch in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activeWorkers.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select worker (optional)'),
                  hint: const Text('— Type name manually —'),
                  initialValue: selectedWorkerId,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('— Type name manually —')),
                    ...activeWorkers.map((w) => DropdownMenuItem<String>(value: w.id, child: Text(w.name))),
                  ],
                  onChanged: (v) {
                    setDialogState(() {
                      selectedWorkerId = v?.isEmpty == true ? null : v;
                      if (v != null && v.isNotEmpty) {
                        final worker = activeWorkers.firstWhere((w) => w.id == v);
                        name.text = worker.name;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Worker name')),
              GpsFields(lat: lat, lng: lng),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Punch in')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;

    final latV = double.tryParse(lat.text);
    final lngV = double.tryParse(lng.text);
    final g = geofence.valueOrNull;
    final within = (g != null && latV != null && lngV != null)
        ? haversineMeters(latV, lngV, g.centerLat, g.centerLng) <= g.radiusMeters
        : null;

    await ref.read(appDatabaseProvider).attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          workerName: name.text.trim(),
          workerId: selectedWorkerId != null ? Value(selectedWorkerId!) : const Value.absent(),
          recordedBy: widget.userId,
          punchIn: DateTime.now(),
          lat: Value(latV),
          lng: Value(lngV),
          withinGeofence: Value(within),
        ));
    ref.invalidate(attendanceProvider(widget.projectId));
  }

  /// Morning roll call: tick everyone who turned up and punch them all in
  /// with one GPS reading, instead of one dialog per labourer.
  Future<void> _punchInMany(BuildContext context, WidgetRef ref, AsyncValue<ProjectGeofence?> geofence) async {
    final workers = (await ref.read(workersProvider(widget.projectId).future)).where((w) => w.status == 'active').toList();
    final attendance = await ref.read(attendanceProvider(widget.projectId).future);
    // Only today's open punches: a punch-out forgotten last week must not
    // keep someone off today's roll call.
    final alreadyIn = {
      for (final a in attendance)
        if (a.punchOut == null && a.workerId != null && isSameDay(a.punchIn, DateTime.now())) a.workerId!,
    };
    final candidates = workers.where((w) => !alreadyIn.contains(w.id)).toList();
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      showSnack(
          context,
          workers.isEmpty
              ? 'Add your labourers in the Workers tab first.'
              : 'Everyone in the Workers list is already punched in today.');
      return;
    }
    final picked = <String>{...candidates.map((w) => w.id)};
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Punch in ${picked.length} of ${candidates.length}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              Row(children: [
                TextButton(onPressed: () => set(() => picked.addAll(candidates.map((w) => w.id))), child: const Text('All')),
                TextButton(onPressed: () => set(picked.clear), child: const Text('None')),
              ]),
              for (final w in candidates)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(w.id),
                  title: Text(w.name),
                  subtitle: w.role == null ? null : Text(w.role!),
                  onChanged: (v) => set(() => v == true ? picked.add(w.id) : picked.remove(w.id)),
                ),
              GpsFields(lat: lat, lng: lng),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Punch in')),
          ],
        ),
      ),
    );
    if (ok != true || picked.isEmpty || !context.mounted) return;
    final latV = double.tryParse(lat.text);
    final lngV = double.tryParse(lng.text);
    final g = geofence.valueOrNull;
    final within = (g != null && latV != null && lngV != null)
        ? haversineMeters(latV, lngV, g.centerLat, g.centerLng) <= g.radiusMeters
        : null;
    final now = DateTime.now();
    final dao = ref.read(appDatabaseProvider).attendanceDao;
    for (final w in candidates.where((w) => picked.contains(w.id))) {
      await dao.punchIn(LabourAttendanceCompanion.insert(
        id: const Uuid().v4(),
        projectId: widget.projectId,
        workerName: w.name,
        workerId: Value(w.id),
        recordedBy: widget.userId,
        punchIn: now,
        lat: Value(latV),
        lng: Value(lngV),
        withinGeofence: Value(within),
      ));
    }
    ref.invalidate(attendanceProvider(widget.projectId));
  }

  /// A punch left open on an earlier day: ask when they left that day
  /// (punching out "now" would count the days in between as hours on site).
  Future<void> _setOutTime(BuildContext context, WidgetRef ref, LabourAttendanceData a) async {
    final inAt = a.punchIn.toLocal();
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
      helpText: 'When did ${a.workerName} leave on ${fmtDate(inAt, short: true)}?',
    );
    if (picked == null || !context.mounted) return;
    final outAt = DateTime(inAt.year, inAt.month, inAt.day, picked.hour, picked.minute);
    if (!outAt.isAfter(inAt)) {
      showSnack(context, 'Pick a time after they punched in (${fmtTime(inAt)}).', error: true);
      return;
    }
    await ref.read(appDatabaseProvider).attendanceDao.punchOut(a.id, at: outAt);
    ref.invalidate(attendanceProvider(widget.projectId));
    if (context.mounted) showSnack(context, '${a.workerName}: out at ${fmtTime(outAt)} on ${fmtDate(inAt, short: true)}');
  }

  Future<void> _punchOut(BuildContext context, WidgetRef ref, LabourAttendanceData a) async {
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Punch out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GpsFields(lat: lat, lng: lng),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Punch out')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final latV = double.tryParse(lat.text);
    final lngV = double.tryParse(lng.text);
    final g = ref.read(geofenceProvider(widget.projectId)).valueOrNull;
    final within = (g != null && latV != null && lngV != null)
        ? haversineMeters(latV, lngV, g.centerLat, g.centerLng) <= g.radiusMeters
        : a.withinGeofence;
    await ref.read(appDatabaseProvider).attendanceDao.punchOut(a.id, lat: latV, lng: lngV, withinGeofence: within);
    ref.invalidate(attendanceProvider(widget.projectId));
  }
}

class _GeofenceCard extends ConsumerWidget {
  const _GeofenceCard({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geofence = ref.watch(geofenceProvider(projectId));
    final scheme = Theme.of(context).colorScheme;
    final set = geofence.valueOrNull != null;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Icon(set ? Icons.gps_fixed : Icons.gps_not_fixed, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: geofence.when(
                data: (g) => Text(g == null
                    ? 'No site area set, so punches are not checked. Set it while standing at the site.'
                    : 'Site area: within ${g.radiusMeters.round()} m of the point you set. Punches outside it are marked.'),
                loading: () => const Text('Checking the site area…'),
                error: (e, st) => Text(friendlyError(e, st)),
              ),
            ),
            TextButton(
              child: Text(set ? 'Change' : 'Set site area'),
              onPressed: () => _configure(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _configure(BuildContext context, WidgetRef ref) async {
    final lat = TextEditingController();
    final lng = TextEditingController();
    final radius = TextEditingController(text: '100');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Site area'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Stand in the middle of the site. Punches within the radius count as on site.'),
            GpsFields(lat: lat, lng: lng),
            TextField(
                controller: radius,
                decoration: const InputDecoration(labelText: 'Radius in metres', helperText: '100 m suits most sites'),
                keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final latV = double.tryParse(lat.text);
    final lngV = double.tryParse(lng.text);
    if (latV == null || lngV == null || latV.abs() > 90 || lngV.abs() > 180) {
      showSnack(context, 'No location yet. Wait for the GPS fix, then save again.', error: true);
      return;
    }
    final r = double.tryParse(radius.text.trim()) ?? 100;
    if (r < 10 || r > 5000) {
      showSnack(context, 'Use a radius between 10 and 5000 metres.', error: true);
      return;
    }
    await ref.read(appDatabaseProvider).geofenceDao.set(projectId, latV, lngV, r);
    ref.invalidate(geofenceProvider(projectId));
    if (context.mounted) showSnack(context, 'Site area saved');
  }
}


/// Latitude/longitude fields filled automatically from the phone's GPS as
/// soon as the dialog opens (they used to be typed by hand, which made the
/// geofence check trivially fakeable and slow to use). Still editable, and
/// a manual value is kept if GPS is unavailable.
class GpsFields extends ConsumerStatefulWidget {
  const GpsFields({super.key, required this.lat, required this.lng});
  final TextEditingController lat;
  final TextEditingController lng;

  @override
  ConsumerState<GpsFields> createState() => _GpsFieldsState();
}

class _GpsFieldsState extends ConsumerState<GpsFields> {
  String _status = 'Getting your location…';
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _status = 'Getting your location…';
    });
    try {
      final fix = await ref.read(locationServiceProvider).currentFix();
      widget.lat.text = fix.lat.toStringAsFixed(6);
      widget.lng.text = fix.lng.toStringAsFixed(6);
      if (mounted) setState(() => _status = 'GPS fix, accurate to about ${fix.accuracyM.round()} m');
    } catch (e) {
      if (mounted) setState(() => _status = e is LocationUnavailable ? e.message : 'Could not get a GPS fix.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_locating)
              const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.my_location, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_status, style: Theme.of(context).textTheme.bodySmall)),
            if (!_locating) TextButton(onPressed: _locate, child: const Text('Retry')),
          ],
        ),
        TextField(
          controller: widget.lat,
          decoration: const InputDecoration(labelText: 'Latitude'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        ),
        TextField(
          controller: widget.lng,
          decoration: const InputDecoration(labelText: 'Longitude'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        ),
      ],
    );
  }
}
