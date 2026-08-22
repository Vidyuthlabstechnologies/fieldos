"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";

import { Sidebar } from "@/components/Sidebar";
import { listDocuments, uploadDocument, type Document } from "@/lib/api";

const CATEGORIES = [
  "drawing", "specification", "contract", "permit", "report",
  "photo", "correspondence", "safety", "other",
];

function DocumentsPage({ projectId }: { projectId: string }) {
  const [docs, setDocs] = useState<Document[]>([]);
  const [category, setCategory] = useState("");
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notes, setNotes] = useState("");
  const [docCategory, setDocCategory] = useState("other");
  const fileRef = useRef<HTMLInputElement>(null);

  async function refresh() {
    setDocs(await listDocuments(projectId, category || undefined));
  }

  useEffect(() => {
    refresh();
  }, [projectId, category]);

  async function handleUpload(e: React.FormEvent) {
    e.preventDefault();
    const file = fileRef.current?.files?.[0];
    if (!file) return;
    setUploading(true);
    setError(null);
    try {
      await uploadDocument(projectId, file, docCategory, notes || undefined);
      if (fileRef.current) fileRef.current.value = "";
      setNotes("");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploading(false);
    }
  }

  // Group docs by name for version display
  const grouped = docs.reduce<Record<string, Document[]>>((acc, doc) => {
    (acc[doc.name] = acc[doc.name] || []).push(doc);
    return acc;
  }, {});

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6 flex items-center justify-between">
            <h1 className="text-2xl font-bold">Documents & Drawings</h1>
            <Link href={`/project?id=${projectId}`} className="text-sm text-slate-600 underline">
              &larr; Back to project
            </Link>
          </div>

          {/* Upload form */}
          <form onSubmit={handleUpload} className="mb-6 rounded border border-slate-200 bg-white p-4">
            <h2 className="mb-3 font-semibold">Upload Document</h2>
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div>
                <label htmlFor="doc_file" className="mb-1 block text-xs text-slate-500">File</label>
                <input id="doc_file" ref={fileRef} type="file" className="w-full text-sm" required />
              </div>
              <div>
                <label htmlFor="doc_category" className="mb-1 block text-xs text-slate-500">Category</label>
                <select id="doc_category" value={docCategory} onChange={(e) => setDocCategory(e.target.value)} className="w-full rounded border border-slate-300 p-2 text-sm">
                  {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor="doc_notes" className="mb-1 block text-xs text-slate-500">Notes</label>
                <input id="doc_notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" className="w-full rounded border border-slate-300 p-2 text-sm" />
              </div>
            </div>
            <button type="submit" disabled={uploading} className="mt-3 rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
              {uploading ? "Uploading..." : "Upload"}
            </button>
          </form>

          {/* Filter */}
          <div className="mb-4 flex gap-2">
            <select value={category} onChange={(e) => setCategory(e.target.value)} className="rounded border border-slate-300 p-2 text-sm">
              <option value="">All categories</option>
              {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>

          {/* Documents list */}
          {Object.keys(grouped).length === 0 ? (
            <p className="text-center text-sm text-slate-500">No documents uploaded yet.</p>
          ) : (
            <div className="space-y-3">
              {Object.entries(grouped).map(([name, versions]) => (
                <div key={name} className="rounded border border-slate-200 bg-white p-3">
                  <div className="flex items-center justify-between">
                    <span className="font-medium">{name}</span>
                    <span className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-600">
                      v{versions[0].version} &middot; {versions.length} version{versions.length > 1 ? "s" : ""}
                    </span>
                  </div>
                  <div className="mt-1 text-xs text-slate-500">
                    <span className="rounded bg-slate-100 px-1.5 py-0.5">{versions[0].category}</span>
                    {" "}&middot;{" "}
                    {versions[0].file_size ? `${(versions[0].file_size / 1024).toFixed(1)} KB` : ""}
                    {" "}&middot;{" "}
                    {new Date(versions[0].created_at).toLocaleDateString()}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

export default function DocsPage() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center">Loading...</main>}>
      <DocsGate />
    </Suspense>
  );
}

function DocsGate() {
  const sp = useSearchParams();
  const pid = sp.get("id");
  if (!pid) return <main className="flex min-h-screen items-center justify-center">No project selected.</main>;
  return <DocumentsPage projectId={pid} />;
}
