"use client";

import { useEffect, useState } from "react";

type DPRSubmission = { entry_date: string; work_summary: string; manpower_count: number };
type DPRPrefill = { work_summary: string; manpower_count: number };

export function DPRForm({
  onSubmit,
  prefill,
}: {
  onSubmit: (data: DPRSubmission) => void | Promise<void>;
  prefill?: DPRPrefill;
}) {
  const [entryDate, setEntryDate] = useState("");
  const [workSummary, setWorkSummary] = useState("");
  const [manpowerCount, setManpowerCount] = useState("0");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (prefill) {
      setWorkSummary(prefill.work_summary);
      setManpowerCount(String(prefill.manpower_count));
    }
  }, [prefill]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!entryDate || !workSummary.trim()) {
      setError("Date and work summary are required");
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await onSubmit({
        entry_date: entryDate,
        work_summary: workSummary,
        manpower_count: Number(manpowerCount) || 0,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to submit DPR");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Date
        <input
          type="date"
          required
          value={entryDate}
          onChange={(e) => setEntryDate(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Work summary
        <textarea
          required
          value={workSummary}
          onChange={(e) => setWorkSummary(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Manpower count
        <input
          type="number"
          min="0"
          value={manpowerCount}
          onChange={(e) => setManpowerCount(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button
        type="submit"
        disabled={submitting}
        className="rounded bg-slate-900 px-4 py-2 text-white disabled:opacity-50"
      >
        {submitting ? "Submitting..." : "Submit DPR"}
      </button>
    </form>
  );
}
