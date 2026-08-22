"use client";

import { Suspense, useEffect, useRef, useState, Fragment } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import {
  createMaterialEntry,
  getMaterialSummary,
  listMaterialEntries,
  listMaterialPhotos,
  uploadMaterialPhoto,
  type MaterialEntry,
  type MaterialPhoto,
  type MaterialSummary,
} from "@/lib/api";

const CATEGORIES = [
  "cement", "sand", "aggregate", "steel", "brick", "timber",
  "pipe", "electrical", "plumbing", "paint", "other",
];

const UNITS = ["kg", "quintal", "ton", "bag", "cu.m", "cu.ft", "nos", "litre", "ft", "m", "sq.m", "sq.ft"];

function MaterialPage({ projectId }: { projectId: string }) {
  const [entries, setEntries] = useState<MaterialEntry[]>([]);
  const [summary, setSummary] = useState<MaterialSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [expandedEntry, setExpandedEntry] = useState<string | null>(null);
  const [entryPhotos, setEntryPhotos] = useState<Record<string, MaterialPhoto[]>>({});
  const [uploadingPhoto, setUploadingPhoto] = useState<string | null>(null);

  // Form state
  const [itemName, setItemName] = useState("");
  const [category, setCategory] = useState("other");
  const [quantity, setQuantity] = useState("");
  const [unit, setUnit] = useState("nos");
  const [supplier, setSupplier] = useState("");
  const [cost, setCost] = useState("");
  const [notes, setNotes] = useState("");
  const [entryDate, setEntryDate] = useState(() => new Date().toISOString().slice(0, 10));
  const fileRef = useRef<HTMLInputElement>(null);

  async function refresh() {
    const [e, s] = await Promise.all([
      listMaterialEntries(projectId),
      getMaterialSummary(projectId),
    ]);
    setEntries(e);
    setSummary(s);
  }

  useEffect(() => {
    refresh().catch(console.error);
  }, [projectId]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!itemName.trim() || !quantity.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createMaterialEntry(projectId, {
        entry_date: entryDate,
        item_name: itemName,
        category,
        quantity,
        unit,
        supplier: supplier || undefined,
        cost: cost || undefined,
        notes: notes || undefined,
      });
      setItemName("");
      setQuantity("");
      setSupplier("");
      setCost("");
      setNotes("");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to add entry");
    } finally {
      setSubmitting(false);
    }
  }

  async function handlePhotoUpload(entryId: string, e: React.FormEvent) {
    e.preventDefault();
    const file = fileRef.current?.files?.[0];
    if (!file) return;
    setUploadingPhoto(entryId);
    try {
      await uploadMaterialPhoto(projectId, entryId, file);
      fileRef.current!.value = "";
      loadPhotos(entryId);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploadingPhoto(null);
    }
  }

  async function loadPhotos(entryId: string) {
    try {
      const photos = await listMaterialPhotos(projectId, entryId);
      setEntryPhotos({ ...entryPhotos, [entryId]: photos });
    } catch (err) {
      console.error(err);
    }
  }

  function toggleExpand(entryId: string) {
    setExpandedEntry(expandedEntry === entryId ? null : entryId);
    if (expandedEntry !== entryId && !entryPhotos[entryId]) {
      loadPhotos(entryId);
    }
  }

  const totalCost = summary.reduce((sum, s) => sum + parseFloat(s.total_cost || "0"), 0);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Materials</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">
              &larr; Back to project
            </Link>
          </div>

          {/* Summary cards */}
          {summary.length > 0 && (
            <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Total Cost</p>
                <p className="text-lg font-semibold">₹{totalCost.toLocaleString()}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Total Entries</p>
                <p className="text-lg font-semibold">{entries.length}</p>
              </div>
              <div className="rounded border border-slate-200 bg-white p-4">
                <p className="text-xs text-slate-500">Categories</p>
                <p className="text-lg font-semibold">{summary.length}</p>
              </div>
            </div>
          )}

          {/* Add form */}
          <form onSubmit={handleSubmit} className="mb-8 rounded border border-slate-200 bg-white p-4">
            <h2 className="mb-3 font-semibold">Add Material Entry</h2>
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div>
                <label htmlFor="entry_date" className="mb-1 block text-xs text-slate-500">Date</label>
                <input
                  id="entry_date"
                  type="date"
                  value={entryDate}
                  onChange={(e) => setEntryDate(e.target.value)}
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                  required
                />
              </div>
              <div>
                <label htmlFor="item_name" className="mb-1 block text-xs text-slate-500">Item Name</label>
                <input
                  id="item_name"
                  value={itemName}
                  onChange={(e) => setItemName(e.target.value)}
                  placeholder="e.g. OPC 53 Cement"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                  required
                />
              </div>
              <div>
                <label htmlFor="category" className="mb-1 block text-xs text-slate-500">Category</label>
                <select
                  id="category"
                  value={category}
                  onChange={(e) => setCategory(e.target.value)}
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                >
                  {CATEGORIES.map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="quantity" className="mb-1 block text-xs text-slate-500">Quantity</label>
                <input
                  id="quantity"
                  type="number"
                  step="0.001"
                  value={quantity}
                  onChange={(e) => setQuantity(e.target.value)}
                  placeholder="0"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                  required
                />
              </div>
              <div>
                <label htmlFor="unit" className="mb-1 block text-xs text-slate-500">Unit</label>
                <select
                  id="unit"
                  value={unit}
                  onChange={(e) => setUnit(e.target.value)}
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                >
                  {UNITS.map((u) => (
                    <option key={u} value={u}>{u}</option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="supplier" className="mb-1 block text-xs text-slate-500">Supplier</label>
                <input
                  id="supplier"
                  value={supplier}
                  onChange={(e) => setSupplier(e.target.value)}
                  placeholder="Optional"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                />
              </div>
              <div>
                <label htmlFor="cost" className="mb-1 block text-xs text-slate-500">Cost (₹)</label>
                <input
                  id="cost"
                  type="number"
                  step="0.01"
                  value={cost}
                  onChange={(e) => setCost(e.target.value)}
                  placeholder="Optional"
                  className="w-full rounded border border-slate-300 p-2 text-sm"
                />
              </div>
              <div className="sm:col-span-2">
                <label htmlFor="notes" className="mb-1 block text-xs text-slate-500">Notes</label>
                <input
                  id="notes"
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
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
              {submitting ? "Adding..." : "Add Entry"}
            </button>
          </form>

          {/* Entries table */}
          {entries.length > 0 && (
            <div className="rounded border border-slate-200 bg-white overflow-hidden">
              <table className="w-full text-left text-sm" aria-label="Material entries">
                <thead className="border-b border-slate-200 bg-slate-50 text-xs text-slate-600">
                  <tr>
                    <th className="px-3 py-2">Date</th>
                    <th className="px-3 py-2">Item</th>
                    <th className="px-3 py-2">Category</th>
                    <th className="px-3 py-2 text-right">Qty</th>
                    <th className="px-3 py-2">Unit</th>
                    <th className="px-3 py-2">Supplier</th>
                    <th className="px-3 py-2 text-right">Cost</th>
                    <th className="px-3 py-2">Photos</th>
                    <th className="px-3 py-2"></th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry) => (
                    <Fragment key={entry.id}>
                      <tr className={`border-b border-slate-100 last:border-0 cursor-pointer hover:bg-slate-50 ${expandedEntry === entry.id ? "bg-slate-50" : ""}`} onClick={() => toggleExpand(entry.id)}>
                        <td className="px-3 py-2 whitespace-nowrap">{entry.entry_date}</td>
                        <td className="px-3 py-2 font-medium">{entry.item_name}</td>
                        <td className="px-3 py-2">
                          <span className="rounded bg-slate-100 px-2 py-0.5 text-xs">{entry.category}</span>
                        </td>
                        <td className="px-3 py-2 text-right">{entry.quantity}</td>
                        <td className="px-3 py-2">{entry.unit}</td>
                        <td className="px-3 py-2 text-slate-500">{entry.supplier || "\u2014"}</td>
                        <td className="px-3 py-2 text-right">
                          {entry.cost ? `₹${parseFloat(entry.cost).toLocaleString()}` : "\u2014"}
                        </td>
                        <td className="px-3 py-2">
                          <span className="text-xs text-slate-500">{entryPhotos[entry.id]?.length || 0} photos</span>
                        </td>
                        <td className="px-3 py-2 text-center">
                          <span className="text-slate-400">{expandedEntry === entry.id ? "\u25BC" : "\u25B6"}</span>
                        </td>
                      </tr>
                      {expandedEntry === entry.id && (
                        <tr className="bg-slate-50">
                          <td colSpan={9} className="p-0">
                            <div className="p-4 border-t border-slate-200">
                              <div className="mb-2 flex items-center gap-2">
                                <span className="font-medium">Photos for {entry.item_name}</span>
                                <form onSubmit={(e) => handlePhotoUpload(entry.id, e)} className="flex items-center gap-2">
                                  <input ref={fileRef} type="file" accept="image/*" className="sr-only" id={`file-${entry.id}`} />
                                  <label htmlFor={`file-${entry.id}`} className="rounded border border-slate-300 px-3 py-1.5 text-xs text-slate-600 hover:bg-slate-100 cursor-pointer">
                                    📷 Add Photo
                                  </label>
                                  <button type="submit" disabled={uploadingPhoto === entry.id} className="rounded bg-slate-900 px-3 py-1.5 text-xs text-white disabled:opacity-50">
                                    {uploadingPhoto === entry.id ? "Uploading..." : "Upload"}
                                  </button>
                                </form>
                              </div>
                              {entryPhotos[entry.id] && entryPhotos[entry.id].length > 0 ? (
                                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 md:grid-cols-6">
                                  {entryPhotos[entry.id].map((photo) => (
                                    <div key={photo.id} className="relative group">
                                      <img
                                        src={photo.photo_url}
                                        alt={photo.caption || "Material photo"}
                                        className="w-full aspect-square object-cover rounded border border-slate-200"
                                      />
                                      {photo.caption && (
                                        <div className="absolute bottom-0 left-0 right-0 bg-black/60 text-white text-xs p-1 truncate">{photo.caption}</div>
                                      )}
                                    </div>
                                  ))}
                                </div>
                              ) : (
                                <p className="text-sm text-slate-500">No photos uploaded yet.</p>
                              )}
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {entries.length === 0 && (
            <p className="text-center text-sm text-slate-500">No material entries yet.</p>
          )}
        </div>
      </main>
    </div>
  );
}

export default function MaterialsPage() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <MaterialsGate />
    </Suspense>
  );
}

function MaterialsGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) {
    return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  }
  return <MaterialPage projectId={projectId} />;
}