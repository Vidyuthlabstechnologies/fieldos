import { getToken } from "./auth";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";
const DEFAULT_TIMEOUT_MS = 30_000;

function authHeader(): Record<string, string> {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const headers = {
      "Content-Type": "application/json",
      ...authHeader(),
      ...(options.headers ?? {}),
    };
    const res = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`API error ${res.status}: ${body}`);
    }
    return res.json() as Promise<T>;
  } finally {
    clearTimeout(timeoutId);
  }
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
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 60_000); // longer timeout for transcription

  try {
    const res = await fetch(`${API_BASE_URL}/projects/${projectId}/dpr/voice-draft`, {
      method: "POST",
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: form,
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`API error ${res.status}: ${body}`);
    }
    return res.json();
  } finally {
    clearTimeout(timeoutId);
  }
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

export type MeasurementEntry = {
  id: string;
  cost_head_id: string;
  description: string;
  length: string | null;
  width: string | null;
  depth: string | null;
  nos: string;
  is_deduction: boolean;
};

export type SteelEntry = {
  id: string;
  cost_head_id: string;
  description: string;
  bar_dia_mm: string;
  nos: string;
  length_ft: string;
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
  return apiFetch<MeasurementEntry>(`/cost-heads/${costHeadId}/measurement-entries`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function createSteelEntry(
  costHeadId: string,
  data: { description: string; bar_dia_mm: string; nos: string; length_ft: string }
) {
  return apiFetch<SteelEntry>(`/cost-heads/${costHeadId}/steel-entries`, {
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

// Material tracking
export type MaterialEntry = {
  id: string;
  project_id: string;
  entry_date: string;
  item_name: string;
  category: string;
  quantity: string;
  unit: string;
  supplier: string | null;
  cost: string | null;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export type MaterialSummary = {
  category: string;
  count: number;
  total_cost: string;
  total_quantity: string;
};

export function listMaterialEntries(projectId: string) {
  return apiFetch<MaterialEntry[]>(`/projects/${projectId}/materials`);
}

export function createMaterialEntry(
  projectId: string,
  data: {
    entry_date: string;
    item_name: string;
    category?: string;
    quantity: string;
    unit: string;
    supplier?: string;
    cost?: string;
    notes?: string;
  }
) {
  return apiFetch<MaterialEntry>(`/projects/${projectId}/materials`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function getMaterialSummary(projectId: string) {
  return apiFetch<MaterialSummary[]>(`/projects/${projectId}/materials/summary`);
}

export type MaterialPhoto = {
  id: string;
  material_entry_id: string;
  photo_url: string;
  caption: string | null;
  created_at: string;
};

export async function uploadMaterialPhoto(
  projectId: string,
  entryId: string,
  file: File,
  caption?: string
): Promise<MaterialPhoto> {
  const form = new FormData();
  form.append("file", file);
  if (caption) form.append("caption", caption);
  const token = getToken();
  const res = await fetch(`${API_BASE_URL}/projects/${projectId}/materials/${entryId}/photos`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json();
}

export function listMaterialPhotos(projectId: string, entryId: string) {
  return apiFetch<MaterialPhoto[]>(`/projects/${projectId}/materials/${entryId}/photos`);
}

// Workers / labour
export type Worker = {
  id: string;
  project_id: string;
  name: string;
  role: string;
  phone: string | null;
  daily_wage: string | null;
  status: string;
  created_at: string;
};

export type Attendance = {
  id: string;
  worker_id: string;
  attendance_date: string;
  status: string;
  notes: string | null;
  created_at: string;
};

export type AttendanceSummary = {
  date: string;
  total_workers: number;
  present: number;
  absent: number;
  half_day: number;
  total_wage_cost: string;
};

export function listWorkers(projectId: string) {
  return apiFetch<Worker[]>(`/projects/${projectId}/workers`);
}

export function createWorker(
  projectId: string,
  data: { name: string; role: string; phone?: string; daily_wage?: string }
) {
  return apiFetch<Worker>(`/projects/${projectId}/workers`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function markAttendance(
  projectId: string,
  data: { worker_id: string; attendance_date: string; status?: string; notes?: string }
) {
  return apiFetch<Attendance>(`/projects/${projectId}/attendance`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function listAttendance(projectId: string, date?: string) {
  const qs = date ? `?date=${date}` : "";
  return apiFetch<Attendance[]>(`/projects/${projectId}/attendance${qs}`);
}

export function getAttendanceSummary(projectId: string) {
  return apiFetch<AttendanceSummary>(`/projects/${projectId}/attendance/summary`);
}

// Settings -- installation-wide config. The key value itself is
// write-only: the backend never echoes it back, only whether it's set.
export type SarvamStatus = { configured: boolean };

export function getSarvamStatus() {
  return apiFetch<SarvamStatus>("/settings/sarvam");
}

export function setSarvamKey(apiKey: string) {
  return apiFetch<SarvamStatus>("/settings/sarvam", {
    method: "PUT",
    body: JSON.stringify({ api_key: apiKey }),
  });
}

export function clearSarvamKey() {
  return apiFetch<SarvamStatus>("/settings/sarvam", { method: "DELETE" });
}

// Document management
export type Document = {
  id: string;
  project_id: string;
  name: string;
  category: string;
  version: number;
  file_path: string;
  file_size: number | null;
  mime_type: string | null;
  notes: string | null;
  uploaded_by: string;
  created_at: string;
};

export function listDocuments(projectId: string, category?: string) {
  const qs = category ? `?category=${category}` : "";
  return apiFetch<Document[]>(`/projects/${projectId}/documents${qs}`);
}

export async function uploadDocument(
  projectId: string,
  file: File,
  category: string = "other",
  notes?: string
): Promise<Document> {
  const form = new FormData();
  form.append("file", file);
  const token = getToken();
  const params = new URLSearchParams({ category });
  if (notes) params.set("notes", notes);
  const res = await fetch(`${API_BASE_URL}/projects/${projectId}/documents?${params}`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json();
}

// Procurement — Vendors
export type Vendor = {
  id: string;
  company_id: string;
  name: string;
  contact_person: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  gst_number: string | null;
  category: string | null;
  notes: string | null;
  created_at: string;
};

export function listVendors(companyId: string) {
  return apiFetch<Vendor[]>(`/companies/${companyId}/vendors`);
}

export function createVendor(
  companyId: string,
  data: { name: string; contact_person?: string; phone?: string; email?: string; category?: string }
) {
  return apiFetch<Vendor>(`/companies/${companyId}/vendors`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// Procurement — Requisitions
export type Requisition = {
  id: string;
  project_id: string;
  item_name: string;
  quantity: string;
  unit: string;
  estimated_cost: string | null;
  urgency: string;
  status: string;
  requested_by: string;
  approved_by: string | null;
  created_at: string;
};

export function listRequisitions(projectId: string, status?: string) {
  const qs = status ? `?status=${status}` : "";
  return apiFetch<Requisition[]>(`/projects/${projectId}/requisitions${qs}`);
}

export function createRequisition(
  projectId: string,
  data: { item_name: string; quantity: string; unit: string; estimated_cost?: string; urgency?: string }
) {
  return apiFetch<Requisition>(`/projects/${projectId}/requisitions`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function approveRequisition(projectId: string, reqId: string) {
  return apiFetch<Requisition>(`/projects/${projectId}/requisitions/${reqId}/approve`, {
    method: "PATCH",
  });
}

// Procurement — RFQ
export type RFQ = {
  id: string;
  project_id: string;
  requisition_id: string | null;
  title: string;
  deadline: string | null;
  status: string;
  created_by: string;
  created_at: string;
};

export function listRFQs(projectId: string) {
  return apiFetch<RFQ[]>(`/projects/${projectId}/rfqs`);
}

export function createRFQ(projectId: string, data: { title: string; requisition_id?: string; deadline?: string }) {
  return apiFetch<RFQ>(`/projects/${projectId}/rfqs`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// Procurement — Quotes
export type Quote = {
  id: string;
  rfq_id: string;
  vendor_id: string;
  total_amount: string;
  delivery_days: number | null;
  payment_terms: string | null;
  notes: string | null;
  status: string;
  created_at: string;
};

export function listQuotes(rfqId: string) {
  return apiFetch<Quote[]>(`/rfqs/${rfqId}/quotes`);
}

export function createQuote(
  rfqId: string,
  data: { vendor_id: string; total_amount: string; delivery_days?: number; payment_terms?: string }
) {
  return apiFetch<Quote>(`/rfqs/${rfqId}/quotes`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// Procurement — Purchase Orders
export type PurchaseOrder = {
  id: string;
  project_id: string;
  quote_id: string | null;
  vendor_id: string;
  po_number: string;
  total_amount: string;
  delivery_date: string | null;
  status: string;
  notes: string | null;
  created_by: string;
  created_at: string;
};

export function listPurchaseOrders(projectId: string) {
  return apiFetch<PurchaseOrder[]>(`/projects/${projectId}/purchase-orders`);
}

export function createPurchaseOrder(
  projectId: string,
  data: { vendor_id: string; po_number: string; total_amount: string; delivery_date?: string; quote_id?: string }
) {
  return apiFetch<PurchaseOrder>(`/projects/${projectId}/purchase-orders`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// Procurement — GRN
export type GRN = {
  id: string;
  purchase_order_id: string;
  received_date: string;
  item_description: string;
  ordered_qty: string;
  received_qty: string;
  unit: string;
  condition: string;
  received_by: string;
  notes: string | null;
  created_at: string;
};

export function listGRNs(poId: string) {
  return apiFetch<GRN[]>(`/purchase-orders/${poId}/grn`);
}

export function createGRN(
  poId: string,
  data: { received_date: string; item_description: string; ordered_qty: string; received_qty: string; unit: string; condition?: string }
) {
  return apiFetch<GRN>(`/purchase-orders/${poId}/grn`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// Equipment
export type Equipment = {
  id: string;
  project_id: string;
  name: string;
  equipment_type: string;
  model: string | null;
  registration_number: string | null;
  status: string;
  daily_rate: string | null;
  notes: string | null;
  created_at: string;
};

export type EquipmentLog = {
  id: string;
  equipment_id: string;
  log_date: string;
  log_type: string;
  hours_used: string | null;
  description: string | null;
  cost: string | null;
  created_by: string;
  created_at: string;
};

export function listEquipment(projectId: string) {
  return apiFetch<Equipment[]>(`/projects/${projectId}/equipment`);
}

export function createEquipment(
  projectId: string,
  data: { name: string; equipment_type: string; model?: string; registration_number?: string; daily_rate?: string }
) {
  return apiFetch<Equipment>(`/projects/${projectId}/equipment`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function updateEquipmentStatus(projectId: string, equipmentId: string, status: string) {
  return apiFetch<Equipment>(`/projects/${projectId}/equipment/${equipmentId}`, {
    method: "PATCH",
    body: JSON.stringify({ status }),
  });
}

export function createEquipmentLog(equipmentId: string, data: { log_date: string; log_type: string; hours_used?: string; description?: string; cost?: string }) {
  return apiFetch<EquipmentLog>(`/equipment/${equipmentId}/logs`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function listEquipmentLogs(equipmentId: string) {
  return apiFetch<EquipmentLog[]>(`/equipment/${equipmentId}/logs`);
}

// Inspections
export type Inspection = {
  id: string;
  project_id: string;
  title: string;
  inspection_type: string;
  status: string;
  inspector_id: string;
  scheduled_date: string | null;
  completed_date: string | null;
  overall_result: string | null;
  notes: string | null;
  created_at: string;
};

export type InspectionItem = {
  id: string;
  inspection_id: string;
  item_description: string;
  status: string;
  notes: string | null;
  sort_order: number;
};

export function listInspections(projectId: string, status?: string) {
  const qs = status ? `?status=${status}` : "";
  return apiFetch<Inspection[]>(`/projects/${projectId}/inspections${qs}`);
}

export function createInspection(projectId: string, data: { title: string; inspection_type?: string; scheduled_date?: string }) {
  return apiFetch<Inspection>(`/projects/${projectId}/inspections`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function listInspectionItems(inspectionId: string) {
  return apiFetch<InspectionItem[]>(`/inspections/${inspectionId}/items`);
}

export function createInspectionItem(inspectionId: string, data: { item_description: string; status?: string; notes?: string }) {
  return apiFetch<InspectionItem>(`/inspections/${inspectionId}/items`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export type InspectionPhoto = {
  id: string;
  inspection_id: string;
  photo_url: string;
  caption: string | null;
  uploaded_by: string;
  created_at: string;
};

export async function uploadInspectionPhoto(
  inspectionId: string,
  file: File,
  caption?: string
): Promise<InspectionPhoto> {
  const form = new FormData();
  form.append("file", file);
  if (caption) form.append("caption", caption);
  const token = getToken();
  const res = await fetch(`${API_BASE_URL}/inspections/${inspectionId}/photos`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json();
}

export function listInspectionPhotos(inspectionId: string) {
  return apiFetch<InspectionPhoto[]>(`/inspections/${inspectionId}/photos`);
}

// Billing / Subscriptions
export type SubscriptionPlan = {
  id: string;
  name: string;
  monthly_price_usd: number;
  max_projects: number;
  max_users_per_project: number;
  features: string | null;
  is_active: boolean;
};

export type CompanySubscription = {
  id: string;
  company_id: string;
  plan_id: string | null;
  status: string;
  trial_ends_at: string | null;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
};

export type BillingEvent = {
  id: string;
  company_id: string;
  event_type: string;
  amount_usd: number | null;
  currency: string;
  description: string | null;
  created_at: string;
};

export function listPlans() {
  return apiFetch<SubscriptionPlan[]>(`/billing/plans`);
}

export function getSubscription(companyId: string) {
  return apiFetch<CompanySubscription>(`/billing/subscription?company_id=${companyId}`);
}

export function createCheckoutSession(companyId: string, data: { plan_id: string; success_url: string; cancel_url: string }) {
  return apiFetch<{ url: string }>(`/billing/checkout-session`, {
    method: "POST",
    body: JSON.stringify({ ...data, company_id: companyId }),
  });
}

export function createPortalSession(companyId: string) {
  return apiFetch<{ url: string }>(`/billing/portal-session`, {
    method: "POST",
    body: JSON.stringify({ company_id: companyId }),
  });
}

export function listBillingEvents(companyId: string) {
  return apiFetch<BillingEvent[]>(`/billing/events?company_id=${companyId}`);
}
