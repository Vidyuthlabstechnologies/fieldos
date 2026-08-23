package com.predictera.fieldos_mobile

import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter to the pure, dependency-free `estimation_calc.py` running
 * on-device via Chaquopy -- see docs/CHAQUOPY_FEASIBILITY.md for why this is
 * scoped to just the calc engine (not the full fieldos/ FastAPI backend).
 */
class MainActivity : FlutterActivity() {
    private val calcEngineChannel = "com.predictera.fieldos_mobile/calc_engine"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(applicationContext))
        }
        val calcBridge: PyObject = Python.getInstance().getModule("calc_bridge")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, calcEngineChannel).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "measurementEntryQuantity" -> {
                        val r = calcBridge.callAttr(
                            "measurement_entry_quantity",
                            call.argument<String>("calculationType"),
                            call.argument<String>("length"),
                            call.argument<String>("width"),
                            call.argument<String>("depth"),
                            call.argument<String>("nos"),
                            call.argument<Boolean>("isDeduction") ?: false,
                        )
                        result.success(r.toString())
                    }
                    "steelEntryWeightKg" -> {
                        val r = calcBridge.callAttr(
                            "steel_entry_weight_kg",
                            call.argument<String>("barDiaMm"),
                            call.argument<String>("nos"),
                            call.argument<String>("lengthFt"),
                        )
                        result.success(r.toString())
                    }
                    "costHeadBillingQuantity" -> {
                        val r = calcBridge.callAttr(
                            "cost_head_billing_quantity",
                            call.argument<String>("rawQuantity"),
                            call.argument<String>("conversionFactor"),
                        )
                        result.success(r.toString())
                    }
                    "costHeadAmount" -> {
                        // callAttr with a raw Kotlin null arg (the "no rate
                        // set yet" case) returns a null PyObject reference
                        // itself rather than a PyObject wrapping Python
                        // None -- guard before calling .toJava on it.
                        val ratePerUnit = call.argument<String>("ratePerUnit")
                        val r: PyObject? = if (ratePerUnit == null) {
                            null
                        } else {
                            calcBridge.callAttr(
                                "cost_head_amount",
                                call.argument<String>("billingQuantity"),
                                ratePerUnit,
                            )
                        }
                        result.success(r?.toJava(String::class.java))
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("CALC_ENGINE_ERROR", e.message, null)
            }
        }
    }
}
