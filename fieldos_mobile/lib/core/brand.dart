/// The FieldOS brand: colours, the hard-hat mark and the wordmark.
///
/// The same navy and safety amber as the launcher icon and the Play Store
/// graphics (tools/make_icons.py draws those from these exact values), so
/// the app, its icon and its store page read as one product.
library;

import 'package:flutter/material.dart';

class Brand {
  Brand._();

  /// Deep site-office navy: app bars, primary buttons, text on amber.
  static const navy = Color(0xFF112A4A);
  static const navyDeep = Color(0xFF0B1D35);
  static const navySoft = Color(0xFF2B4A73);

  /// Safety-helmet amber: the hat, the main action on every screen.
  static const amber = Color(0xFFF5A524);
  static const amberDark = Color(0xFFD6860E);
  static const amberSoft = Color(0xFFFFF1D6);

  /// Light page background, a touch cooler than white so cards stand out.
  static const paper = Color(0xFFF4F6F9);
  static const ink = Color(0xFF13233A);
  static const inkMuted = Color(0xFF5B6B80);
  static const line = Color(0xFFDDE3EB);

  /// Status colours, chosen to stay readable in bright sunlight.
  static const ok = Color(0xFF1E8E5A);
  static const okSoft = Color(0xFFE3F4EB);
  static const warn = Color(0xFFB86E00);
  static const warnSoft = Color(0xFFFFF1D6);
  static const danger = Color(0xFFC62828);
  static const dangerSoft = Color(0xFFFDECEC);

  static const fontFamily = 'Inter';

  static const supportEmail = 'info@mldynamic.com';
  static const companyName = 'ML Dynamic Solutions Private Limited';

  /// Where the published privacy policy lives. Set at build time
  /// (--dart-define=PRIVACY_POLICY_URL=...) once it is published, so a new
  /// URL never needs a code change. Empty: the app shows the policy text
  /// it carries itself.
  static const privacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');
}

/// The hard hat from the app icon, drawn as vectors so it is sharp at any
/// size. [onDark] adds the white site-level line under the brim, as on the
/// icon; on light backgrounds the line is navy.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FieldOS',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _HardHatPainter(lineColor: onDark ? Colors.white : Brand.navy)),
      ),
    );
  }
}

/// The mark on its navy tile, like the launcher icon.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Brand.navy,
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.25), blurRadius: size * 0.25, offset: Offset(0, size * 0.08))],
      ),
      alignment: Alignment.center,
      child: BrandMark(size: size * 0.82, onDark: true),
    );
  }
}

/// The navy launch screen with the hat, shown while the app reads the saved
/// session (it matches the native splash, so there is no jump).
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Brand.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 132, onDark: true),
            SizedBox(height: 12),
            Wordmark(fontSize: 30, onDark: true),
          ],
        ),
      ),
    );
  }
}

/// "FieldOS" set in the brand font, with "OS" in amber.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 28, this.onDark = false});

  final double fontSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: Brand.fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.1,
      color: onDark ? Colors.white : Brand.navy,
    );
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Field', style: base),
        TextSpan(text: 'OS', style: base.copyWith(color: Brand.amber)),
      ]),
      semanticsLabel: 'FieldOS',
    );
  }
}

class _HardHatPainter extends CustomPainter {
  _HardHatPainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Same proportions as tools/make_icons.py's hard_hat(size, 0.72).
    final s = size.width;
    final cx = s / 2, cy = s * 0.56;
    final w = s * 0.72;
    final r = w * 0.36;
    final amber = Paint()..color = Brand.amber;
    final amberDark = Paint()..color = Brand.amberDark;

    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), 3.14159265, 3.14159265, true, amber);
    final rw = r * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(cx - rw / 2, cy - r * 0.97, cx + rw / 2, cy), Radius.circular(rw / 2)),
      amberDark,
    );
    final bh = r * 0.16;
    canvas.drawRect(Rect.fromLTRB(cx - r, cy - bh, cx + r, cy), amberDark);
    final bw = w / 2, brh = r * 0.26;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(cx - bw, cy, cx + bw, cy + brh), Radius.circular(brh / 2)),
      amber,
    );
    final lw = w * 0.34, lh = r * 0.1, gap = r * 0.34;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - lw, cy + brh + gap, cx + lw, cy + brh + gap + lh),
        Radius.circular(lh / 2),
      ),
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(_HardHatPainter old) => old.lineColor != lineColor;
}
