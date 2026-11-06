/// Every project site on one map, with its attendance geofence. Uses
/// OpenStreetMap tiles through flutter_map: no API key and no billing,
/// keeping the product at zero running cost. (OSM's tile policy asks for a
/// real user agent and modest use, which a contractor's handful of sites is.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';

class SiteMapScreen extends ConsumerWidget {
  const SiteMapScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider(companyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Site map')),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          final placed = all.where((p) => p.locationLat != null && p.locationLng != null).toList();
          final unplaced = all.where((p) => p.locationLat == null || p.locationLng == null).toList();
          return Column(
            children: [
              Expanded(child: _Map(placed: placed)),
              if (unplaced.isNotEmpty)
                Material(
                  elevation: 4,
                  child: ExpansionTile(
                    title: Text('${unplaced.length} project${unplaced.length == 1 ? '' : 's'} without a site location'),
                    children: [
                      for (final p in unplaced)
                        ListTile(
                          title: Text(p.name),
                          subtitle: const Text('Stand on site and tap to set it from GPS'),
                          trailing: const Icon(Icons.add_location_alt),
                          onTap: () => _placeHere(context, ref, p),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _placeHere(BuildContext context, WidgetRef ref, Project p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fix = await ref.read(locationServiceProvider).currentFix();
      await ref.read(appDatabaseProvider).geofenceDao.set(p.id, fix.lat, fix.lng, 100);
      ref.invalidate(projectsProvider(companyId));
      ref.invalidate(geofenceProvider(p.id));
      messenger.showSnackBar(SnackBar(content: Text('${p.name} placed here, with a 100 m attendance geofence.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is LocationUnavailable ? e.message : 'Could not get a GPS fix.')));
    }
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.placed});
  final List<Project> placed;

  @override
  Widget build(BuildContext context) {
    if (placed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No site locations yet. Set one below, or from a project\'s Labour tab.', textAlign: TextAlign.center),
        ),
      );
    }
    final points = [for (final p in placed) LatLng(p.locationLat!, p.locationLng!)];
    final scheme = Theme.of(context).colorScheme;
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: points.length == 1
            ? null
            : CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(48)),
        initialCenter: points.first,
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.mldynamic.fieldos',
        ),
        CircleLayer(circles: [
          for (final p in placed)
            CircleMarker(
              point: LatLng(p.locationLat!, p.locationLng!),
              radius: (p.geofenceRadiusM ?? 100).toDouble(),
              useRadiusInMeter: true,
              color: scheme.primary.withValues(alpha: 0.12),
              borderColor: scheme.primary,
              borderStrokeWidth: 1.5,
            ),
        ]),
        MarkerLayer(markers: [
          for (final p in placed)
            Marker(
              point: LatLng(p.locationLat!, p.locationLng!),
              width: 160,
              height: 64,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(4)),
                      child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ),
                    Icon(Icons.location_on, color: scheme.primary, size: 32),
                  ],
                ),
              ),
            ),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
      ],
    );
  }
}
