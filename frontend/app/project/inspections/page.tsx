"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import {
  createInspection,
  createInspectionItem,
  listInspectionItems,
  listInspectionPhotos,
  listInspections,
  uploadInspectionPhoto,
  type Inspection,
  type InspectionItem,
  type InspectionPhoto,
} from "@/lib/api";

const INSPECTION_TYPES = ["safety", "quality", "structural", "mep", "environmental", "final", "other"];

function InspectionsPage({ projectId }: { projectId: string }) {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [selectedInsp, setSelectedInsp] = useState<Inspection | null>(null);
  const [items, setItems] = useState<InspectionItem[]>([]);
  const [photos, setPhotos] = useState<InspectionPhoto[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [tab, setTab] = useState<"list" | "create">("list");
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  // Create inspection form
  const [inspTitle, setInspTitle] = useState("");
  const [inspType, setInspType] = useState("quality");
  const [inspDate, setInspDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [inspNotes, setInspNotes] = useState("");

  // Add item form
  const [itemDesc, setItemDesc] = useState("");
  const [itemStatus, setItemStatus] = useState("pending");
  const [itemNotes, setItemNotes] = useState("");

  async function refresh() {
    setInspections(await listInspections(projectId));
  }

  useEffect(() => { refresh(); }, [projectId]);

  useEffect(() => {
    if (selectedInsp) {
      listInspectionItems(selectedInsp.id).then(setItems).catch(console.error);
      loadPhotos();
    }
  }, [selectedInsp]);

  async function loadPhotos() {
    if (selectedInsp) {
      try {
        const p = await listInspectionPhotos(selectedInsp.id);
        setPhotos(p);
      } catch (err) {
        console.error(err);
      }
    }
  }

  async function handleCreateInspection(e: React.FormEvent) {
    e.preventDefault();
    if (!inspTitle.trim()) return;
    setSubmitting(true);
    try {
      const newInsp = await createInspection(projectId, { title: inspTitle, inspection_type: inspType, scheduled_date: inspDate || undefined });
      setInspTitle(""); setInspNotes("");
      setSelectedInsp(newInsp);
      refresh();
      setTab("list");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleAddItem(e: React.FormEvent) {
    e.preventDefault();
    if (!selectedInsp || !itemDesc.trim()) return;
    setSubmitting(true);
    try {
      await createInspectionItem(selectedInsp.id, { item_description: itemDesc, status: itemStatus, notes: itemNotes || undefined });
      setItemDesc(""); setItemNotes("");
      listInspectionItems(selectedInsp.id).then(setItems).catch(console.error);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  async function handlePhotoUpload(e: React.FormEvent) {
    e.preventDefault();
    const file = fileRef.current?.files?.[0];
    if (!file || !selectedInsp) return;
    setUploadingPhoto(true);
    try {
      await uploadInspectionPhoto(selectedInsp.id, file);
      fileRef.current!.value = "";
      loadPhotos();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploadingPhoto(false);
    }
  }

  const statusColor: Record<string, string> = {
    pending: "bg-amber-100 text-amber-700",
    in_progress: "bg-blue-100 text-blue-700",
    completed: "bg-green-100 text-green-700",
    pass: "bg-green-100 text-green-700",
    fail: "bg-red-100 text-red-700",
    na: "bg-slate-100 text-slate-600",
  };

  const overallColor: Record<string, string> = {
    pass: "bg-green-100 text-green-700",
    fail: "bg-red-100 text-red-700",
    partial: "bg-amber-100 text-amber-700",
  };

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Inspections & Quality</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">&larr; Back</Link>
          </div>

          {error && <p className="mb-3 text-sm text-red-600">{error}</p>}

          {/* Tab switcher */}
          <div className="mb-4 flex gap-2 border-b border-slate-200 pb-2">
            <button onClick={() => { setTab("list"); setSelectedInsp(null); }} className={`px-3 py-1.5 text-sm font-medium rounded ${tab === "list" ? "bg-slate-900 text-white" : "text-slate-600 hover:bg-slate-100"}`}>
              List Inspections
            </button>
            <button onClick={() => setTab("create")} className={`px-3 py-1.5 text-sm font-medium rounded ${tab === "create" ? "bg-slate-900 text-white" : "text-slate-600 hover:bg-slate-100"}`}>
              New Inspection
            </button>
          </div>

          {/* Create Inspection Form */}
          {tab === "create" && (
            <form onSubmit={handleCreateInspection} className="mb-6 rounded border border-slate-200 bg-white p-4">
              <h2 className="mb-3 font-semibold">New Inspection</h2>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div className="sm:col-span-2">
                  <label htmlFor="insp_title" className="mb-1 block text-xs text-slate-500">Title</label>
                  <input id="insp_title" value={inspTitle} onChange={(e) => setInspTitle(e.target.value)} placeholder="e.g. Foundation Pour Quality Check" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                </div>
                <div>
                  <label htmlFor="insp_type" className="mb-1 block text-xs text-slate-500">Type</label>
                  <select id="insp_type" value={inspType} onChange={(e) => setInspType(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                    {INSPECTION_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </div>
                <div>
                  <label htmlFor="insp_date" className="mb-1 block text-xs text-slate-500">Scheduled Date</label>
                  <input id="insp_date" type="date" value={inspDate} onChange={(e) => setInspDate(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm" />
                </div>
                <div className="sm:col-span-3">
                  <label htmlFor="insp_notes" className="mb-1 block text-xs text-slate-500">Notes</label>
                  <textarea id="insp_notes" value={inspNotes} onChange={(e) => setInspNotes(e.target.value)} rows={2} placeholder="Optional" className="w-full rounded border border-slate-300 p-2 text-sm" />
                </div>
              </div>
              <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                {submitting ? "Creating..." : "Create Inspection"}
              </button>
            </form>
          )}

          {/* Inspections List */}
          {tab === "list" && (
            <div className="rounded border border-slate-200 bg-white">
              <div className="border-b border-slate-200 px-4 py-3">
                <h2 className="font-semibold">Inspections ({inspections.length})</h2>
              </div>
              {inspections.length === 0 ? (
                <p className="p-4 text-sm text-slate-500">No inspections yet. Create one to get started.</p>
              ) : (
                <div className="divide-y divide-slate-100">
                  {inspections.map((insp) => (
                    <button
                      key={insp.id}
                      type="button"
                      onClick={() => setSelectedInsp(insp)}
                      className={`w-full px-4 py-3 text-left transition ${selectedInsp?.id === insp.id ? "bg-slate-50 border-l-4 border-l-slate-900" : "hover:bg-slate-50"}`}
                    >
                      <div className="flex items-center justify-between">
                        <span className="font-medium">{insp.title}</span>
                        <span className={`rounded px-1.5 py-0.5 text-xs ${statusColor[insp.status] || ""}`}>{insp.status}</span>
                      </div>
                      <div className="mt-1 flex items-center gap-3 text-xs text-slate-500">
                        <span className="rounded bg-slate-100 px-1.5 py-0.5">{insp.inspection_type}</span>
                        {insp.scheduled_date && <span>📅 {insp.scheduled_date}</span>}
                        {insp.completed_date && <span>✓ {insp.completed_date}</span>}
                        {insp.overall_result && (
                          <span className={`rounded px-1.5 py-0.5 ${overallColor[insp.overall_result] || ""}`}>{insp.overall_result}</span>
                        )}
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Checklist Items (when inspection selected) */}
          {selectedInsp && tab === "list" && (
            <div className="mt-6 rounded border border-slate-200 bg-white">
              <div className="border-b border-slate-200 px-4 py-3 flex items-center justify-between">
                <h2 className="font-semibold">Checklist: {selectedInsp.title}</h2>
                <span className={`rounded px-2 py-0.5 text-xs ${statusColor[selectedInsp.status] || ""}`}>{selectedInsp.status}</span>
              </div>

              {/* Photos section */}
              <div className="border-b border-slate-200 p-4">
                <div className="mb-2 flex items-center justify-between">
                  <span className="font-medium">Photos ({photos.length})</span>
                  <form onSubmit={handlePhotoUpload} className="flex items-center gap-2">
                    <input ref={fileRef} type="file" accept="image/*" className="sr-only" id="insp-photo-upload" />
                    <label htmlFor="insp-photo-upload" className="rounded border border-slate-300 px-3 py-1.5 text-xs text-slate-600 hover:bg-slate-100 cursor-pointer">
                      📷 Add Photo
                    </label>
                    <button type="submit" disabled={uploadingPhoto} className="rounded bg-slate-900 px-3 py-1.5 text-xs text-white disabled:opacity-50">
                      {uploadingPhoto ? "Uploading..." : "Upload"}
                    </button>
                  </form>
                </div>
                {photos.length > 0 && (
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 md:grid-cols-6">
                    {photos.map((photo) => (
                      <div key={photo.id} className="relative group">
                        <img
                          src={photo.photo_url}
                          alt={photo.caption || "Inspection photo"}
                          className="w-full aspect-square object-cover rounded border border-slate-200"
                        />
                        {photo.caption && (
                          <div className="absolute bottom-0 left-0 right-0 bg-black/60 text-white text-xs p-1 truncate">{photo.caption}</div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
                {photos.length === 0 && <p className="text-sm text-slate-500">No photos uploaded yet.</p>}
              </div>

              {/* Add item form */}
              <form onSubmit={handleAddItem} className="border-b border-slate-200 p-4">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
                  <div className="sm:col-span-2">
                    <label htmlFor="item_desc" className="mb-1 block text-xs text-slate-500">Item Description</label>
                    <input id="item_desc" value={itemDesc} onChange={(e) => setItemDesc(e.target.value)} placeholder="e.g. Rebar spacing as per drawing" className="w-full rounded border border-slate-300 p-2 text-sm" required />
                  </div>
                  <div>
                    <label htmlFor="item_status" className="mb-1 block text-xs text-slate-500">Status</label>
                    <select id="item_status" value={itemStatus} onChange={(e) => setItemStatus(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                      {["pending", "pass", "fail", "na"].map((s) => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </div>
                  <div>
                    <label htmlFor="item_notes" className="mb-1 block text-xs text-slate-500">Notes</label>
                    <input id="item_notes" value={itemNotes} onChange={(e) => setItemNotes(e.target.value)} placeholder="Optional" className="w-full rounded border border-slate-300 p-2 text-sm" />
                  </div>
                </div>
                <button type="submit" disabled={submitting} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
                  {submitting ? "Adding..." : "Add Checklist Item"}
                </button>
              </form>

              {/* Items list */}
              {items.length === 0 ? (
                <p className="p-4 text-sm text-slate-500">No checklist items yet.</p>
              ) : (
                <div className="divide-y divide-slate-100">
                  {items.map((item) => (
                    <div key={item.id} className="px-4 py-3">
                      <div className="flex items-start gap-3">
                        <span className={`mt-0.5 rounded px-1.5 py-0.5 text-xs ${statusColor[item.status] || ""}`}>{item.status}</span>
                        <div className="flex-1">
                          <p className="font-medium text-sm">{item.item_description}</p>
                          {item.notes && <p className="mt-0.5 text-xs text-slate-500">{item.notes}</p>}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

export default function InspectionsPageRoute() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <InspectionsGate />
    </Suspense>
  );
}

function InspectionsGate() {
  const sp = useSearchParams();
  const pid = sp.get("id");
  if (!pid) return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  return <InspectionsPage projectId={pid} />;
}