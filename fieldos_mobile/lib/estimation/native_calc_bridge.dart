/// Calls the on-device Python estimation_calc.py (bundled via Chaquopy,
/// see android/app/build.gradle.kts and android/app/src/main/python/) for
/// the precision-critical BOQ row calculations, instead of the Dart port in
/// estimation_calc.dart.
///
/// Every Decimal crosses the platform channel as a string -- never a
/// double -- so no precision is lost at this boundary. This exists to
/// eliminate the Python/Dart calc-engine divergence risk documented in
/// docs/CODEBASE_RECONNAISSANCE.md, by making the two platforms share the
/// literal same Python implementation for these functions rather than two
/// independently-maintained ports.
///
/// Android only (see docs/CHAQUOPY_FEASIBILITY.md) -- calling this on any
/// other platform will throw a MissingPluginException.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/services.dart';

class NativeCalcBridge {
  static const _channel = MethodChannel('com.predictera.fieldos_mobile/calc_engine');

  static Future<Decimal> measurementEntryQuantity({
    required String calculationType,
    Decimal? length,
    Decimal? width,
    Decimal? depth,
    required Decimal nos,
    bool isDeduction = false,
  }) async {
    final result = await _channel.invokeMethod<String>('measurementEntryQuantity', {
      'calculationType': calculationType,
      'length': length?.toString(),
      'width': width?.toString(),
      'depth': depth?.toString(),
      'nos': nos.toString(),
      'isDeduction': isDeduction,
    });
    return Decimal.parse(result!);
  }

  static Future<Decimal> steelEntryWeightKg({
    required Decimal barDiaMm,
    required Decimal nos,
    required Decimal lengthFt,
  }) async {
    final result = await _channel.invokeMethod<String>('steelEntryWeightKg', {
      'barDiaMm': barDiaMm.toString(),
      'nos': nos.toString(),
      'lengthFt': lengthFt.toString(),
    });
    return Decimal.parse(result!);
  }

  static Future<Decimal> costHeadBillingQuantity({
    required Decimal rawQuantity,
    required Decimal conversionFactor,
  }) async {
    final result = await _channel.invokeMethod<String>('costHeadBillingQuantity', {
      'rawQuantity': rawQuantity.toString(),
      'conversionFactor': conversionFactor.toString(),
    });
    return Decimal.parse(result!);
  }

  static Future<Decimal?> costHeadAmount({
    required Decimal billingQuantity,
    Decimal? ratePerUnit,
  }) async {
    final result = await _channel.invokeMethod<String?>('costHeadAmount', {
      'billingQuantity': billingQuantity.toString(),
      'ratePerUnit': ratePerUnit?.toString(),
    });
    return result == null ? null : Decimal.parse(result);
  }
}
