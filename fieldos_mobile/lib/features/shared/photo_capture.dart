/// Camera-first photo evidence capture. Site evidence (DPR progress,
/// inspection findings, material receipts) is overwhelmingly captured on the
/// spot with the camera, so camera comes first in the UI and gallery is the
/// fallback -- the opposite of a generic file picker.
///
/// Copies the picked image into the app's local media directory before
/// returning, so the path we store stays valid even after the picker's
/// cache is cleared (same contract as documents_screen's file handling).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/shared/photo_stamp.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';

/// Capture a photo with camera-first UI. The [prefix] parameter is used
/// for organizing photos by type (e.g., 'dpr_', 'inspection_', 'grn_').
/// Camera photos get the date, time, GPS position and [place] stamped on
/// them; gallery picks are kept as they are (their time and place are
/// unknown).
Future<String?> captureCameraFirst(BuildContext context, {String prefix = 'photo', String? place}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  LocationService? location;
  try {
    location = ProviderScope.containerOf(context, listen: false).read(locationServiceProvider);
  } catch (_) {}
  // Start the GPS fix while the camera is open.
  final fix = source == ImageSource.camera && location != null
      ? location.currentFix().timeout(const Duration(seconds: 20)).then<LocationFix?>((f) => f, onError: (_) => null)
      : Future<LocationFix?>.value(null);

  final picked = await ImagePicker().pickImage(source: source, maxWidth: 2048, imageQuality: 85);
  if (picked == null) return null;

  final mediaDir = await localMediaDirectory();
  final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
  final targetPath = '${mediaDir.path}/$fileName';
  await picked.saveTo(targetPath);
  if (source == ImageSource.camera) {
    try {
      final f = await fix.timeout(const Duration(seconds: 5), onTimeout: () => null);
      final lines = stampLines(takenAt: DateTime.now(), place: place, lat: f?.lat, lng: f?.lng, accuracyM: f?.accuracyM);
      final stamped = await stampJpegInBackground(await File(targetPath).readAsBytes(), lines);
      if (stamped != null) await File(targetPath).writeAsBytes(stamped, flush: true);
    } catch (_) {
      // An unstamped photo is still evidence; never lose it over the stamp.
    }
  }
  return targetPath;
}
