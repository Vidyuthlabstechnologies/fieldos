"use client";

import { useState } from "react";

type MeasurementEntrySubmission = {
  description: string;
  length: string;
  width: string;
  depth: string;
  nos: string;
  is_deduction: boolean;
};

export function MeasurementEntryForm({
  onSubmit,
}: {
  onSubmit: (data: MeasurementEntrySubmission) => void | Promise<void>;
}) {
  const [description, setDescription] = useState("");
  const [length, setLength] = useState("");
  const [width, setWidth] = useState("");
  const [depth, setDepth] = useState("");
  const [nos, setNos] = useState("1");
  const [isDeduction, setIsDeduction] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!description.trim()) {
      setError("Description is required");
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await onSubmit({ description, length, width, depth, nos, is_deduction: isDeduction });
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
        Length
        <input
          value={length}
          onChange={(e) => setLength(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Width
        <input
          value={width}
          onChange={(e) => setWidth(e.target.value)}
          className="w-20 rounded border border-slate-300 p-1.5 text-sm"
        />
      </label>
      <label className="flex flex-col gap-1 text-xs">
        Depth
        <input
          value={depth}
          onChange={(e) => setDepth(e.target.value)}
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
      <label className="flex items-center gap-1 pb-2 text-xs">
        <input
          type="checkbox"
          checked={isDeduction}
          onChange={(e) => setIsDeduction(e.target.checked)}
        />
        Deduction
      </label>
      {error && <p className="text-xs text-red-600">{error}</p>}
      <button type="submit" disabled={submitting} className="rounded bg-slate-900 px-3 py-1.5 text-sm text-white disabled:opacity-50">
        {submitting ? "Adding..." : "Add entry"}
      </button>
    </form>
  );
}
