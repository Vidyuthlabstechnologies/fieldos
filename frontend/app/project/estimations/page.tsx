"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";

import { createEstimation, listEstimations, type Estimation } from "@/lib/api";

function EstimationsList({ projectId }: { projectId: string }) {
  const [estimations, setEstimations] = useState<Estimation[]>([]);
  const [newName, setNewName] = useState("");
  const [newProfitPercent, setNewProfitPercent] = useState("");

  async function refresh() {
    setEstimations(await listEstimations(projectId));
  }

  useEffect(() => {
    refresh().catch(console.error);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId]);

  async function handleCreate() {
    if (!newName.trim()) return;
    await createEstimation(projectId, {
      name: newName,
      ...(newProfitPercent ? { contractor_profit_percent: newProfitPercent } : {}),
    });
    setNewName("");
    setNewProfitPercent("");
    refresh();
  }

  return (
    <main className="mx-auto max-w-2xl p-6">
      <h1 className="mb-4 text-2xl font-bold">Estimations (BOQ)</h1>

      <div className="mb-6 flex flex-wrap items-end gap-2">
        <label className="flex flex-col gap-1 text-sm">
          Name
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            className="rounded border border-slate-300 p-2"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Contractor profit %
          <input
            value={newProfitPercent}
            onChange={(e) => setNewProfitPercent(e.target.value)}
            placeholder="optional"
            className="w-28 rounded border border-slate-300 p-2"
          />
        </label>
        <button onClick={handleCreate} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
          New estimation
        </button>
      </div>

      <ul className="flex flex-col gap-2">
        {estimations.map((e) => (
          <li key={e.id}>
            <a
              href={`/project/estimations/detail?id=${projectId}&estimationId=${e.id}`}
              className="block rounded border border-slate-200 p-3 hover:border-slate-400"
            >
              <div className="font-semibold">{e.name}</div>
              <div className="text-xs uppercase text-slate-500">{e.status}</div>
            </a>
          </li>
        ))}
      </ul>
    </main>
  );
}

function EstimationsGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) {
    return <main className="mx-auto max-w-2xl p-6">No project selected.</main>;
  }
  return <EstimationsList projectId={projectId} />;
}

export default function EstimationsPage() {
  return (
    <Suspense fallback={<main className="mx-auto max-w-2xl p-6">Loading...</main>}>
      <EstimationsGate />
    </Suspense>
  );
}
