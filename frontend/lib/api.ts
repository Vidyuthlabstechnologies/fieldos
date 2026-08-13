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
