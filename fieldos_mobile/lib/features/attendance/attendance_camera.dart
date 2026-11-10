/// The camera for attendance: a selfie at a staff check-in, or a photo of
/// the worker or the morning roll call at a labour punch. Camera only, no
/// gallery (an old photo would defeat the point), stamped with the time,
/// the site and the GPS position.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/shared/photo_stamp.dart';
import 'package:fieldos_mobile/services/location_service.dart';

/// Small enough to sync on a weak connection, big enough to see a face.
const attendancePhotoSide = 1280.0;
const attendancePhotoQuality = 80;

abstract class AttendanceCamera {
  /// The photo's path on the phone, or null when they backed out.
  Future<String?> take({required bool selfie, String? place, LocationFix? fix});
}

class DeviceAttendanceCamera implements AttendanceCamera {
  @override
  Future<String?> take({required bool selfie, String? place, LocationFix? fix}) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
      maxWidth: attendancePhotoSide,
      maxHeight: attendancePhotoSide,
      imageQuality: attendancePhotoQuality,
    );
    if (picked == null) return null;
    final dir = await localMediaDirectory();
    final path = '${dir.path}/${selfie ? 'selfie' : 'punch'}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await picked.saveTo(path);
    try {
      final lines = stampLines(takenAt: DateTime.now(), place: place, lat: fix?.lat, lng: fix?.lng, accuracyM: fix?.accuracyM);
      final stamped = await stampJpegInBackground(await File(path).readAsBytes(), lines, quality: attendancePhotoQuality);
      if (stamped != null) await File(path).writeAsBytes(stamped, flush: true);
    } catch (_) {
      // An unstamped photo is still evidence.
    }
    return path;
  }
}

final attendanceCameraProvider = Provider<AttendanceCamera>((ref) => DeviceAttendanceCamera());
