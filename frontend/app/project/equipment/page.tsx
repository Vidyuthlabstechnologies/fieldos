"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import { createEquipment, createEquipmentLog, listEquipment, listEquipmentLogs, updateEquipmentStatus, type Equipment, type EquipmentLog } from "@/lib/api";

const EQ_TYPES = ["crane", "excavator", "bulldozer", "roller", "mixer", "pump", "compressor", "generator", "truck", "other"];

function EquipmentPage({ projectId }: { projectId: string }) {
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [selectedEq, setSelectedEq] = useState<string | null>(null);
  const [logs, setLogs] = useState<EquipmentLog[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Add equipment form
  const [eqName, setEqName] = useState("");
  const [eqType, setEqType] = useState("other");
  const [eqModel, setEqModel] = useState("");
  const [eqReg, setEqReg] = useState("");
  const [eqRate, setEqRate] = useState("");

  // Add log form
  const [logDate, setLogDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [logType, setLogType] = useState("usage");
  const [logHours, setLogHours] = useState("");
  const [logDesc, setLogDesc] = useState("");
  const [logCost, setLogCost] = useState("");

  async function refresh() {
    setEquipment(await listEquipment(projectId));
  }

  useEffect(() => { refresh(); }, [projectId]);

  useEffect(() => {
    if (selectedEq) {
      listEquipmentLogs(selectedEq).then(setLogs).catch(console.error);
    }
  }, [selectedEq]);

  async function handleAddEquipment(e: React.FormEvent) {
    e.preventDefault();
    if (!eqName.trim()) return;
    setSubmitting(true);
    try {
      await createEquipment(projectId, { name: eqName, equipment_type: eqType, model: eqModel || undefined, registration_number: eqReg || undefined, daily_rate: eqRate || undefined });
      setEqName(""); setEqModel(""); setEqReg(""); setEqRate("");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleAddLog(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedEq) return;
    setSubmitting(true);
    try {
      await createEquipmentLog(selectedEq, { log_date: logDate, log_type: logType, hours_used: logHours || undefined, description: logDesc || undefined, cost: logCost || undefined });
      setLogHours(""); setLogDesc(""); setLogCost("");
      listEquipmentLogs(selectedEq).then(setLogs).catch(console.error);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleStatusChange(eqId: string, newStatus: string) {
    try {
      await updateEquipmentStatus(projectId, eqId, newStatus);
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to update status");
    }
  }

  const statusColor: Record<string, string> = {
    available: "bg-green-100 text-green-700",
    in_use: "bg-blue-100 text-blue-700",
    maintenance: "bg-amber-100 text-amber-700",
    breakdown: "bg-red-100 text-red-700",
  };

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Equipment & Machinery</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">&larr; Back</Link>
          </div>

          {error && <p className="mb-3 text-sm text-red-600">{error}</p>}

          {/* Add equipment form */}
          <form onSubmit={handleAddEquipment} className="mb-6 rounded border border-slate-200 bg-white p-4">
            <h2 className="mb-3 font-semibold">Add Equipment</h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
              <div className="sm:col-span-2">
                <label htmlFor="eq_name" className="mb-1 block text-xs text-slate-500">Name</label>
                <input id="eq_name" value={eqName} onChange={(e) => setEqName(e.target.value)} placeholder="e.g. Tata Hitachi EX200" className="w-full rounded border border-slate-300 p-2 text-sm" required />
              </div>
              <div>
                <label htmlFor="eq_type" className="mb-1 block text-xs text-slate-500">Type</label>
                <select id="eq_type" value={eqType} onChange={(e) => setEqType(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                  {EQ_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="eq_model" className="mb-1 block text-xs text-slate-500">Model</label>
                <input id="eq_model" value={eqModel} onChange={(e) => setEqModel(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
              </div>
              <div>
                <label htmlFor="eq_reg" className="mb-1 block text-xs text-slate-500">Registration No.</label>
                <input id="eq_reg" value={eqReg} onChange={(e) => setEqReg(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
              </div>
              <div>
                <label htmlFor="eq_rate" className="mb-1 block text-xs text-slate-500">Daily Rate (₹)</label>
                <input id="eq_rate" type="number" step="0.01" value={eqRate} onChange={(e) => setEqRate(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
              </div>
            </div>
            <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
              {submitting ? "Adding..." : "Add Equipment"}
            </button>
          </form>

          {/* Equipment list */}
          <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
            {equipment.map((eq) => (
              <div
                key={eq.id}
                className={`rounded border p-3 text-left transition ${selectedEq === eq.id ? "border-slate-900 bg-slate-50" : "border-slate-200 bg-white hover:border-slate-400"}`}
              >
                <div className="flex items-center justify-between mb-2">
                  <button
                    type="button"
                    onClick={() => setSelectedEq(eq.id)}
                    className="w-full text-left font-medium"
                  >
                    {eq.name}
                  </button>
                  <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[eq.status] || ""}`}>{eq.status}</span>
                </div>
                <div className="mt-1 text-xs text-slate-500 flex flex-wrap gap-2">
                  <span>{eq.equipment_type} {eq.model && `· ${eq.model}`} {eq.daily_rate && `· ₹${eq.daily_rate}/day`}</span>
                  <select
                    value={eq.status}
                    onChange={(e) => handleStatusChange(eq.id, e.target.value)}
                    className="rounded border border-slate-300 p-1 text-xs text-slate-700 bg-white"
                  >
                    <option value="available">Available</option>
                    <option value="in_use">In Use</option>
                    <option value="maintenance">Maintenance</option>
                    <option value="breakdown">Breakdown</option>
                  </select>
                </div>
              </div>
            ))}
          </div>

          {equipment.length === 0 && <p className="text-center text-sm text-slate-500">No equipment registered yet.</p>}

          {/* Log form (shown when equipment selected) */}
          {selectedEq && (
            <form onSubmit={handleAddLog} className="rounded border border-slate-200 bg-white p-4">
              <h2 className="mb-3 font-semibold">Add Log</h2>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                <div>
                  <label htmlFor="log_date" className="mb-1 block text-xs text-slate-500">Date</label>
                  <input id="log_date" type="date" value={logDate} onChange={(e) => setLogDate(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                </div>
                <div>
                  <label htmlFor="log_type" className="mb-1 block text-xs text-slate-500">Type</label>
                  <select id="log_type" value={logType} onChange={(e) => setLogType(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                    {["usage", "maintenance", "repair", "fuel", "inspection"].map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </div>
                <div>
                  <label htmlFor="log_hours" className="mb-1 block text-xs text-slate-500">Hours Used</label>
                  <input id="log_hours" type="number" step="0.5" value={logHours} onChange={(e) => setLogHours(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                </div>
                <div>
                  <label htmlFor="log_cost" className="mb-1 block text-xs text-slate-500">Cost (₹)</label>
                  <input id="log_cost" type="number" step="0.01" value={logCost} onChange={(e) => setLogCost(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                </div>
                <div className="sm:col-span-4">
                  <label htmlFor="log_desc" className="mb-1 block text-xs text-slate-500">Description</label>
                  <input id="log_desc" value={logDesc} onChange={(e) => setLogDesc(e.target.value)} placeholder="Optional" className="w-full rounded border border-slate-300 p-2 text-sm" />
                </div>
              </div>
              <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                {submitting ? "Adding..." : "Add Log"}
              </button>
            </form>
          )}

          {/* Logs */}
          {selectedEq && logs.length > 0 && (
            <div className="mt-4 rounded border border-slate-200 bg-white">
              <div className="border-b border-slate-200 px-4 py-2 text-sm font-semibold">Logs</div>
              <div className="divide-y divide-slate-100">
                {logs.map((log) => (
                  <div key={log.id} className="px-4 py-2 text-sm">
                    <div className="flex items-center gap-2">
                      <span className="rounded bg-slate-100 px-1.5 py-0.5 text-xs">{log.log_type}</span>
                      <span>{log.log_date}</span>
                      {log.hours_used && <span className="text-slate-500">{log.hours_used}h</span>}
                      {log.cost && <span className="text-slate-500">₹{log.cost}</span>}
                    </div>
                    {log.description && <p className="mt-1 text-xs text-slate-500">{log.description}</p>}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

export default function EquipmentPageRoute() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <EquipmentGate />
    </Suspense>
  );
}

function EquipmentGate() {
  const sp = useSearchParams();
  const pid = sp.get("id");
  if (!pid) return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  return <EquipmentPage projectId={pid} />;
}
