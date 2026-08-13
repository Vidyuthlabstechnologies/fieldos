import { supabase } from "./supabaseClient";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

async function authHeader(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = {
    "Content-Type": "application/json",
    ...(await authHeader()),
    ...(options.headers ?? {}),
  };
  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json() as Promise<T>;
}

export type Project = {
  id: string;
  company_id: string;
  name: string;
  client_name: string | null;
  status: string;
};

export function createProject(data: { company_id: string; name: string; client_name?: string }) {
  return apiFetch<Project>("/projects", { method: "POST", body: JSON.stringify(data) });
}

export function listProjects(companyId: string) {
  return apiFetch<Project[]>(`/projects?company_id=${encodeURIComponent(companyId)}`);
}

export function getProject(projectId: string) {
  return apiFetch<Project>(`/projects/${projectId}`);
}

export type Task = {
  id: string;
  project_id: string;
  title: string;
  status: "todo" | "in_progress" | "done" | "blocked";
  due_date: string | null;
};

export type DPREntry = {
  id: string;
  entry_date: string;
  work_summary: string;
  manpower_count: number;
  status: string;
};

export type Issue = {
  id: string;
  description: string;
  severity: string;
  status: string;
};

export type FeedItem = { type: string; id: string; occurred_at: string; summary: string };

export type Dashboard = {
  percent_tasks_complete: number;
  dpr_streak_days: number;
  open_issue_count: number;
};

export function listTasks(projectId: string) {
  return apiFetch<Task[]>(`/projects/${projectId}/tasks`);
}

export function createTask(projectId: string, title: string) {
  return apiFetch<Task>(`/projects/${projectId}/tasks`, {
    method: "POST",
    body: JSON.stringify({ title }),
  });
}

export function updateTaskStatus(projectId: string, taskId: string, status: Task["status"]) {
  return apiFetch<Task>(`/projects/${projectId}/tasks/${taskId}`, {
    method: "PATCH",
    body: JSON.stringify({ status }),
  });
}

export function listDprEntries(projectId: string) {
  return apiFetch<DPREntry[]>(`/projects/${projectId}/dpr`);
}

export function createDprEntry(
  projectId: string,
  data: { entry_date: string; work_summary: string; manpower_count: number }
) {
  return apiFetch<DPREntry>(`/projects/${projectId}/dpr`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function listIssues(projectId: string) {
  return apiFetch<Issue[]>(`/projects/${projectId}/issues`);
}

export function getSiteFeed(projectId: string) {
  return apiFetch<FeedItem[]>(`/projects/${projectId}/feed`);
}

export function getDashboard(projectId: string) {
  return apiFetch<Dashboard>(`/projects/${projectId}/dashboard`);
}
