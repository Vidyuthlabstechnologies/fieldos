"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import {
  approveRequisition,
  createGRN,
  createPurchaseOrder,
  createQuote,
  createRequisition,
  createRFQ,
  createVendor,
  getProject,
  listGRNs,
  listPurchaseOrders,
  listQuotes,
  listRequisitions,
  listRFQs,
  listVendors,
  type GRN,
  type Project,
  type PurchaseOrder,
  type Quote,
  type Requisition,
  type RFQ,
  type Vendor,
} from "@/lib/api";

type ProcurementTab = "vendors" | "requisitions" | "rfq" | "quotes" | "po" | "grn";

function ProcurementPage({ projectId }: { projectId: string }) {
  const [tab, setTab] = useState<ProcurementTab>("requisitions");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [companyId, setCompanyId] = useState<string | null>(null);

  // Vendors
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [vName, setVName] = useState("");
  const [vContact, setVContact] = useState("");
  const [vPhone, setVPhone] = useState("");
  const [vEmail, setVEmail] = useState("");
  const [vCategory, setVCategory] = useState("");

  // Requisitions
  const [requisitions, setRequisitions] = useState<Requisition[]>([]);
  const [rItem, setRItem] = useState("");
  const [rQty, setRQty] = useState("");
  const [rUnit, setRUnit] = useState("nos");
  const [rCost, setRCost] = useState("");
  const [rUrgency, setRUrgency] = useState("normal");

  // RFQ
  const [rfqs, setRfqs] = useState<RFQ[]>([]);
  const [rfqTitle, setRfqTitle] = useState("");
  const [rfqReqId, setRfqReqId] = useState("");
  const [rfqDeadline, setRfqDeadline] = useState("");

  // Quotes
  const [quotes, setQuotes] = useState<Quote[]>([]);
  const [selectedRfq, setSelectedRfq] = useState<string | null>(null);
  const [qVendorId, setQVendorId] = useState("");
  const [qAmount, setQAmount] = useState("");
  const [qDelivery, setQDelivery] = useState("");
  const [qTerms, setQTerms] = useState("");

  // Purchase Orders
  const [pos, setPos] = useState<PurchaseOrder[]>([]);
  const [poVendorId, setPoVendorId] = useState("");
  const [poNumber, setPoNumber] = useState("");
  const [poAmount, setPoAmount] = useState("");
  const [poDelivery, setPoDelivery] = useState("");
  const [poQuoteId, setPoQuoteId] = useState("");

  // GRN
  const [grns, setGrns] = useState<GRN[]>([]);
  const [selectedPo, setSelectedPo] = useState<string | null>(null);
  const [grnDate, setGrnDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [grnItem, setGrnItem] = useState("");
  const [grnOrderedQty, setGrnOrderedQty] = useState("");
  const [grnReceivedQty, setGrnReceivedQty] = useState("");
  const [grnUnit, setGrnUnit] = useState("");
  const [grnCondition, setGrnCondition] = useState("good");

  // Common
  const statusColor: Record<string, string> = {
    pending: "bg-amber-100 text-amber-700",
    approved: "bg-green-100 text-green-700",
    rejected: "bg-red-100 text-red-700",
    ordered: "bg-blue-100 text-blue-700",
    draft: "bg-slate-100 text-slate-600",
    sent: "bg-blue-100 text-blue-700",
    received: "bg-green-100 text-green-700",
    partial: "bg-amber-100 text-amber-700",
    completed: "bg-green-100 text-green-700",
    good: "bg-green-100 text-green-700",
    damaged: "bg-red-100 text-red-700",
    short: "bg-amber-100 text-amber-700",
  };

  const urgencyColor: Record<string, string> = {
    low: "bg-slate-100 text-slate-600",
    normal: "bg-blue-100 text-blue-700",
    high: "bg-amber-100 text-amber-700",
    critical: "bg-red-100 text-red-700",
  };

  // --- Data fetching ---
  async function loadVendors() {
    if (!companyId) return;
    setVendors(await listVendors(companyId));
  }

  async function loadRequisitions() {
    setRequisitions(await listRequisitions(projectId));
  }

  async function loadRFQs() {
    setRfqs(await listRFQs(projectId));
  }

  async function loadQuotes() {
    if (selectedRfq) setQuotes(await listQuotes(selectedRfq));
  }

  async function loadPOs() {
    setPos(await listPurchaseOrders(projectId));
  }

  async function loadGRNs() {
    if (selectedPo) {
      setGrns(await listGRNs(selectedPo));
    }
  }

  useEffect(() => {
    loadVendors();
    loadRequisitions();
    loadRFQs();
    loadPOs();
    // Fetch project to get company_id
    getProject(projectId).then((project: Project) => {
      setCompanyId(project.company_id);
    }).catch(console.error);
  }, [projectId]);

  useEffect(() => { loadVendors(); }, [companyId]);

  useEffect(() => { loadQuotes(); }, [selectedRfq]);
  useEffect(() => { loadGRNs(); }, [selectedPo]);

  // --- Handlers ---
  async function handleAddVendor(e: React.FormEvent) {
    e.preventDefault();
    if (!vName.trim() || !companyId) return;
    setSubmitting(true);
    try {
      await createVendor(companyId, { name: vName, contact_person: vContact || undefined, phone: vPhone || undefined, email: vEmail || undefined, category: vCategory || undefined });
      setVName(""); setVContact(""); setVPhone(""); setVEmail(""); setVCategory("");
      loadVendors();
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
    finally { setSubmitting(false); }
  }

  async function handleAddRequisition(e: React.FormEvent) {
    e.preventDefault();
    if (!rItem.trim() || !rQty.trim()) return;
    setSubmitting(true);
    try {
      await createRequisition(projectId, { item_name: rItem, quantity: rQty, unit: rUnit, estimated_cost: rCost || undefined, urgency: rUrgency });
      setRItem(""); setRQty(""); setRCost("");
      loadRequisitions();
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
    finally { setSubmitting(false); }
  }

  async function handleApproveReq(reqId: string) {
    try { await approveRequisition(projectId, reqId); loadRequisitions(); }
    catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
  }

  async function handleAddRFQ(e: React.FormEvent) {
    e.preventDefault();
    if (!rfqTitle.trim()) return;
    setSubmitting(true);
    try {
      await createRFQ(projectId, { title: rfqTitle, requisition_id: rfqReqId || undefined, deadline: rfqDeadline || undefined });
      setRfqTitle(""); setRfqReqId(""); setRfqDeadline("");
      loadRFQs();
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
    finally { setSubmitting(false); }
  }

  async function handleAddQuote(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedRfq || !qVendorId || !qAmount) return;
    setSubmitting(true);
    try {
      await createQuote(selectedRfq, { vendor_id: qVendorId, total_amount: qAmount, delivery_days: qDelivery ? parseInt(qDelivery) : undefined, payment_terms: qTerms || undefined });
      setQVendorId(""); setQAmount(""); setQDelivery(""); setQTerms("");
      loadQuotes();
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
    finally { setSubmitting(false); }
  }

  async function handleAddPO(e: React.FormEvent) {
    e.preventDefault();
    if (!poVendorId || !poNumber || !poAmount) return;
    setSubmitting(true);
    try {
      await createPurchaseOrder(projectId, { vendor_id: poVendorId, po_number: poNumber, total_amount: poAmount, delivery_date: poDelivery || undefined, quote_id: poQuoteId || undefined });
      setPoVendorId(""); setPoNumber(""); setPoAmount(""); setPoDelivery(""); setPoQuoteId("");
      loadPOs();
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
    finally { setSubmitting(false); }
  }

  // --- Render ---
  const tabs: { id: ProcurementTab; label: string }[] = [
    { id: "vendors", label: "Vendors" },
    { id: "requisitions", label: "Requisitions" },
    { id: "rfq", label: "RFQ" },
    { id: "quotes", label: "Quotes" },
    { id: "po", label: "Purchase Orders" },
    { id: "grn", label: "GRN" },
  ];

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-6xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Procurement</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">&larr; Back</Link>
          </div>

          {/* Tab bar */}
          <div className="mb-4 flex flex-wrap gap-1 border-b border-slate-200 pb-2">
            {tabs.map((t) => (
              <button
                key={t.id}
                onClick={() => { setTab(t.id); setError(null); }}
                className={`px-3 py-1.5 text-sm font-medium rounded ${tab === t.id ? "bg-slate-900 text-white" : "text-slate-600 hover:bg-slate-100"}`}
              >
                {t.label}
              </button>
            ))}
          </div>

          {error && <p className="mb-3 text-sm text-red-600">{error}</p>}

          {/* ========== VENDORS ========== */}
          {tab === "vendors" && (
            <>
              <form onSubmit={handleAddVendor} className="mb-6 rounded border border-slate-200 bg-white p-4">
                <h2 className="mb-3 font-semibold">Add Vendor</h2>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                  <div className="sm:col-span-2">
                    <label className="mb-1 block text-xs text-slate-500">Name *</label>
                    <input value={vName} onChange={(e) => setVName(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Contact Person</label>
                    <input value={vContact} onChange={(e) => setVContact(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Phone</label>
                    <input value={vPhone} onChange={(e) => setVPhone(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Email</label>
                    <input value={vEmail} onChange={(e) => setVEmail(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div className="sm:col-span-4">
                    <label className="mb-1 block text-xs text-slate-500">Category</label>
                    <input value={vCategory} onChange={(e) => setVCategory(e.target.value)} placeholder="e.g. cement, steel, electrical" className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                </div>
                <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                  {submitting ? "Adding..." : "Add Vendor"}
                </button>
              </form>

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">Vendors ({vendors.length})</h2></div>
                {vendors.length === 0 ? <p className="p-4 text-sm text-slate-500">No vendors yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {vendors.map((v) => (
                      <div key={v.id} className="px-4 py-3">
                        <span className="font-medium">{v.name}</span>
                        <span className="ml-2 text-sm text-slate-500">{v.category || "—"}</span>
                        <div className="mt-1 text-xs text-slate-500">
                          {v.contact_person && `${v.contact_person} · `}{v.phone || ""}{v.email && ` · ${v.email}`}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ========== REQUISITIONS ========== */}
          {tab === "requisitions" && (
            <>
              <form onSubmit={handleAddRequisition} className="mb-6 rounded border border-slate-200 bg-white p-4">
                <h2 className="mb-3 font-semibold">New Material Requisition</h2>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                  <div className="sm:col-span-2">
                    <label className="mb-1 block text-xs text-slate-500">Item Name *</label>
                    <input value={rItem} onChange={(e) => setRItem(e.target.value)} placeholder="e.g. OPC 53 Cement" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Quantity *</label>
                    <input type="number" step="0.001" value={rQty} onChange={(e) => setRQty(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Unit</label>
                    <select value={rUnit} onChange={(e) => setRUnit(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                      {["nos", "bag", "kg", "ton", "cu.m", "litre", "ft", "m", "sq.m"].map((u) => <option key={u} value={u}>{u}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Est. Cost (₹)</label>
                    <input type="number" step="0.01" value={rCost} onChange={(e) => setRCost(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Urgency</label>
                    <select value={rUrgency} onChange={(e) => setRUrgency(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                      {["low", "normal", "high", "critical"].map((u) => <option key={u} value={u}>{u}</option>)}
                    </select>
                  </div>
                </div>
                <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                  {submitting ? "Creating..." : "Submit Requisition"}
                </button>
              </form>

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">Requisitions ({requisitions.length})</h2></div>
                {requisitions.length === 0 ? <p className="p-4 text-sm text-slate-500">No requisitions yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {requisitions.map((r) => (
                      <div key={r.id} className="flex items-center justify-between px-4 py-3">
                        <div>
                          <span className="font-medium">{r.item_name}</span>
                          <span className="ml-2 text-sm text-slate-500">{r.quantity} {r.unit}{r.estimated_cost && ` · ₹${parseFloat(r.estimated_cost).toLocaleString()}`}</span>
                          <div className="mt-1 flex gap-2">
                            <span className={`rounded px-1.5 py-0.5 text-xs ${urgencyColor[r.urgency] || ""}`}>{r.urgency}</span>
                            <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[r.status] || ""}`}>{r.status}</span>
                          </div>
                        </div>
                        {r.status === "pending" && <button onClick={() => handleApproveReq(r.id)} className="rounded bg-green-600 px-3 py-1.5 text-xs text-white hover:bg-green-700">Approve</button>}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ========== RFQ ========== */}
          {tab === "rfq" && (
            <>
              <form onSubmit={handleAddRFQ} className="mb-6 rounded border border-slate-200 bg-white p-4">
                <h2 className="mb-3 font-semibold">Create RFQ</h2>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <div className="sm:col-span-2">
                    <label className="mb-1 block text-xs text-slate-500">Title *</label>
                    <input value={rfqTitle} onChange={(e) => setRfqTitle(e.target.value)} placeholder="e.g. Cement Supply - Q3 2025" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Link to Requisition (optional)</label>
                    <input value={rfqReqId} onChange={(e) => setRfqReqId(e.target.value)} placeholder="Requisition ID" className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Deadline</label>
                    <input type="date" value={rfqDeadline} onChange={(e) => setRfqDeadline(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                </div>
                <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                  {submitting ? "Creating..." : "Create RFQ"}
                </button>
              </form>

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">RFQs ({rfqs.length})</h2></div>
                {rfqs.length === 0 ? <p className="p-4 text-sm text-slate-500">No RFQs yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {rfqs.map((r) => (
                      <button key={r.id} onClick={() => { setSelectedRfq(r.id); setTab("quotes"); }} className="w-full px-4 py-3 text-left hover:bg-slate-50 border-b border-slate-100 last:border-0">
                        <span className="font-medium">{r.title}</span>
                        <span className="ml-2 text-sm text-slate-500">{r.deadline ? `Deadline: ${r.deadline}` : "No deadline"}</span>
                        <span className={`ml-2 rounded px-1.5 py-0.5 text-xs ${statusColor[r.status] || ""}`}>{r.status}</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ========== QUOTES ========== */}
          {tab === "quotes" && (
            <>
              <div className="mb-4 flex items-center justify-between">
                <h2 className="font-semibold">Quotations {selectedRfq && `for RFQ ${selectedRfq.slice(0, 8)}`}</h2>
                <button onClick={() => { setSelectedRfq(null); setTab("rfq"); }} className="text-sm text-slate-600 underline">&larr; Back to RFQs</button>
              </div>

              {selectedRfq && (
                <form onSubmit={handleAddQuote} className="mb-6 rounded border border-slate-200 bg-white p-4">
                  <h2 className="mb-3 font-semibold">Add Quotation</h2>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Vendor *</label>
                      <select value={qVendorId} onChange={(e) => setQVendorId(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required>
                        <option value="">Select vendor</option>
                        {vendors.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
                      </select>
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Total Amount (₹) *</label>
                      <input type="number" step="0.01" value={qAmount} onChange={(e) => setQAmount(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Delivery (days)</label>
                      <input type="number" value={qDelivery} onChange={(e) => setQDelivery(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Payment Terms</label>
                      <input value={qTerms} onChange={(e) => setQTerms(e.target.value)} placeholder="e.g. 30 days" className="w-full rounded border border-slate-300 p-2 text-sm" />
                    </div>
                  </div>
                  <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                    {submitting ? "Adding..." : "Add Quotation"}
                  </button>
                </form>
              )}

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">Quotations ({quotes.length})</h2></div>
                {quotes.length === 0 ? <p className="p-4 text-sm text-slate-500">No quotations yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {quotes.map((q) => (
                      <div key={q.id} className="px-4 py-3">
                        <div className="flex items-center justify-between">
                          <span className="font-medium">Vendor: {vendors.find(v => v.id === q.vendor_id)?.name || q.vendor_id}</span>
                          <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[q.status] || ""}`}>{q.status}</span>
                        </div>
                        <div className="mt-1 text-sm text-slate-500">
                          ₹{parseFloat(q.total_amount).toLocaleString()} · {q.delivery_days ? `${q.delivery_days} days` : "—"} · {q.payment_terms || "—"}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ========== PURCHASE ORDERS ========== */}
          {tab === "po" && (
            <>
              <form onSubmit={handleAddPO} className="mb-6 rounded border border-slate-200 bg-white p-4">
                <h2 className="mb-3 font-semibold">Create Purchase Order</h2>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Vendor *</label>
                    <select value={poVendorId} onChange={(e) => setPoVendorId(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required>
                      <option value="">Select vendor</option>
                      {vendors.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">PO Number *</label>
                    <input value={poNumber} onChange={(e) => setPoNumber(e.target.value)} placeholder="PO-2025-001" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Total Amount (₹) *</label>
                    <input type="number" step="0.01" value={poAmount} onChange={(e) => setPoAmount(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs text-slate-500">Delivery Date</label>
                    <input type="date" value={poDelivery} onChange={(e) => setPoDelivery(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                  <div className="sm:col-span-2">
                    <label className="mb-1 block text-xs text-slate-500">From Quotation (optional)</label>
                    <select value={poQuoteId} onChange={(e) => setPoQuoteId(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                      <option value="">—</option>
                      {quotes.map((q) => <option key={q.id} value={q.id}>₹{parseFloat(q.total_amount).toLocaleString()} - {vendors.find(v => v.id === q.vendor_id)?.name || q.vendor_id}</option>)}
                    </select>
                  </div>
                </div>
                <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                  {submitting ? "Creating..." : "Create PO"}
                </button>
              </form>

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">Purchase Orders ({pos.length})</h2></div>
                {pos.length === 0 ? <p className="p-4 text-sm text-slate-500">No purchase orders yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {pos.map((p) => (
                      <button key={p.id} onClick={() => { setSelectedPo(p.id); setTab("grn"); }} className="w-full px-4 py-3 text-left hover:bg-slate-50 border-b border-slate-100 last:border-0">
                        <div className="flex items-center justify-between">
                          <span className="font-medium">{p.po_number}</span>
                          <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[p.status] || ""}`}>{p.status}</span>
                        </div>
                        <div className="mt-1 text-sm text-slate-500">
                          Vendor: {vendors.find(v => v.id === p.vendor_id)?.name || p.vendor_id} · ₹{parseFloat(p.total_amount).toLocaleString()}
                          {p.delivery_date && ` · Delivery: ${p.delivery_date}`}
                        </div>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* ========== GRN ========== */}
          {tab === "grn" && (
            <>
              <div className="mb-4 flex items-center justify-between">
                <h2 className="font-semibold">Goods Received Notes {selectedPo && `for PO ${selectedPo.slice(0, 8)}`}</h2>
                <button onClick={() => { setSelectedPo(null); setTab("po"); }} className="text-sm text-slate-600 underline">&larr; Back to POs</button>
              </div>

              {selectedPo && (
                <form onSubmit={async (e) => {
                  e.preventDefault();
                  if (!grnItem || !grnReceivedQty || !grnUnit) return;
                  setSubmitting(true);
                  try {
                    await createGRN(selectedPo, { received_date: grnDate, item_description: grnItem, ordered_qty: grnOrderedQty, received_qty: grnReceivedQty, unit: grnUnit, condition: grnCondition });
                    setGrnItem(""); setGrnOrderedQty(""); setGrnReceivedQty(""); setGrnUnit(""); setGrnCondition("good");
                    loadGRNs();
                  } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
                  finally { setSubmitting(false); }
                }} className="mb-6 rounded border border-slate-200 bg-white p-4">
                  <h2 className="mb-3 font-semibold">Record Goods Received</h2>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Date *</label>
                      <input type="date" value={grnDate} onChange={(e) => setGrnDate(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                    </div>
                    <div className="sm:col-span-2">
                      <label className="mb-1 block text-xs text-slate-500">Item Description *</label>
                      <input value={grnItem} onChange={(e) => setGrnItem(e.target.value)} placeholder="e.g. OPC 53 Cement - 50 bags" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Ordered Qty</label>
                      <input type="number" step="0.001" value={grnOrderedQty} onChange={(e) => setGrnOrderedQty(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Received Qty *</label>
                      <input type="number" step="0.001" value={grnReceivedQty} onChange={(e) => setGrnReceivedQty(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" required />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Unit</label>
                      <input value={grnUnit} onChange={(e) => setGrnUnit(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                    </div>
                    <div>
                      <label className="mb-1 block text-xs text-slate-500">Condition</label>
                      <select value={grnCondition} onChange={(e) => setGrnCondition(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                        {["good", "damaged", "short"].map((c) => <option key={c} value={c}>{c}</option>)}
                      </select>
                    </div>
                  </div>
                  <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                    {submitting ? "Recording..." : "Record GRN"}
                  </button>
                </form>
              )}

              <div className="rounded border border-slate-200 bg-white">
                <div className="border-b border-slate-200 px-4 py-3"><h2 className="font-semibold">GRNs ({grns.length})</h2></div>
                {grns.length === 0 ? <p className="p-4 text-sm text-slate-500">No GRNs recorded yet.</p> : (
                  <div className="divide-y divide-slate-100">
                    {grns.map((g) => (
                      <div key={g.id} className="px-4 py-3">
                        <div className="flex items-center justify-between">
                          <span className="font-medium">{g.item_description}</span>
                          <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[g.condition] || ""}`}>{g.condition}</span>
                        </div>
                        <div className="mt-1 text-sm text-slate-500">
                          Received: {g.received_qty} / Ordered: {g.ordered_qty} {g.unit} · {g.received_date}
                        </div>
                        {g.notes && <p className="mt-1 text-xs text-slate-500">{g.notes}</p>}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      </main>
    </div>
  );
}

export default function ProcurementPageRoute() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <ProcurementGate />
    </Suspense>
  );
}

function ProcurementGate() {
  const sp = useSearchParams();
  const pid = sp.get("id");
  if (!pid) return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  return <ProcurementPage projectId={pid} />;
}