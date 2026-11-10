/// Mitra ("friend"), FieldOS's site buddy: a young site engineer in the
/// brand's amber hard hat and hi-vis vest, who guides the tour, keeps empty
/// screens company and reacts to what happens.
///
/// Drawn and animated in Rive (mascot/make_scene.py), then rendered to one
/// looping WebP per mood (mascot/render_frames.py): the app shows those
/// rather than a .riv, so there is no Rive watermark and no native runtime.
/// With "remove animations" on in the phone's settings, Mitra holds still.
library;

import 'package:flutter/material.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';

/// Mitra's moods, in the same order as the Rive scene's `mood` number.
enum MitraMood {
  idle,
  wave,
  talk,
  think,
  celebrate,
  thumbsUp,
  listen,
  sleep,
  oops,
  worried,
  surprised,
  point,
  measure,
  hammer,
  money,
  checklist,
  chai,
}

class Mitra extends StatelessWidget {
  const Mitra({super.key, this.mood = MitraMood.idle, this.size = 120, this.still = false});

  final MitraMood mood;
  final double size;

  /// The first frame only (also used when the phone asks for less motion).
  final bool still;

  static String animatedAsset(MitraMood mood) => 'assets/mascot/mitra_${mood.name}.webp';
  static String stillAsset(MitraMood mood) => 'assets/mascot/mitra_${mood.name}.png';

  @override
  Widget build(BuildContext context) {
    final calm = still || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final asset = calm ? stillAsset(mood) : animatedAsset(mood);
    // Its own layer: the animated frames repaint only Mitra, never the
    // list or card around it, so scrolling stays smooth.
    return RepaintBoundary(
      child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
          ),
          child: Image.asset(
            asset,
            key: ValueKey(asset),
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            // A missing frame must never break the screen it sits on.
            errorBuilder: (_, _, _) => Center(child: BrandMark(size: size * 0.7)),
          ),
        ),
      ),
      ),
    );
  }
}

/// Mitra with a speech bubble: the voice of the tour and of friendly tips.
class MitraSays extends StatelessWidget {
  const MitraSays({
    super.key,
    required this.title,
    this.message,
    this.mood = MitraMood.talk,
    this.size = 96,
    this.trailing,
  });

  final String title;
  final String? message;
  final MitraMood mood;
  final double size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Tap Mitra to hear the words, for anyone who would rather listen.
        GestureDetector(
          onTap: () => ReadAloud.toggle(ReadAloud.spoken([title, ?message])),
          child: Mitra(mood: mood, size: size),
        ),
        Expanded(
          child: CustomPaint(
            painter: _BubbleTail(color: scheme.surfaceContainerHigh),
            child: Container(
              margin: const EdgeInsets.only(left: 8, bottom: 14),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (message != null) ...[
                    const SizedBox(height: 4),
                    Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTail extends CustomPainter {
  _BubbleTail({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 30;
    final path = Path()
      ..moveTo(10, y)
      ..lineTo(0, y + 12)
      ..lineTo(18, y + 6)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTail old) => old.color != color;
}

/// A quiet "nothing here yet" for a list: Mitra, the line, and an optional
/// hint. Scrollable, so pull-to-refresh still works on an empty list.
class MitraEmpty extends StatelessWidget {
  const MitraEmpty(this.text, {super.key, this.hint, this.mood = MitraMood.idle});

  final String text;
  final String? hint;
  final MitraMood mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) => ListView(
        padding: EdgeInsets.zero,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight.isFinite ? c.maxHeight : 0),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => ReadAloud.toggle(ReadAloud.spoken([text, ?hint])),
                      child: Mitra(mood: mood, size: c.maxHeight.isFinite && c.maxHeight < 260 ? 72 : 112),
                    ),
                    const SizedBox(height: 8),
                    Text(text, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
                    if (hint != null) ...[
                      const SizedBox(height: 4),
                      Text(hint!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
