"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { MobileMenuButton, Sidebar } from "@/components/Sidebar";
import { generateBOQPDF, type BOQ, type BOQLineOut, type Project } from "@/lib/pdf";
import { getBoq, getProject, listCostHeads, type CostHead } from "@/lib/api";

function EstimationDetail({ projectId, estimationId }: { projectId: string; estimationId: string }) {
  const [project, setProject] = useState<Project | null>(null);
  const [boq, setBoq] = useState<BOQ | null>(null);
  const [costHeads, setCostHeads] = useState<CostHead[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [generatingPdf, setGeneratingPdf] = useState(false);

  async function refresh() {
    const [p, b, c] = await Promise.all([
      getProject(projectId),
      getBoq(estimationId),
      listCostHeads(estimationId),
    ]);
    setProject(p);
    setBoq(b);
    setCostHeads(c);
  }

  useEffect(() => { refresh().catch(console.error); }, [projectId, estimationId]);

  function handlePdfExport() {
    if (!project || !boq) return;
    setGeneratingPdf(true);
    const doc = generateBOQPDF(project, boq);
    doc.save(`${project.name.replace(/[^a-z0-9-]/gi, "-")}-BOQ.pdf`);
    setGeneratingPdf(false);
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <header className="lg:hidden fixed top-0 left-0 right-0 z-20 h-14 bg-white border-b border-slate-200 flex items-center justify-between px-4">
        <MobileMenuButton isOpen={isOpen} onClick={() => setIsOpen(!isOpen)} />
        <span className="font-semibold text-slate-900">BOQ Detail</span>
        <div className="w-10" />
      </header>
      <main className="ml-56 flex-1 p-6 lg:pt-6 pt-20">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
            <div>
              <Link href={`/project/estimations?id=${projectId}`} className="text-sm text-slate-600 underline">
                ← Back to Estimations
              </Link>
              <h1 className="text-2xl font-bold mt-1">{project?.name}</h1>
            </div>
            <button
              onClick={handlePdfExport}
              disabled={generatingPdf || !boq}
              className="rounded bg-slate-900 px-4 py-2 text-white disabled:opacity-50"
            >
              {generatingPdf ? "Generating..." : "Export PDF"}
            </button>
          </div>

          {boq && (
            <div className="rounded border border-slate-200 bg-white overflow-hidden">
              <table className="w-full text-left text-sm" aria-label="BOQ">
                <thead className="border-b border-slate-200 bg-slate-50 text-xs text-slate-600">
                  <tr>
                    <th className="px-3 py-2">Description</th>
                    <th className="px-3 py-2">Unit</th>
                    <th className="px-3 py-2 text-right">Raw Qty</th>
                    <th className="px-3 py-2 text-right">Billing Qty</th>
                    <th className="px-3 py-2 text-right">Rate</th>
                    <th className="px-3 py-2 text-right">Amount</th>
                  </tr>
                </thead>
                <tbody>
                  {boq.lines.map((line, idx) => (
                    <tr key={idx} className="border-b border-slate-100 last:border-0">
                      <td className="px-3 py-2 font-medium">{line.name}</td>
                      <td className="px-3 py-2">{line.billing_unit}</td>
                      <td className="px-3 py-2 text-right">{parseFloat(line.raw_quantity).toFixed(3)}</td>
                      <td className="px-3 py-2 text-right">{parseFloat(line.billing_quantity).toFixed(3)}</td>
                      <td className="px-3 py-2 text-right">
                        {line.rate_per_unit ? `₹${parseFloat(line.rate_per_unit).toFixed(2)}` : "—"}
                      </td>
                      <td className="px-3 py-2 text-right font-mono">
                        {line.amount ? `₹${parseFloat(line.amount).toFixed(2)}` : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
                <tfoot className="bg-slate-50 text-sm font-semibold">
                  <tr>
                    <td className="px-3 py-2" colSpan={5} style={{ textAlign: "right" }}>Subtotal</td>
                    <td className="px-3 py-2 text-right">₹{parseFloat(boq.subtotal).toFixed(2)}</td>
                  </tr>
                  {boq.contractor_profit_percent && (
                    <tr>
                      <td className="px-3 py-2" colSpan={5} style={{ textAlign: "right" }}>
                        Contractor Profit ({boq.contractor_profit_percent}%)
                      </td>
                      <td className="px-3 py-2 text-right">₹{parseFloat(boq.contractor_profit_amount).toFixed(2)}</td>
                    </tr>
                  )}
                  <tr className="border-t-2 border-slate-200">
                    <td className="px-3 py-2" colSpan={5} style={{ textAlign: "right" }}>Grand Total</td>
                    <td className="px-3 py-2 text-right text-lg">₹{parseFloat(boq.grand_total).toFixed(2)}</td>
                  </tr>
                </tfoot>
              </table>
            </div>
          )}

          {costHeads.length > 0 && (
            <div className="mt-8">
              <h2 className="mb-3 text-lg font-semibold">Cost Heads</h2>
              <div className="rounded border border-slate-200 bg-white">
                <table className="w-full text-left text-sm" aria-label="Cost Heads">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs text-slate-600">
                    <tr>
                      <th className="px-3 py-2">Name</th>
                      <th className="px-3 py-2">Type</th>
                      <th className="px-3 py-2">Raw Unit</th>
                      <th className="px-3 py-2">Billing Unit</th>
                      <th className="px-3 py-2">Conversion</th>
                      <th className="px-3 py-2 text-right">Rate/Unit</th>
                    </tr>
                  </thead>
                  <tbody>
                    {costHeads.map((ch) => (
                      <tr key={ch.id} className="border-b border-slate-100 last:border-0">
                        <td className="px-3 py-2 font-medium">{ch.name}</td>
                        <td className="px-3 py-2">
                          <span className="rounded bg-slate-100 px-2 py-0.5 text-xs">{ch.calculation_type}</span>
                        </td>
                        <td className="px-3 py-2">{ch.raw_unit}</td>
                        <td className="px-3 py-2">{ch.billing_unit}</td>
                        <td className="px-3 py-2">{ch.conversion_factor}</td>
                        <td className="px-3 py-2 text-right">
                          {ch.rate_per_unit ? `₹${ch.rate_per_unit}` : "—"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function EstimationDetailGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  const estimationId = searchParams.get("estimationId");
  if (!projectId || !estimationId) {
    return <main className="mx-auto max-w-4xl p-6">No project/estimation selected.</main>;
  }
  return <EstimationDetail projectId={projectId} estimationId={estimationId} />;
}

export default function EstimationDetailPage() {
  return (
    <Suspense fallback={<main className="mx-auto max-w-4xl p-6">Loading...</main>}>
      <EstimationDetailGate />
    </Suspense>
  );
}