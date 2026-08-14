import { getToken } from "./auth";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

function authHeader(): Record<string, string> {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = {
    "Content-Type": "application/json",
    ...authHeader(),
    ...(options.headers ?? {}),
  };
  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json() as Promise<T>;
}

export type Company = { id: string; name: string; created_at: string };

export function listMyCompanies() {
  return apiFetch<Company[]>("/companies/mine");
}

export function createCompany(name: string) {
  return apiFetch<Company>("/companies", { method: "POST", body: JSON.stringify({ name }) });
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

export type DPRVoiceDraft = {
  transcript: string;
  work_summary: string;
  manpower_count: number;
  weather: string | null;
};

// Multipart upload -- doesn't go through apiFetch, which always sets
// Content-Type: application/json. The browser needs to set its own
// multipart boundary here.
export async function createDprVoiceDraft(projectId: string, audioBlob: Blob): Promise<DPRVoiceDraft> {
  const form = new FormData();
  form.append("audio", audioBlob, "recording.webm");

  const token = getToken();
  const res = await fetch(`${API_BASE_URL}/projects/${projectId}/dpr/voice-draft`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json();
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

// Estimation / BOQ. Money and quantity fields are kept as strings (not
// parsed to JS number) to preserve the exact Decimal precision the backend
// sends -- converting to a JS float would reintroduce the rounding-error
// risk the whole calculation engine exists to avoid.
export type CalculationType = "volume" | "area" | "steel_weight" | "count";

export type Estimation = {
  id: string;
  project_id: string;
  name: string;
  status: string;
  contractor_profit_percent: string | null;
  created_by: string;
};

export type CostHead = {
  id: string;
  estimation_id: string;
  name: string;
  calculation_type: CalculationType;
  raw_unit: string;
  billing_unit: string;
  conversion_factor: string;
  rate_per_unit: string | null;
  sort_order: number;
};

export type BOQLine = {
  cost_head_id: string;
  name: string;
  billing_unit: string;
  raw_quantity: string;
  billing_quantity: string;
  rate_per_unit: string | null;
  amount: string | null;
};

export type BOQ = {
  lines: BOQLine[];
  subtotal: string;
  contractor_profit_percent: string | null;
  contractor_profit_amount: string;
  grand_total: string;
};

export function listEstimations(projectId: string) {
  return apiFetch<Estimation[]>(`/projects/${projectId}/estimations`);
}

export function listCostHeads(estimationId: string) {
  return apiFetch<CostHead[]>(`/estimations/${estimationId}/cost-heads`);
}

export function createEstimation(
  projectId: string,
  data: { name: string; contractor_profit_percent?: string }
) {
  return apiFetch<Estimation>(`/projects/${projectId}/estimations`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function createCostHead(
  estimationId: string,
  data: {
    name: string;
    calculation_type: CalculationType;
    raw_unit: string;
    billing_unit: string;
    conversion_factor?: string;
    rate_per_unit?: string;
  }
) {
  return apiFetch<CostHead>(`/estimations/${estimationId}/cost-heads`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function createMeasurementEntry(
  costHeadId: string,
  data: { description: string; length?: string; width?: string; depth?: string; nos: string; is_deduction?: boolean }
) {
  return apiFetch(`/cost-heads/${costHeadId}/measurement-entries`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function createSteelEntry(
  costHeadId: string,
  data: { description: string; bar_dia_mm: string; nos: string; length_ft: string }
) {
  return apiFetch(`/cost-heads/${costHeadId}/steel-entries`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function getBoq(estimationId: string) {
  return apiFetch<BOQ>(`/estimations/${estimationId}/boq`);
}

// Project export/import -- moving one project's full data between two
// separate local installs (e.g. site laptop -> office laptop). The payload
// shape is opaque here on purpose: it's produced and consumed entirely by
// the backend, this just passes it through.
export function exportProject(projectId: string) {
  return apiFetch<Record<string, unknown>>(`/projects/${projectId}/export`);
}

export function importProject(companyId: string, data: Record<string, unknown>) {
  return apiFetch<Project>(`/companies/${companyId}/import`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}
