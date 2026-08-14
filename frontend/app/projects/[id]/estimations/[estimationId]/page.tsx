"use client";

import { use, useEffect, useState } from "react";

import { BOQTable } from "@/components/BOQTable";
import { CostHeadForm } from "@/components/CostHeadForm";
import { MeasurementEntryForm } from "@/components/MeasurementEntryForm";
import { SteelEntryForm } from "@/components/SteelEntryForm";
import {
  createCostHead,
  createMeasurementEntry,
  createSteelEntry,
  getBoq,
  listCostHeads,
  type BOQ,
  type CostHead,
} from "@/lib/api";

export default function EstimationDetailPage({
  params,
}: {
  params: Promise<{ id: string; estimationId: string }>;
}) {
  const { estimationId } = use(params);
  const [costHeads, setCostHeads] = useState<CostHead[]>([]);
  const [boq, setBoq] = useState<BOQ | null>(null);

  async function refresh() {
    const [heads, nextBoq] = await Promise.all([listCostHeads(estimationId), getBoq(estimationId)]);
    setCostHeads(heads);
    setBoq(nextBoq);
  }

  useEffect(() => {
    refresh().catch(console.error);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [estimationId]);

  async function handleAddCostHead(data: Parameters<typeof createCostHead>[1]) {
    await createCostHead(estimationId, data);
    refresh();
  }

  return (
    <main className="mx-auto grid max-w-4xl gap-8 p-6">
      <section>
        <h2 className="mb-2 text-lg font-semibold">Add Cost Head</h2>
        <CostHeadForm onSubmit={handleAddCostHead} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">Cost Heads</h2>
        <div className="flex flex-col gap-4">
          {costHeads.map((costHead) => (
            <div key={costHead.id} className="rounded border border-slate-200 p-3">
              <div className="mb-2 font-medium">
                {costHead.name}{" "}
                <span className="text-xs uppercase text-slate-500">({costHead.calculation_type})</span>
              </div>
              {costHead.calculation_type === "steel_weight" ? (
                <SteelEntryForm
                  onSubmit={async (data) => {
                    await createSteelEntry(costHead.id, data);
                    refresh();
                  }}
                />
              ) : (
                <MeasurementEntryForm
                  onSubmit={async (data) => {
                    await createMeasurementEntry(costHead.id, data);
                    refresh();
                  }}
                />
              )}
            </div>
          ))}
        </div>
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">BOQ</h2>
        {boq && <BOQTable boq={boq} />}
      </section>
    </main>
  );
}
