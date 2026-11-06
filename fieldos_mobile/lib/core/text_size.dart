/// Larger text inside FieldOS, on top of the phone's own font size, for
/// people who read the screen in sunlight or without their glasses.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/providers.dart';

const textSizeKey = 'text_size';

/// The choices, as a multiple of the phone's own size.
const textSizes = {'normal': 1.0, 'large': 1.15, 'larger': 1.3};

class TextSizeController extends StateNotifier<String> {
  TextSizeController(this._ref) : super('normal') {
    _load();
  }
  final Ref _ref;

  Future<void> _load() async {
    final saved = await _ref.read(appDatabaseProvider).settingsDao.get(textSizeKey);
    if (mounted && textSizes.containsKey(saved)) state = saved!;
  }

  Future<void> choose(String size) async {
    if (!textSizes.containsKey(size)) return;
    state = size;
    await _ref.read(appDatabaseProvider).settingsDao.set(textSizeKey, size);
  }
}

final textSizeProvider = StateNotifierProvider<TextSizeController, String>((ref) => TextSizeController(ref));

/// The phone's scale times ours, capped so layouts still fit.
TextScaler combinedTextScaler(TextScaler phone, String size) {
  final factor = textSizes[size] ?? 1.0;
  if (factor == 1.0) return phone;
  final base = phone.scale(16) / 16;
  return TextScaler.linear((base * factor).clamp(1.0, 2.0));
}
