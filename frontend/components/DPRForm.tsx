"use client";

import { useState } from "react";

type DPRSubmission = { entry_date: string; work_summary: string; manpower_count: number };

export function DPRForm({ onSubmit }: { onSubmit: (data: DPRSubmission) => void }) {
  const [entryDate, setEntryDate] = useState("");
  const [workSummary, setWorkSummary] = useState("");
  const [manpowerCount, setManpowerCount] = useState("0");

  function handleSubmit() {
    onSubmit({
      entry_date: entryDate,
      work_summary: workSummary,
      manpower_count: Number(manpowerCount),
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Date
        <input
          type="date"
          value={entryDate}
          onChange={(e) => setEntryDate(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Work summary
        <textarea
          value={workSummary}
          onChange={(e) => setWorkSummary(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Manpower count
        <input
          type="number"
          value={manpowerCount}
          onChange={(e) => setManpowerCount(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
        Submit DPR
      </button>
    </div>
  );
}
