"use client";

import { useState } from "react";

type SteelEntrySubmission = {
  description: string;
  bar_dia_mm: string;
  nos: string;
  length_ft: string;
};

export function SteelEntryForm({ onSubmit }: { onSubmit: (data: SteelEntrySubmission) => void }) {
  const [description, setDescription] = useState("");
  const [barDiaMm, setBarDiaMm] = useState("");
  const [nos, setNos] = useState("");
  const [lengthFt, setLengthFt] = useState("");

  function handleSubmit() {
    onSubmit({ description, bar_dia_mm: barDiaMm, nos, length_ft: lengthFt });
  }

  return (
    <div className="flex flex-wrap items-end gap-2">
      <label className="flex flex-col gap-1 text-xs">
        Description
        <input
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="w-32 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Bar dia (mm)
        <input
          value={barDiaMm}
          onChange={(e) => setBarDiaMm(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Nos
        <input
          value={nos}
          onChange={(e) => setNos(e.target.value)}
          className="w-16 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Length (ft)
        <input
          value={lengthFt}
          onChange={(e) => setLengthFt(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-3 py-1.5 text-sm text-white">
        Add entry
      </button>
    </div>
  );
}
