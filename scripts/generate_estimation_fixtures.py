"""Generates estimation_fixtures.json: randomized BOQ cases computed by the
DESKTOP Python engine (fieldos/estimation_calc.py), the ground truth for the
mobile Dart port's differential test (test/estimation_differential_test.dart).

Quantities are emitted as strings so Decimal precision survives JSON.
Reproducible: fixed seed. Re-run only when the desktop engine changes:

    .venv\\Scripts\\python.exe scripts/generate_estimation_fixtures.py
"""

import json
import random
import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fieldos.estimation_calc import build_boq, steel_entry_weight_kg, measurement_entry_quantity  # noqa: E402


def d(value: Decimal | None) -> str | None:
    return None if value is None else str(value)


def rand_decimal(rng: random.Random, lo: float, hi: float, places: int) -> Decimal:
    return Decimal(str(round(rng.uniform(lo, hi), places)))


def main() -> None:
    rng = random.Random(20260824)
    calc_types = ["volume", "area", "count", "steel_weight"]

    cases = []
    for _ in range(120):
        heads = []
        for h in range(rng.randint(1, 5)):
            ctype = rng.choice(calc_types)
            measurements = []
            steel = []
            if ctype == "steel_weight":
                for _ in range(rng.randint(1, 6)):
                    steel.append({
                        "bar_dia_mm": d(rand_decimal(rng, 6, 32, 1)),
                        "nos": d(rand_decimal(rng, 1, 200, 0)),
                        "length_ft": d(rand_decimal(rng, 1, 40, 2)),
                    })
            else:
                for _ in range(rng.randint(1, 6)):
                    measurements.append({
                        "length": d(rand_decimal(rng, 0, 500, 3)),
                        "width": d(rand_decimal(rng, 0, 500, 3)),
                        "depth": d(None if rng.random() < 0.4 and ctype != "volume" else rand_decimal(rng, 0, 30, 3)),
                        "nos": d(rand_decimal(rng, 1, 50, 2)),
                        "is_deduction": rng.random() < 0.25,
                    })
            heads.append({
                "id": f"head-{h}",
                "name": f"Head {h}",
                "calculation_type": ctype,
                "billing_unit": rng.choice(["cft", "sqm", "nos", "kg"]),
                "conversion_factor": d(rand_decimal(rng, 0.01, 10, 6)),
                "rate_per_unit": d(None if rng.random() < 0.15 else rand_decimal(rng, 10, 9000, 2)),
                "measurements": measurements,
                "steel": steel,
            })

        profit = d(None if rng.random() < 0.3 else rand_decimal(rng, 0, 25, 2))

        py_heads = []
        py_standalone = []
        for head in heads:
            ch = type("CH", (), {})()
            ch.id = head["id"]
            ch.name = head["name"]
            ch.calculation_type = head["calculation_type"]
            ch.billing_unit = head["billing_unit"]
            ch.conversion_factor = Decimal(head["conversion_factor"])
            ch.rate_per_unit = None if head["rate_per_unit"] is None else Decimal(head["rate_per_unit"])
            ms = [
                type("M", (), {})() for _ in head["measurements"]
            ]
            for m, src in zip(ms, head["measurements"]):
                m.length = None if src["length"] is None else Decimal(src["length"])
                m.width = None if src["width"] is None else Decimal(src["width"])
                m.depth = None if src["depth"] is None else Decimal(src["depth"])
                m.nos = Decimal(src["nos"])
                m.is_deduction = src["is_deduction"]
            ss = [type("S", (), {})() for _ in head["steel"]]
            for s, src in zip(ss, head["steel"]):
                s.bar_dia_mm = Decimal(src["bar_dia_mm"])
                s.nos = Decimal(src["nos"])
                s.length_ft = Decimal(src["length_ft"])
            py_heads.append((ch, ms, ss))
            for m, s in zip(ms, [None] * len(ms)):
                pass
            # standalone per-entry expectations for a subset
            if head["calculation_type"] != "steel_weight" and head["measurements"]:
                src = head["measurements"][0]
                qty = measurement_entry_quantity(
                    head["calculation_type"],
                    None if src["length"] is None else Decimal(src["length"]),
                    None if src["width"] is None else Decimal(src["width"]),
                    None if src["depth"] is None else Decimal(src["depth"]),
                    Decimal(src["nos"]),
                    src["is_deduction"],
                )
                py_standalone.append({"case": "measurement", "input": src, "ctype": head["calculation_type"], "expect": d(qty)})
            for s_src in head["steel"]:
                w = steel_entry_weight_kg(Decimal(s_src["bar_dia_mm"]), Decimal(s_src["nos"]), Decimal(s_src["length_ft"]))
                py_standalone.append({"case": "steel", "input": s_src, "expect": d(w)})

        profit_dec = None if profit is None else Decimal(profit)
        result = build_boq(py_heads, contractor_profit_percent=profit_dec)

        cases.append({
            "heads": heads,
            "contractor_profit_percent": profit,
            "standalone": py_standalone,
            "expect": {
                "lines": [
                    {
                        "cost_head_id": ln.cost_head_id,
                        "raw_quantity": d(ln.raw_quantity),
                        "billing_quantity": d(ln.billing_quantity),
                        "amount": d(ln.amount),
                    }
                    for ln in result.lines
                ],
                "subtotal": d(result.subtotal),
                "contractor_profit_amount": d(result.contractor_profit_amount),
                "grand_total": d(result.grand_total),
            },
        })

    out = Path(__file__).resolve().parents[1] / "fieldos_mobile" / "test" / "fixtures" / "estimation_fixtures.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"seed": 20260824, "cases": cases}, indent=1))
    print(f"wrote {out} with {len(cases)} cases")


if __name__ == "__main__":
    main()
