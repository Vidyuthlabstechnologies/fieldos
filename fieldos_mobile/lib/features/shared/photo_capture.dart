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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/shared/photo_stamp.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// Bills and receipts are read again later for amounts and GST numbers,
/// so they are kept larger and less squeezed than site photos (Onsite's
/// reviews: "bill photos are blurry").
const photoMaxSide = 2048.0;
const photoQuality = 85;
const billMaxSide = 3200.0;
const billQuality = 95;

/// How many photos one gallery pick may bring in.
const maxPhotosPerPick = 10;

/// A picked file as the app keeps it: a photo, or a PDF when [allowPdf].
class CapturedFile {
  const CapturedFile(this.path, {this.isPdf = false});
  final String path;
  final bool isPdf;
}

/// The name a picked file is kept under: the kind of record, when, which
/// one of a multi-pick, and the picker's own name.
String capturedFileName(String prefix, int millis, int index, String pickedName) {
  final safe = pickedName.replaceAll(RegExp(r'[^\w.\-]'), '_');
  return index == 0 ? '${prefix}_${millis}_$safe' : '${prefix}_${millis}_${index}_$safe';
}

/// Capture a photo with camera-first UI. The [prefix] parameter is used
/// for organizing photos by type (e.g., 'dpr_', 'inspection_', 'grn_').
/// Camera photos get the date, time, GPS position and [place] stamped on
/// them; gallery picks are kept as they are (their time and place are
/// unknown).
Future<String?> captureCameraFirst(BuildContext context, {String prefix = 'photo', String? place, bool sharp = false}) async {
  final files = await captureCameraFirstMany(context, prefix: prefix, place: place, sharp: sharp, max: 1);
  return files.isEmpty ? null : files.first.path;
}

/// Like [captureCameraFirst], but the gallery lets the user pick up to
/// [max] photos at once, and [allowPdf] adds "Choose a PDF" for bills that
/// came by email or WhatsApp. [sharp] keeps the photo big enough to read a
/// bill's small print.
Future<List<CapturedFile>> captureCameraFirstMany(
  BuildContext context, {
  String prefix = 'photo',
  String? place,
  bool sharp = false,
  bool allowPdf = false,
  int max = maxPhotosPerPick,
}) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: Text(tr('Take photo')),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: Text(tr('Choose from gallery')),
            subtitle: max > 1 ? Text(trf('Up to {n} at once', {'n': '$max'})) : null,
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (allowPdf)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(tr('Choose a PDF')),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return const [];
  LocationService? location;
  try {
    location = ProviderScope.containerOf(context, listen: false).read(locationServiceProvider);
  } catch (_) {}
  final mediaDir = await localMediaDirectory();
  final millis = DateTime.now().millisecondsSinceEpoch;

  if (source == 'pdf') {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
    final from = file?.path;
    if (file == null || from == null) return const [];
    final target = '${mediaDir.path}/${capturedFileName(prefix, millis, 0, file.name)}';
    await File(from).copy(target);
    return [CapturedFile(target, isPdf: true)];
  }

  final camera = source == 'camera';
  // Start the GPS fix while the camera is open.
  final fix = camera && location != null
      ? location.currentFix().timeout(const Duration(seconds: 20)).then<LocationFix?>((f) => f, onError: (_) => null)
      : Future<LocationFix?>.value(null);

  final side = sharp ? billMaxSide : photoMaxSide;
  final quality = sharp ? billQuality : photoQuality;
  final picker = ImagePicker();
  final List<XFile> picked;
  if (camera) {
    final one = await picker.pickImage(source: ImageSource.camera, maxWidth: side, maxHeight: side, imageQuality: quality);
    picked = [?one];
  } else if (max > 1) {
    picked = (await picker.pickMultiImage(maxWidth: side, maxHeight: side, imageQuality: quality, limit: max)).take(max).toList();
  } else {
    final one = await picker.pickImage(source: ImageSource.gallery, maxWidth: side, maxHeight: side, imageQuality: quality);
    picked = [?one];
  }
  if (picked.isEmpty) return const [];

  final out = <CapturedFile>[];
  for (var i = 0; i < picked.length; i++) {
    final targetPath = '${mediaDir.path}/${capturedFileName(prefix, millis, i, picked[i].name)}';
    await picked[i].saveTo(targetPath);
    out.add(CapturedFile(targetPath));
  }
  if (camera) {
    final targetPath = out.single.path;
    try {
      final f = await fix.timeout(const Duration(seconds: 5), onTimeout: () => null);
      final lines = stampLines(takenAt: DateTime.now(), place: place, lat: f?.lat, lng: f?.lng, accuracyM: f?.accuracyM);
      final stamped = await stampJpegInBackground(await File(targetPath).readAsBytes(), lines,
          below: sharp, quality: sharp ? billQuality : photoQuality);
      if (stamped != null) await File(targetPath).writeAsBytes(stamped, flush: true);
    } catch (_) {
      // An unstamped photo is still evidence; never lose it over the stamp.
    }
  }
  return out;
}
