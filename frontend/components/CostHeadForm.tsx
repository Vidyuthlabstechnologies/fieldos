"use client";

import { useState } from "react";

import type { CalculationType } from "@/lib/api";

type CostHeadSubmission = {
  name: string;
  calculation_type: CalculationType;
  raw_unit: string;
  billing_unit: string;
  rate_per_unit?: string;
};

const CALCULATION_TYPES: CalculationType[] = ["volume", "area", "steel_weight", "count"];

export function CostHeadForm({ onSubmit }: { onSubmit: (data: CostHeadSubmission) => void }) {
  const [name, setName] = useState("");
  const [calculationType, setCalculationType] = useState<CalculationType>("volume");
  const [rawUnit, setRawUnit] = useState("");
  const [billingUnit, setBillingUnit] = useState("");
  const [ratePerUnit, setRatePerUnit] = useState("");

  function handleSubmit() {
    onSubmit({
      name,
      calculation_type: calculationType,
      raw_unit: rawUnit,
      billing_unit: billingUnit,
      ...(ratePerUnit ? { rate_per_unit: ratePerUnit } : {}),
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Cost head name
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Calculation type
        <select
          value={calculationType}
          onChange={(e) => setCalculationType(e.target.value as CalculationType)}
          className="rounded border border-slate-300 p-2"
        >
          {CALCULATION_TYPES.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Raw unit
        <input
          value={rawUnit}
          onChange={(e) => setRawUnit(e.target.value)}
          placeholder="CFT / SFT / KG"
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Billing unit
        <input
          value={billingUnit}
          onChange={(e) => setBillingUnit(e.target.value)}
          placeholder="CUM / SFT / TONNES"
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Rate per unit
        <input
          value={ratePerUnit}
          onChange={(e) => setRatePerUnit(e.target.value)}
          placeholder="optional"
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
        Add cost head
      </button>
    </div>
  );
}
