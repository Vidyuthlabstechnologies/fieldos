"use client";

import { jsPDF } from "jspdf";
import autoTable from "jspdf-autotable";

export interface BOQ {
  lines: BOQLineOut[];
  subtotal: string;
  contractor_profit_percent: string | null;
  contractor_profit_amount: string;
  grand_total: string;
}

export interface BOQLineOut {
  name: string;
  billing_unit: string;
  raw_quantity: string;
  billing_quantity: string;
  rate_per_unit: string | null;
  amount: string | null;
}

export interface DPREntry {
  entry_date: string;
  work_summary: string;
  manpower_count: number;
  weather: string | null;
  status: string;
}

export interface Inspection {
  title: string;
  inspection_type: string;
  status: string;
  overall_result: string | null;
  inspector_id: string;
  completed_date: string | null;
  scheduled_date: string | null;
}

export interface InspectionItem {
  item_description: string;
  status: string;
  notes: string | null;
}

export interface Project {
  name: string;
  client_name: string | null;
  status: string;
}

export interface Task {
  title: string;
  status: string;
  due_date: string | null;
}

export interface MaterialEntry {
  item_name: string;
  category: string;
  quantity: string;
  unit: string;
  supplier: string | null;
  cost: string | null;
}

export interface MaterialSummary {
  category: string;
  count: number;
  total_quantity: string;
  total_cost: string;
}

export interface Worker {
  name: string;
  role: string;
  daily_wage: string | null;
}

export interface Attendance {
  worker_id: string;
  attendance_date: string;
  status: string;
}

declare module "jspdf" {
  interface jsPDF {
    autoTable: (options: any) => jsPDF;
    lastAutoTable: { finalY: number };
  }
}

export function generateBOQPDF(project: Project, boq: BOQ): jsPDF {
  const doc = new jsPDF();
  const margin = 14;

  doc.setFontSize(20);
  doc.setFont("helvetica", "bold");
  doc.text(project.name, margin, 20);

  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");
  doc.text(`Client: ${project.client_name || "—"}`, margin, 28);
  doc.text(`Generated: ${new Date().toLocaleDateString()}`, margin, 34);

  const tableData = boq.lines.map((line) => [
    line.name,
    line.billing_unit,
    line.raw_quantity,
    line.billing_quantity,
    line.rate_per_unit ? `₹${line.rate_per_unit}` : "—",
    line.amount ? `₹${line.amount}` : "—",
  ]);

  doc.autoTable({
    startY: 42,
    head: [["Description", "Unit", "Raw Qty", "Billing Qty", "Rate", "Amount"]],
    body: tableData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
    columnStyles: {
      2: { halign: "right" },
      3: { halign: "right" },
      4: { halign: "right" },
      5: { halign: "right" },
    },
  });

  const finalY = doc.lastAutoTable.finalY + 6;
  doc.setFontSize(10);
  doc.setFont("helvetica", "bold");
  doc.text(`Subtotal: ₹${parseFloat(boq.subtotal).toFixed(2)}`, margin, finalY);
  if (boq.contractor_profit_percent) {
    doc.text(`Contractor Profit (${boq.contractor_profit_percent}%): ₹${parseFloat(boq.contractor_profit_amount).toFixed(2)}`, margin, finalY + 6);
  }
  doc.setFontSize(12);
  doc.text(`Grand Total: ₹${parseFloat(boq.grand_total).toFixed(2)}`, margin, finalY + 14);

  return doc;
}

export function generateDPRPDF(
  project: Project,
  entries: DPREntry[],
  _startDate?: Date,
  _endDate?: Date
): jsPDF {
  const doc = new jsPDF();
  const margin = 14;

  doc.setFontSize(20);
  doc.setFont("helvetica", "bold");
  doc.text("Daily Progress Report", margin, 20);
  doc.setFontSize(12);
  doc.setFont("helvetica", "normal");
  doc.text(project.name, margin, 28);

  const tableData = entries.map((e) => [
    e.entry_date,
    e.work_summary.length > 60 ? e.work_summary.substring(0, 60) + "..." : e.work_summary,
    e.manpower_count.toString(),
    e.weather || "—",
    e.status,
  ]);

  doc.autoTable({
    startY: 42,
    head: [["Date", "Work Summary", "Manpower", "Weather", "Status"]],
    body: tableData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
    columnStyles: { 2: { halign: "center" } },
  });

  return doc;
}

export function generateInspectionPDF(
  project: Project,
  inspection: Inspection,
  items: InspectionItem[]
): jsPDF {
  const doc = new jsPDF();
  const margin = 14;

  doc.setFontSize(20);
  doc.setFont("helvetica", "bold");
  doc.text("Inspection Report", margin, 20);
  doc.setFontSize(14);
  doc.setFont("helvetica", "normal");
  doc.text(inspection.title, margin, 28);
  doc.setFontSize(10);
  doc.text(`Type: ${inspection.inspection_type} | Status: ${inspection.status} | Result: ${inspection.overall_result || "—"}`, margin, 34);
  doc.text(`Inspector: ${inspection.inspector_id} | Date: ${inspection.completed_date || inspection.scheduled_date || "—"}`, margin, 40);

  const tableData = items.map((item, idx) => [
    (idx + 1).toString(),
    item.item_description,
    item.status.toUpperCase(),
    item.notes || "—",
  ]);

  doc.autoTable({
    startY: 48,
    head: [["#", "Checklist Item", "Status", "Notes"]],
    body: tableData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
  });

  const passCount = items.filter((i) => i.status === "pass").length;
  const failCount = items.filter((i) => i.status === "fail").length;
  const pendingCount = items.filter((i) => i.status === "pending").length;
  const naCount = items.filter((i) => i.status === "na").length;

  const finalY = doc.lastAutoTable.finalY + 6;
  doc.setFontSize(10);
  doc.text(`Summary: ${passCount} Pass | ${failCount} Fail | ${pendingCount} Pending | ${naCount} N/A`, margin, finalY);

  return doc;
}

export function generateProjectReportPDF(
  project: Project,
  data: {
    tasks: Task[];
    dprEntries: DPREntry[];
    materials: MaterialEntry[];
    materialSummary: MaterialSummary[];
    workers: Worker[];
    attendance: Attendance[];
  }
): jsPDF {
  const doc = new jsPDF();
  const margin = 14;

  doc.setFontSize(20);
  doc.setFont("helvetica", "bold");
  doc.text("Project Report", margin, 20);
  doc.setFontSize(12);
  doc.setFont("helvetica", "normal");
  doc.text(project.name, margin, 28);
  doc.text(`Client: ${project.client_name || "—"}`, margin, 34);
  doc.text(`Status: ${project.status} | Generated: ${new Date().toLocaleDateString()}`, margin, 40);

  let y = 48;

  // Tasks
  doc.setFontSize(12);
  doc.setFont("helvetica", "bold");
  doc.text("Tasks", margin, y);
  y += 6;
  const taskData = data.tasks.map((t) => [t.title, t.status, t.due_date || "—"]);
  doc.autoTable({
    startY: y,
    head: [["Title", "Status", "Due Date"]],
    body: taskData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
  });
  y = doc.lastAutoTable.finalY + 6;

  // DPR Summary
  doc.setFontSize(12);
  doc.setFont("helvetica", "bold");
  doc.text("Daily Progress Reports", margin, y);
  y += 6;
  const dprData = data.dprEntries.slice(0, 20).map((e) => [
    e.entry_date,
    e.work_summary.length > 50 ? e.work_summary.substring(0, 50) + "..." : e.work_summary,
    e.manpower_count.toString(),
  ]);
  doc.autoTable({
    startY: y,
    head: [["Date", "Summary", "Manpower"]],
    body: dprData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
  });
  y = doc.lastAutoTable.finalY + 6;

  // Materials Summary
  doc.setFontSize(12);
  doc.setFont("helvetica", "bold");
  doc.text("Material Summary", margin, y);
  y += 6;
  const matData = data.materialSummary.map((m) => [
    m.category,
    m.count.toString(),
    m.total_quantity,
    `₹${parseFloat(m.total_cost).toLocaleString()}`,
  ]);
  doc.autoTable({
    startY: y,
    head: [["Category", "Entries", "Total Qty", "Total Cost"]],
    body: matData,
    theme: "striped",
    headStyles: { fillColor: [30, 41, 59], fontSize: 8 },
    styles: { fontSize: 7.5, cellPadding: 2 },
    columnStyles: { 1: { halign: "center" }, 3: { halign: "right" } },
  });

  return doc;
}