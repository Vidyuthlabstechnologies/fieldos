"use client";

import { useState } from "react";

type SteelEntrySubmission = {
  description: string;
  bar_dia_mm: string;
  nos: string;
  length_ft: string;
};

export function SteelEntryForm({ onSubmit }: { onSubmit: (data: SteelEntrySubmission) => void | Promise<void> }) {
  const [description, setDescription] = useState("");
  const [barDiaMm, setBarDiaMm] = useState("");
  const [nos, setNos] = useState("");
  const [lengthFt, setLengthFt] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!description.trim() || !barDiaMm || !nos || !lengthFt) {
      setError("All fields are required");
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await onSubmit({ description, bar_dia_mm: barDiaMm, nos, length_ft: lengthFt });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to add entry");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-wrap items-end gap-2">
      <label className="flex flex-col gap-1 text-xs">
        Description
        <input
          required
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="w-32 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Bar dia (mm)
        <input
          required
          value={barDiaMm}
          onChange={(e) => setBarDiaMm(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Nos
        <input
          required
          value={nos}
          onChange={(e) => setNos(e.target.value)}
          className="w-16 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Length (ft)
        <input
          required
          value={lengthFt}
          onChange={(e) => setLengthFt(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      {error && <p className="text-xs text-red-600">{error}</p>}
      <button type="submit" disabled={submitting} className="rounded bg-slate-900 px-3 py-1.5 text-sm text-white disabled:opacity-50">
        {submitting ? "Adding..." : "Add entry"}
      </button>
    </form>
  );
}
