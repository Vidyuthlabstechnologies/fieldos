"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { DashboardWidget } from "@/components/DashboardWidget";
import { DPRForm } from "@/components/DPRForm";
import { MobileMenuButton, Sidebar } from "@/components/Sidebar";
import { SiteFeed } from "@/components/SiteFeed";
import { TaskList } from "@/components/TaskList";
import { VoiceDPRRecorder } from "@/components/VoiceDPRRecorder";
import {
  createDprEntry,
  createTask,
  exportProject,
  getDashboard,
  getProject,
  getSiteFeed,
  listTasks,
  updateTaskStatus,
  type Dashboard,
  type DPRVoiceDraft,
  type FeedItem,
  type Project,
  type Task,
} from "@/lib/api";

function ProjectDetail({ projectId }: { projectId: string }) {
  const [project, setProject] = useState<Project | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState("");
  const [exporting, setExporting] = useState(false);
  const [voiceDraft, setVoiceDraft] = useState<DPRVoiceDraft | null>(null);
  const [taskError, setTaskError] = useState<string | null>(null);
  const [dprError, setDprError] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState(false);

  async function refresh() {
    const [p, t, f, d] = await Promise.all([
      getProject(projectId),
      listTasks(projectId),
      getSiteFeed(projectId),
      getDashboard(projectId),
    ]);
    setProject(p);
    setTasks(t);
    setFeed(f);
    setDashboard(d);
  }

  async function handleExport() {
    setExporting(true);
    try {
      const data = await exportProject(projectId);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${(project?.name ?? "project").replace(/[^a-z0-9-]+/gi, "-")}.fieldos-export.json`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  }

  useEffect(() => {
    refresh().catch(console.error);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId]);

  async function handleAddTask() {
    if (!newTaskTitle.trim()) return;
    setTaskError(null);
    try {
      await createTask(projectId, newTaskTitle);
      setNewTaskTitle("");
      refresh();
    } catch (err) {
      setTaskError(err instanceof Error ? err.message : "Failed to add task");
    }
  }

  async function handleStatusChange(taskId: string, status: Task["status"]) {
    await updateTaskStatus(projectId, taskId, status);
    refresh();
  }

  async function handleDprSubmit(data: { entry_date: string; work_summary: string; manpower_count: number }) {
    setDprError(null);
    try {
      await createDprEntry(projectId, data);
      setVoiceDraft(null);
      refresh();
    } catch (err) {
      setDprError(err instanceof Error ? err.message : "Failed to submit DPR");
      throw err;
    }
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <header className="lg:hidden fixed top-0 left-0 right-0 z-20 h-14 bg-white border-b border-slate-200 flex items-center justify-between px-4">
        <MobileMenuButton isOpen={isOpen} onClick={() => setIsOpen(!isOpen)} />
        <span className="font-semibold text-slate-900">FieldOS</span>
        <div className="w-10" />
      </header>
      <main className="ml-56 flex-1 p-6 lg:pt-6 pt-20">
        <div className="mx-auto grid max-w-4xl gap-8">
          {dashboard && <DashboardWidget dashboard={dashboard} />}

          <div className="flex items-center justify-between">
            <Link href={`/project/estimations?id=${projectId}`} className="text-sm font-medium text-slate-700 underline">
              Estimations (BOQ) &rarr;
            </Link>
            <button
              onClick={handleExport}
              disabled={exporting}
              type="button"
              className="rounded border border-slate-300 px-3 py-1.5 text-sm disabled:opacity-50"
            >
              {exporting ? "Exporting..." : "Export project"}
            </button>
          </div>

          <section>
            <h2 className="mb-2 text-lg font-semibold">Tasks</h2>
            <div className="mb-3 flex gap-2">
              <input
                value={newTaskTitle}
                onChange={(e) => setNewTaskTitle(e.target.value)}
                placeholder="New task title"
                className="flex-1 rounded border border-slate-300 p-2"
              />
              <button onClick={handleAddTask} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
                Add
              </button>
            </div>
            {taskError && <p className="mb-2 text-sm text-red-600">{taskError}</p>}
            <TaskList tasks={tasks} onStatusChange={handleStatusChange} />
          </section>

          <section>
            <h2 className="mb-2 text-lg font-semibold">Daily Progress Report</h2>
            <div className="mb-3">
              <VoiceDPRRecorder projectId={projectId} onDraft={setVoiceDraft} />
              {voiceDraft && (
                <p className="mt-2 text-xs text-slate-500">
                  Transcript: &ldquo;{voiceDraft.transcript}&rdquo; &mdash; review the fields below before submitting.
                </p>
              )}
            </div>
            {dprError && <p className="mb-2 text-sm text-red-600">{dprError}</p>}
            <DPRForm onSubmit={handleDprSubmit} prefill={voiceDraft ?? undefined} />
          </section>

          <section>
            <h2 className="mb-2 text-lg font-semibold">Site Feed</h2>
            <SiteFeed items={feed} />
          </section>
        </div>
      </main>
    </div>
  );
}

function ProjectDetailGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) {
    return <main className="mx-auto max-w-4xl p-6">No project selected.</main>;
  }
  return <ProjectDetail projectId={projectId} />;
}

export default function ProjectDetailPage() {
  return (
    <Suspense fallback={<main className="mx-auto max-w-4xl p-6">Loading...</main>}>
      <ProjectDetailGate />
    </Suspense>
  );
}
