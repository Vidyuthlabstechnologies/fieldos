/// The navy page with the brand on top and a rounded sheet below it: the
/// look of every step where someone starts out (logging in, setting up a
/// company, choosing the subscription).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fieldos_mobile/core/brand.dart';

class BrandedSheetPage extends StatelessWidget {
  const BrandedSheetPage({super.key, required this.header, required this.sheet, this.trailing});

  /// True on short screens, where the header should use less height.
  static bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).height < 700;

  /// What sits on the navy part, above the sheet. Use white text, and
  /// [isCompact] to keep it short on small phones.
  final List<Widget> header;

  /// The sheet's content, laid out at most 420 wide.
  final Widget sheet;

  /// An optional button at the top right of the navy part, such as a menu.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // White status-bar icons on the navy top. Without this the phone keeps
    // whatever the last screen (or the launch theme) set, which can be dark
    // icons that disappear into the navy.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      backgroundColor: Brand.navy,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(children: [...header, const SizedBox(height: 28)]),
                    ),
                  ),
                  if (trailing != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: trailing!),
                    ),
                ],
              ),
            ),
            // Fills the rest of the screen, so a short form still reads as
            // one sheet down to the bottom edge, and scrolls when the
            // keyboard leaves less room.
            SliverFillRemaining(
              hasScrollBody: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomInset),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: sheet),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
