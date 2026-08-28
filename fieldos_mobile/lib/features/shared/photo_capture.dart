/// Camera-first photo evidence capture. Site evidence (DPR progress,
/// inspection findings, material receipts) is overwhelmingly captured on the
/// spot with the camera, so camera comes first in the UI and gallery is the
/// fallback -- the opposite of a generic file picker.
///
/// Copies the picked image into the app's local media directory before
/// returning, so the path we store stays valid even after the picker's
/// cache is cleared (same contract as documents_screen's file handling).
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fieldos_mobile/data/app_database.dart';

/// Capture a photo with camera-first UI. The [prefix] parameter is used
/// for organizing photos by type (e.g., 'dpr_', 'inspection_', 'grn_').
Future<String?> captureCameraFirst(BuildContext context, {String prefix = 'photo'}) async {
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

  final picked = await ImagePicker().pickImage(source: source, maxWidth: 2048, imageQuality: 85);
  if (picked == null) return null;

  final mediaDir = await localMediaDirectory();
  final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
  final targetPath = '${mediaDir.path}/$fileName';
  await picked.saveTo(targetPath);
  return targetPath;
}
