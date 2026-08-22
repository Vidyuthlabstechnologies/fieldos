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

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

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
        FilledButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('Punch in'),
          onPressed: () => _punchIn(context, ref, geofence),
        ),
        const SizedBox(height: 12),
        attendance.when(
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('No attendance yet.'))
              : Column(
                  children: [
                    for (final a in rows)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            a.withinGeofence == true ? Icons.location_on : Icons.location_off,
                            color: a.withinGeofence == true ? Colors.green : Colors.orange,
                          ),
                          title: Text(a.workerName),
                          subtitle: Text(
                            'In ${a.punchIn.toLocal().toString().split('.')[0]}${a.punchOut != null ? '  •  Out ${a.punchOut!.toLocal().toString().split('.')[0]}' : ''}'
                            '${a.lat != null ? '  •  (${a.lat!.toStringAsFixed(4)}, ${a.lng!.toStringAsFixed(4)})' : ''}',
                          ),
                          trailing: a.punchOut == null
                              ? TextButton(
                                  child: const Text('Punch out'),
                                  onPressed: () => _punchOut(context, ref, a),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
      ],
    );
  }

  Future<void> _punchIn(BuildContext context, WidgetRef ref, AsyncValue<ProjectGeofence?> geofence) async {
    final name = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Punch in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Worker name')),
            TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude (GPS)'), keyboardType: TextInputType.number),
            TextField(controller: lng, decoration: const InputDecoration(labelText: 'Longitude (GPS)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Punch in')),
        ],
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
          recordedBy: widget.userId,
          punchIn: DateTime.now(),
          lat: Value(latV),
          lng: Value(lngV),
          withinGeofence: Value(within),
        ));
    ref.invalidate(attendanceProvider(widget.projectId));
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
            TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude (GPS)'), keyboardType: TextInputType.number),
            TextField(controller: lng, decoration: const InputDecoration(labelText: 'Longitude (GPS)'), keyboardType: TextInputType.number),
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
    return Card(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed),
            const SizedBox(width: 8),
            Expanded(
              child: geofence.when(
                data: (g) => Text(g == null
                    ? 'No geofence set — punches will not be validated.'
                    : 'Geofence: (${g.centerLat.toStringAsFixed(4)}, ${g.centerLng.toStringAsFixed(4)}) ± ${g.radiusMeters.toInt()} m'),
                loading: () => const Text('Loading geofence…'),
                error: (e, _) => Text('$e'),
              ),
            ),
            TextButton(
              child: const Text('Configure'),
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
        title: const Text('Set project geofence'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: lat, decoration: const InputDecoration(labelText: 'Center latitude'), keyboardType: TextInputType.number),
            TextField(controller: lng, decoration: const InputDecoration(labelText: 'Center longitude'), keyboardType: TextInputType.number),
            TextField(controller: radius, decoration: const InputDecoration(labelText: 'Radius (m)'), keyboardType: TextInputType.number),
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
    if (latV == null || lngV == null) return;
    await ref.read(appDatabaseProvider).geofenceDao.set(projectId, latV, lngV, double.tryParse(radius.text) ?? 100);
    ref.invalidate(geofenceProvider(projectId));
  }
}
