/// Site photos after they are saved: a row of thumbnails, and a full-screen
/// viewer to zoom, swipe and share them on WhatsApp. The photos already
/// carry the date, time and GPS stamp from the camera, so what is shared
/// still proves when and where it was taken.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/l10n/language.dart';

/// Only photos taken on this phone have a file here; a teammate's photos
/// are left out rather than shown as broken images.
List<String> photosOnThisPhone(Iterable<String> paths) => [for (final p in paths) if (File(p).existsSync()) p];

Future<void> sharePhotos(List<String> paths, {String? text}) async {
  if (paths.isEmpty) return;
  await SharePlus.instance.share(ShareParams(
    files: [for (final p in paths) XFile(p, mimeType: 'image/jpeg')],
    text: text,
  ));
}

Future<void> showPhotoViewer(BuildContext context, List<String> paths, {int initial = 0, String? shareText}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PhotoViewerScreen(paths: paths, initial: initial, shareText: shareText),
  ));
}

class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({super.key, required this.paths, this.initial = 0, this.shareText});
  final List<String> paths;
  final int initial;
  final String? shareText;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.paths.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(many ? '${_index + 1} / ${widget.paths.length}' : tr('Photo')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: tr('Share photo'),
            onPressed: () => sharePhotos([widget.paths[_index]], text: widget.shareText),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.paths.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(widget.paths[i]),
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thumbnails of a report's or checklist item's photos. Tap one to open it
/// full screen; "Share all" sends every photo at once.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.paths, this.shareText, this.size = 84});
  final List<String> paths;
  final String? shareText;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: size,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => Semantics(
            button: true,
            label: tr('Open photo'),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showPhotoViewer(context, paths, initial: i, shareText: shareText),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(paths[i]),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, _, _) =>
                      SizedBox(width: size, height: size, child: const Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
      ),
      if (paths.length > 1)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: Text(tr('Share all photos')),
            onPressed: () => sharePhotos(paths, text: shareText),
          ),
        ),
    ]);
  }
}
