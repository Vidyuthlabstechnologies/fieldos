"use client";

import { use, useEffect, useState } from "react";

import { DashboardWidget } from "@/components/DashboardWidget";
import { DPRForm } from "@/components/DPRForm";
import { SiteFeed } from "@/components/SiteFeed";
import { TaskList } from "@/components/TaskList";
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
  type FeedItem,
  type Project,
  type Task,
} from "@/lib/api";

export default function ProjectDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const projectId = use(params).id;
  const [project, setProject] = useState<Project | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState("");
  const [exporting, setExporting] = useState(false);

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
    await createTask(projectId, newTaskTitle);
    setNewTaskTitle("");
    refresh();
  }

  async function handleStatusChange(taskId: string, status: Task["status"]) {
    await updateTaskStatus(projectId, taskId, status);
    refresh();
  }

  async function handleDprSubmit(data: { entry_date: string; work_summary: string; manpower_count: number }) {
    await createDprEntry(projectId, data);
    refresh();
  }

  return (
    <main className="mx-auto grid max-w-4xl gap-8 p-6">
      {dashboard && <DashboardWidget dashboard={dashboard} />}

      <div className="flex items-center justify-between">
        <a href={`/projects/${projectId}/estimations`} className="text-sm font-medium text-slate-700 underline">
          Estimations (BOQ) →
        </a>
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
        <TaskList tasks={tasks} onStatusChange={handleStatusChange} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">Daily Progress Report</h2>
        <DPRForm onSubmit={handleDprSubmit} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">Site Feed</h2>
        <SiteFeed items={feed} />
      </section>
    </main>
  );
}
