"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import {
  createWorker,
  getAttendanceSummary,
  listAttendance,
  listWorkers,
  markAttendance,
  type Attendance,
  type AttendanceSummary,
  type Worker,
} from "@/lib/api";

function WorkersPage({ projectId }: { projectId: string }) {
  const [workers, setWorkers] = useState<Worker[]>([]);
  const [attendance, setAttendance] = useState<Attendance[]>([]);
  const [summary, setSummary] = useState<AttendanceSummary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [attDate, setAttDate] = useState(() => new Date().toISOString().slice(0, 10));

  // Worker form
  const [wName, setWName] = useState("");
  const [wRole, setWRole] = useState("");
  const [wPhone, setWPhone] = useState("");
  const [wWage, setWWage] = useState("");

  async function refresh() {
    const [w, a, s] = await Promise.all([
      listWorkers(projectId),
      listAttendance(projectId, attDate),
      getAttendanceSummary(projectId),
    ]);
    setWorkers(w);
    setAttendance(a);
    setSummary(s);
  }

  useEffect(() => {
    refresh().catch(console.error);
  }, [projectId, attDate]);

  async function handleAddWorker(e: React.FormEvent) {
    e.preventDefault();
    if (!wName.trim() || !wRole.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createWorker(projectId, {
        name: wName,
        role: wRole,
        phone: wPhone || undefined,
        daily_wage: wWage || undefined,
      });
      setWName("");
      setWRole("");
      setWPhone("");
      setWWage("");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to add worker");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleAttendance(workerId: string, status: string) {
    try {
      await markAttendance(projectId, {
        worker_id: workerId,
        attendance_date: attDate,
        status,
      });
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to mark attendance");
    }
  }

  function getWorkerStatus(workerId: string): string {
    const rec = attendance.find((a) => a.worker_id === workerId);
    return rec?.status ?? "none";
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Labour Management</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">
              &larr; Back to project
            </Link>
          </div>

          {/* Attendance summary */}
          {summary && (
            <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-5">
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Total Workers</p>
                <p className="text-lg font-semibold">{summary.total_workers}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Present</p>
                <p className="text-lg font-semibold text-green-700">{summary.present}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Absent</p>
                <p className="text-lg font-semibold text-red-600">{summary.absent}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Half Day</p>
                <p className="text-lg font-semibold text-amber-600">{summary.half_day}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Wage Cost</p>
                <p className="text-lg font-semibold">₹{parseFloat(summary.total_wage_cost).toLocaleString()}</p>
              </div>
            </div>
          )}

          {/* Add worker form */}
          <form onSubmit={handleAddWorker} className="mb-8 rounded border border-slate-200 bg-white p-4">
            <h2 className="mb-3 font-semibold">Add Worker</h2>
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
              <div>
                <label htmlFor="w_name" className="mb-1 block text-xs text-slate-500">Name</label>
                <input
                  id="w_name"
                  value={wName}
                  onChange={(e) => setWName(e.target.value)}
                  placeholder="Worker name"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                  required
                />
              </div>
              <div>
                <label htmlFor="w_role" className="mb-1 block text-xs text-slate-500">Role / Skill</label>
                <input
                  id="w_role"
                  value={wRole}
                  onChange={(e) => setWRole(e.target.value)}
                  placeholder="e.g. Mason, Carpenter"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                  required
                />
              </div>
              <div>
                <label htmlFor="w_phone" className="mb-1 block text-xs text-slate-500">Phone</label>
                <input
                  id="w_phone"
                  value={wPhone}
                  onChange={(e) => setWPhone(e.target.value)}
                  placeholder="Optional"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                />
              </div>
              <div>
                <label htmlFor="w_wage" className="mb-1 block text-xs text-slate-500">Daily Wage (₹)</label>
                <input
                  id="w_wage"
                  type="number"
                  step="0.01"
                  value={wWage}
                  onChange={(e) => setWWage(e.target.value)}
                  placeholder="Optional"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                />
              </div>
            </div>
            <button
              type="submit"
              disabled={submitting}
              className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50"
            >
              {submitting ? "Adding..." : "Add Worker"}
            </button>
          </form>

          {/* Attendance section */}
          <div className="mb-6 rounded border border-slate-200 bg-white p-4">
            <div className="mb-3 flex items-center gap-4">
              <h2 className="font-semibold">Attendance</h2>
              <div>
                <label htmlFor="att_date" className="sr-only">Attendance date</label>
                <input
                  id="att_date"
                  type="date"
                  value={attDate}
                  onChange={(e) => setAttDate(e.target.value)}
                  className="rounded border border-slate-300 p-1.5 text-sm"
                />
              </div>
            </div>

            {workers.length === 0 ? (
              <p className="text-sm text-slate-500">No workers added yet.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm" aria-label="Worker attendance">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs text-slate-600">
                    <tr>
                      <th className="px-3 py-2">Name</th>
                      <th className="px-3 py-2">Role</th>
                      <th className="px-3 py-2">Wage</th>
                      <th className="px-3 py-2 text-center">Present</th>
                      <th className="px-3 py-2 text-center">Absent</th>
                      <th className="px-3 py-2 text-center">Half Day</th>
                      <th className="px-3 py-2">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {workers.map((w) => {
                      const status = getWorkerStatus(w.id);
                      return (
                        <tr key={w.id} className="border-b border-slate-100 last:border-0">
                          <td className="px-3 py-2 font-medium">{w.name}</td>
                          <td className="px-3 py-2">{w.role}</td>
                          <td className="px-3 py-2">
                            {w.daily_wage ? `₹${w.daily_wage}` : "\u2014"}
                          </td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => handleAttendance(w.id, "present")}
                              className={`rounded px-2 py-1 text-xs ${
                                status === "present"
                                  ? "bg-green-600 text-white"
                                  : "bg-slate-100 text-slate-600 hover:bg-green-100"
                              }`}
                            >
                              P
                            </button>
                          </td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => handleAttendance(w.id, "absent")}
                              className={`rounded px-2 py-1 text-xs ${
                                status === "absent"
                                  ? "bg-red-600 text-white"
                                  : "bg-slate-100 text-slate-600 hover:bg-red-100"
                              }`}
                            >
                              A
                            </button>
                          </td>
                          <td className="px-3 py-2 text-center">
                            <button
                              type="button"
                              onClick={() => handleAttendance(w.id, "half_day")}
                              className={`rounded px-2 py-1 text-xs ${
                                status === "half_day"
                                  ? "bg-amber-500 text-white"
                                  : "bg-slate-100 text-slate-600 hover:bg-amber-100"
                              }`}
                            >
                              H
                            </button>
                          </td>
                          <td className="px-3 py-2">
                            <span
                              className={`rounded px-2 py-0.5 text-xs ${
                                status === "present"
                                  ? "bg-green-100 text-green-800"
                                  : status === "absent"
                                    ? "bg-red-100 text-red-800"
                                    : status === "half_day"
                                      ? "bg-amber-100 text-amber-800"
                                      : "bg-slate-100 text-slate-500"
                              }`}
                            >
                              {status === "none" ? "Not marked" : status}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

export default function LabourPage() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <LabourGate />
    </Suspense>
  );
}

function LabourGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) {
    return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  }
  return <WorkersPage projectId={projectId} />;
}
