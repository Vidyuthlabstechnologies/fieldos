/// The current drawing on screen with its pins and markup: pinch to zoom,
/// tap a spot to leave a note or raise a defect or RFI right there, or draw
/// on it. PDFs are shown a page at a time as an image from the phone's own
/// PDF renderer, so pins sit on the page the same way on every phone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart' show askText;
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// One page of a revision as an image, its size, and the page count.
class SheetPage {
  const SheetPage(this.file, this.size, this.pages);
  final File file;
  final Size size;
  final int pages;
}

bool isPdfRevision(DrawingRevision r) =>
    r.mimeType.toLowerCase().contains('pdf') || r.filePath.toLowerCase().endsWith('.pdf');

Future<Size> _imageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final s = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  codec.dispose();
  return s;
}

/// Renders [page] of a PDF revision once and keeps the PNG beside the app's
/// files; an image revision is used as it is.
Future<SheetPage> loadSheetPage(DrawingRevision r, int page) async {
  final source = File(r.filePath);
  if (!source.existsSync()) throw const FileSystemException('missing');
  if (!isPdfRevision(r)) {
    return SheetPage(source, await _imageSize(await source.readAsBytes()), 1);
  }
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'drawing_pages'));
  await dir.create(recursive: true);
  final out = File(p.join(dir.path, '${r.id}_$page.png'));
  final countFile = File(p.join(dir.path, '${r.id}.pages'));
  final pdf = await source.readAsBytes();
  var pages = int.tryParse(countFile.existsSync() ? countFile.readAsStringSync() : '') ?? 0;
  if (pages == 0) {
    // A tiny render of every page, only to count them.
    await for (final _ in Printing.raster(pdf, dpi: 4)) {
      pages++;
    }
    await countFile.writeAsString('$pages');
  }
  if (!out.existsSync()) {
    // 150 dpi: an A1 sheet is about 5000 px wide, sharp enough to read
    // dimensions when zoomed, small enough for a site phone.
    final raster = await Printing.raster(pdf, pages: [page], dpi: 150).first;
    await out.writeAsBytes(await raster.toPng(), flush: true);
  }
  return SheetPage(out, await _imageSize(await out.readAsBytes()), pages);
}

/// Tests swap the renderer (there is no PDF engine in a widget test).
final sheetPageLoaderProvider = Provider<Future<SheetPage> Function(DrawingRevision, int)>((ref) => loadSheetPage);

enum _Mode { look, pin, draw }

const _penColors = {'red': Color(0xFFD32F2F), 'blue': Color(0xFF1565C0)};

class DrawingSheetScreen extends ConsumerStatefulWidget {
  const DrawingSheetScreen({super.key, required this.project, required this.drawingId});
  final Project project;
  final String drawingId;

  @override
  ConsumerState<DrawingSheetScreen> createState() => _DrawingSheetScreenState();
}

class _DrawingSheetScreenState extends ConsumerState<DrawingSheetScreen> {
  final _zoom = TransformationController();
  _Mode _mode = _Mode.look;
  int _page = 0;
  String _pen = 'red';

  /// Strokes being drawn, in page fractions.
  final List<List<Offset>> _strokes = [];
  Future<SheetPage>? _sheet;
  String? _sheetKey;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  bool get _canWrite {
    final role = ref.read(sessionProvider).role;
    return role != null && Roles.canWrite(role);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(executionDataProvider(widget.project.id));
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: ErrorState(error: e, stack: st)),
      data: (d) {
        final dr = d.drawingById[widget.drawingId];
        final rev = dr == null ? null : d.currentRevision(dr.id);
        if (dr == null || rev == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.layers_clear_outlined,
              title: tr('No approved revision yet'),
              message: tr('Pins go on the revision the site builds to, once a manager approves it.'),
            ),
          );
        }
        // A newly approved revision (from sync, or approved meanwhile) opens
        // on its first page: the page we were on may not exist in it, and
        // the screen then said the drawing could not be shown.
        if (_sheetKey != null && !_sheetKey!.startsWith('${rev.id}/')) _page = 0;
        final key = '${rev.id}/$_page';
        if (_sheetKey != key) {
          _sheetKey = key;
          _sheet = ref.read(sheetPageLoaderProvider)(rev, _page);
        }
        final pins = d.pinsOn(dr.id, page: _page);
        return Scaffold(
          appBar: AppBar(
            title: Text('${dr.number} ${rev.rev}', maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: tr('Open the file'),
                icon: const Icon(Icons.open_in_new),
                onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(rev.filePath)], subject: '${dr.number} ${rev.rev}')),
              ),
            ],
          ),
          body: FutureBuilder<SheetPage>(
            future: _sheet,
            builder: (context, snap) {
              if (snap.hasError) {
                return EmptyState(
                  icon: Icons.cloud_download_outlined,
                  title: tr('The drawing could not be shown'),
                  message: tr('The file is not on this phone yet. Sync and try again.'),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final sheet = snap.data!;
              return Column(children: [
                if (sheet.pages > 1) _pageBar(sheet.pages),
                Expanded(child: _canvas(context, d, dr, rev, sheet, pins)),
                if (_canWrite) _toolbar(context, d, rev),
              ]);
            },
          ),
        );
      },
    );
  }

  Widget _pageBar(int pages) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            tooltip: tr('Previous page'),
            icon: const Icon(Icons.chevron_left),
            onPressed: _page == 0 ? null : () => setState(() => _page--),
          ),
          Text(trf('Page {n} of {total}', {'n': _page + 1, 'total': pages})),
          IconButton(
            tooltip: tr('Next page'),
            icon: const Icon(Icons.chevron_right),
            onPressed: _page >= pages - 1 ? null : () => setState(() => _page++),
          ),
        ]),
      );

  Widget _canvas(BuildContext context, ExecutionData d, Drawing dr, DrawingRevision rev, SheetPage sheet, List<DrawingPin> pins) {
    final scale = _zoom.value.getMaxScaleOnAxis();
    final drawing = _mode == _Mode.draw;
    return LayoutBuilder(builder: (context, box) {
      final fit = applyBoxFit(BoxFit.contain, sheet.size, box.biggest).destination;
      Offset frac(Offset local) => Offset((local.dx / fit.width).clamp(0.0, 1.0), (local.dy / fit.height).clamp(0.0, 1.0));
      return InteractiveViewer(
        transformationController: _zoom,
        minScale: 1,
        maxScale: 10,
        panEnabled: !drawing,
        scaleEnabled: !drawing,
        // Pages are drawn left to right in every language.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: fit.width,
              height: fit.height,
              child: GestureDetector(
                key: const Key('sheet-canvas'),
                behavior: HitTestBehavior.opaque,
                onTapUp: _mode == _Mode.pin ? (e) => _placePin(context, d, dr, rev, frac(e.localPosition)) : null,
                onPanStart: drawing ? (e) => setState(() => _strokes.add([frac(e.localPosition)])) : null,
                onPanUpdate: drawing ? (e) => setState(() => _strokes.last.add(frac(e.localPosition))) : null,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: Image.file(sheet.file, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _MarkupPainter(
                          saved: [for (final p in pins) if (p.kind == 'markup') p],
                          drawing: _strokes,
                          pen: _penColors[_pen]!,
                          scale: scale,
                        ),
                      ),
                    ),
                  ),
                  for (final pin in pins)
                    // Inside the left-to-right page, start is the left edge.
                    PositionedDirectional(
                      start: pin.x * fit.width - 20,
                      top: pin.y * fit.height - 20,
                      width: 40,
                      height: 40,
                      child: Transform.scale(
                        scale: 1 / scale,
                        child: _PinMark(
                          key: Key('pin-${pin.id}'),
                          pin: pin,
                          tone: _pinTone(d, pin),
                          onTap: () => _openPin(context, d, pin),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _toolbar(BuildContext context, ExecutionData d, DrawingRevision rev) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        color: theme.colorScheme.surfaceContainer,
        padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_mode != _Mode.look)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _mode == _Mode.pin ? tr('Tap the spot on the drawing.') : tr('Draw with your finger, then save.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_mode == _Mode.draw)
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final c in _penColors.keys)
                ChoiceChip(
                  label: Text(c == 'red' ? tr('Red') : tr('Blue')),
                  selected: _pen == c,
                  onSelected: (_) => setState(() => _pen = c),
                ),
              IconButton(
                tooltip: tr('Undo'),
                icon: const Icon(Icons.undo),
                onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
              ),
              FilledButton(
                key: const Key('sheet-save-markup'),
                onPressed: _strokes.isEmpty ? null : () => _saveMarkup(context, rev),
                child: Text(tr('Save')),
              ),
            ]),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Mode.look, icon: const Icon(Icons.pan_tool_outlined), label: Text(tr('Look'))),
              ButtonSegment(
                  value: _Mode.pin, icon: const Icon(Icons.add_location_alt_outlined, key: Key('sheet-mode-pin')), label: Text(tr('Pin'))),
              ButtonSegment(value: _Mode.draw, icon: const Icon(Icons.draw_outlined, key: Key('sheet-mode-draw')), label: Text(tr('Draw'))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              if (_mode != _Mode.draw) _strokes.clear();
            }),
          ),
        ]),
      ),
    );
  }

  PillTone _pinTone(ExecutionData d, DrawingPin pin) {
    switch (pin.kind) {
      case 'defect':
        final x = d.defects.where((e) => e.id == pin.linkId).firstOrNull;
        if (x == null) return PillTone.neutral;
        return x.status == 'closed' ? PillTone.ok : (x.status == 'fixed' ? PillTone.warn : PillTone.danger);
      case 'rfi':
        final x = d.rfis.where((e) => e.id == pin.linkId).firstOrNull;
        if (x == null) return PillTone.neutral;
        return x.status == 'open' ? PillTone.warn : PillTone.ok;
      default:
        return PillTone.neutral;
    }
  }

  String _me() => ref.read(sessionProvider).user!.id;

  Future<void> _write(BuildContext context, Future<void> Function() run, {String? done}) async {
    try {
      await run();
      ref.invalidate(executionDataProvider(widget.project.id));
      if (done != null && context.mounted) showSnack(context, done);
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  Future<void> _placePin(BuildContext context, ExecutionData d, Drawing dr, DrawingRevision rev, Offset at) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const Key('pin-kind-defect'),
            leading: const Icon(Icons.report_problem_outlined),
            title: Text(tr('Defect here')),
            onTap: () => Navigator.pop(ctx, 'defect'),
          ),
          ListTile(
            key: const Key('pin-kind-rfi'),
            leading: const Icon(Icons.help_outline),
            title: Text(tr('Question for the designer (RFI)')),
            onTap: () => Navigator.pop(ctx, 'rfi'),
          ),
          ListTile(
            key: const Key('pin-kind-note'),
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(tr('Note')),
            onTap: () => Navigator.pop(ctx, 'note'),
          ),
        ]),
      ),
    );
    if (kind == null || !context.mounted) return;
    final x = ref.read(appDatabaseProvider).siteExecutionDao;
    final me = _me();
    final page = _page;
    switch (kind) {
      case 'defect':
        final picked = await _askDefect(context);
        if (picked == null || !context.mounted) return;
        await _write(context, () async {
          final defect = await x.raiseDefect(
            projectId: widget.project.id,
            description: picked.$1,
            severity: picked.$2,
            location: trf('Drawing {number}', {'number': dr.number}),
            by: me,
          );
          await x.addPin(
              projectId: widget.project.id, revisionId: rev.id, kind: 'defect', label: picked.$1, x: at.dx, y: at.dy, page: page,
              linkId: defect.id, by: me);
        }, done: tr('Defect raised and pinned.'));
      case 'rfi':
        final q = await askText(context, title: tr('Question for the designer (RFI)'), label: tr('Question'));
        if (q == null || q.isEmpty || !context.mounted) return;
        await _write(context, () async {
          final rfi = await x.raiseRfi(projectId: widget.project.id, question: q, drawingId: dr.id, by: me);
          await x.addPin(
              projectId: widget.project.id, revisionId: rev.id, kind: 'rfi', label: q, x: at.dx, y: at.dy, page: page, linkId: rfi.id, by: me);
        }, done: tr('RFI raised and pinned.'));
      default:
        final note = await askText(context, title: tr('Note'), label: tr('What is here?'));
        if (note == null || note.isEmpty || !context.mounted) return;
        await _write(context, () async {
          await x.addPin(projectId: widget.project.id, revisionId: rev.id, kind: 'note', label: note, x: at.dx, y: at.dy, page: page, by: me);
        });
    }
  }

  Future<(String, String)?> _askDefect(BuildContext context) async {
    final c = TextEditingController();
    var severity = 'minor';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Defect here')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              key: const Key('pin-defect-text'),
              controller: c,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr('What is wrong?')),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final s in defectSeverities)
                ChoiceChip(label: Text(severityLabel(s)), selected: severity == s, onSelected: (_) => set(() => severity = s)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('pin-defect-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    final text = c.text.trim();
    return ok == true && text.isNotEmpty ? (text, severity) : null;
  }

  Future<void> _saveMarkup(BuildContext context, DrawingRevision rev) async {
    final label = await askText(context, title: tr('Save markup'), label: tr('What does it show? (optional)'));
    if (label == null || !context.mounted) return;
    final strokes = [
      for (final s in _strokes)
        if (s.length > 1) [for (final o in s) ...[_round(o.dx), _round(o.dy)]],
    ];
    if (strokes.isEmpty) return;
    final start = _strokes.first.first;
    final json = jsonEncode(strokes);
    if (json.length > 40000) {
      showSnack(context, tr('That markup is too large. Save it in smaller parts.'), error: true);
      return;
    }
    await _write(context, () async {
      await ref.read(appDatabaseProvider).siteExecutionDao.addPin(
            projectId: widget.project.id,
            revisionId: rev.id,
            kind: 'markup',
            label: label.isEmpty ? tr('Markup') : label,
            x: start.dx,
            y: start.dy,
            page: _page,
            strokes: json,
            color: _pen,
            by: _me(),
          );
    });
    if (mounted) setState(_strokes.clear);
  }

  Future<void> _openPin(BuildContext context, ExecutionData d, DrawingPin pin) async {
    final session = ref.read(sessionProvider);
    final mine = pin.createdBy == session.user?.id;
    final manager = Roles.canApprove(session.role);
    String? status;
    if (pin.kind == 'defect') {
      final x = d.defects.where((e) => e.id == pin.linkId).firstOrNull;
      if (x != null) status = '${severityLabel(x.severity)} · ${_defectStatus(x.status)}';
    } else if (pin.kind == 'rfi') {
      final x = d.rfis.where((e) => e.id == pin.linkId).firstOrNull;
      if (x != null) status = x.answer == null ? _rfiStatus(x.status) : '${_rfiStatus(x.status)}: ${x.answer}';
    }
    final remove = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_kindLabel(pin.kind), style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(pin.label, style: Theme.of(ctx).textTheme.titleMedium),
            if (status != null) ...[const SizedBox(height: 4), Text(status)],
            const SizedBox(height: 4),
            Text(fmtDateTime(pin.createdAt), style: Theme.of(ctx).textTheme.bodySmall),
            if (mine || manager) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('pin-remove'),
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Remove pin')),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ]),
        ),
      ),
    );
    if (remove != true || !context.mounted) return;
    await _write(context, () async {
      await ref.read(appDatabaseProvider).siteExecutionDao.removePin(pin.id, by: session.user!.id, manager: manager);
    });
  }
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;

String _kindLabel(String k) => switch (k) {
      'defect' => tr('Defect'),
      'rfi' => tr('RFI'),
      'markup' => tr('Markup'),
      _ => tr('Note'),
    };

String _defectStatus(String s) => switch (s) {
      'closed' => tr('Closed'),
      'fixed' => tr('Fixed'),
      _ => tr('Open'),
    };

String _rfiStatus(String s) => switch (s) {
      'answered' => tr('Answered'),
      'closed' => tr('Closed'),
      _ => tr('Open'),
    };

class _PinMark extends StatelessWidget {
  const _PinMark({super.key, required this.pin, required this.tone, required this.onTap});
  final DrawingPin pin;
  final PillTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = pin.kind == 'markup'
        ? (_penColors[pin.color] ?? _penColors['red']!)
        : pin.kind == 'note'
            ? Theme.of(context).colorScheme.primary
            : toneColor(context, tone);
    final icon = switch (pin.kind) {
      'defect' => Icons.report_problem,
      'rfi' => Icons.help,
      'markup' => Icons.draw,
      _ => Icons.sticky_note_2,
    };
    return Semantics(
      button: true,
      label: '${_kindLabel(pin.kind)}: ${pin.label}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
              boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  _MarkupPainter({required this.saved, required this.drawing, required this.pen, required this.scale});
  final List<DrawingPin> saved;
  final List<List<Offset>> drawing;
  final Color pen;
  final double scale;

  void _stroke(Canvas c, Size size, List<Offset> pts, Color color) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx * size.width, o.dy * size.height);
    }
    c.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3 / scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final pin in saved) {
      final color = _penColors[pin.color] ?? _penColors['red']!;
      for (final s in decodeStrokes(pin.strokes)) {
        _stroke(canvas, size, s, color);
      }
    }
    for (final s in drawing) {
      _stroke(canvas, size, s, pen);
    }
  }

  @override
  bool shouldRepaint(_MarkupPainter old) => true;
}

/// Markup strokes from their JSON (`[[x, y, x, y, ...], ...]`); anything
/// malformed is skipped rather than failing the drawing.
List<List<Offset>> decodeStrokes(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (s is List)
          [
            for (var i = 0; i + 1 < s.length; i += 2)
              if (s[i] is num && s[i + 1] is num) Offset((s[i] as num).toDouble(), (s[i + 1] as num).toDouble()),
          ],
    ];
  } on FormatException {
    return const [];
  }
}
