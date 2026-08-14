"use client";

import { useEffect, useRef, useState } from "react";

import { ProjectCard } from "@/components/ProjectCard";
import { createCompany, importProject, listMyCompanies, listProjects, type Company, type Project } from "@/lib/api";

export default function ProjectsPage() {
  const [company, setCompany] = useState<Company | null | undefined>(undefined); // undefined = loading
  const [projects, setProjects] = useState<Project[]>([]);
  const [newCompanyName, setNewCompanyName] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const importInputRef = useRef<HTMLInputElement>(null);

  async function handleImportFile(file: File) {
    if (!company) return;
    setError(null);
    setImporting(true);
    try {
      const text = await file.text();
      const data = JSON.parse(text);
      const imported = await importProject(company.id, data);
      setProjects((prev) => [imported, ...prev]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to import project");
    } finally {
      setImporting(false);
      if (importInputRef.current) importInputRef.current.value = "";
    }
  }

  useEffect(() => {
    listMyCompanies()
      .then((companies) => setCompany(companies[0] ?? null))
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load company"));
  }, []);

  useEffect(() => {
    if (company) {
      listProjects(company.id).then(setProjects).catch(console.error);
    }
  }, [company]);

  async function handleCreateCompany() {
    setError(null);
    setCreating(true);
    try {
      const created = await createCompany(newCompanyName);
      setCompany(created);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create company");
    } finally {
      setCreating(false);
    }
  }

  if (company === undefined) {
    return <main className="mx-auto max-w-3xl p-6">Loading...</main>;
  }

  if (company === null) {
    return (
      <main className="mx-auto flex max-w-sm flex-col gap-4 p-6">
        <h1 className="text-2xl font-bold">Set up your company</h1>
        <p className="text-sm text-slate-600">You&apos;re not part of a company yet. Create one to get started.</p>
        <label className="flex flex-col gap-1 text-sm">
          Company name
          <input
            type="text"
            value={newCompanyName}
            onChange={(e) => setNewCompanyName(e.target.value)}
            className="rounded border border-slate-300 p-2"
          />
        </label>
        <button
          onClick={handleCreateCompany}
          disabled={creating || !newCompanyName}
          className="rounded bg-slate-900 px-4 py-2 text-white disabled:opacity-50"
          type="button"
        >
          Create company
        </button>
        {error && <p className="text-sm text-red-600">{error}</p>}
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-3xl p-6">
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Projects</h1>
        <div className="flex gap-2">
          <input
            ref={importInputRef}
            type="file"
            accept="application/json"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) handleImportFile(file);
            }}
          />
          <button
            onClick={() => importInputRef.current?.click()}
            disabled={importing}
            type="button"
            className="rounded border border-slate-300 px-4 py-2 text-sm disabled:opacity-50"
          >
            {importing ? "Importing..." : "Import project"}
          </button>
          <a href="/projects/new" className="rounded bg-slate-900 px-4 py-2 text-white">
            New project
          </a>
        </div>
      </div>
      {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
      <div className="grid gap-3">
        {projects.map((p) => (
          <ProjectCard key={p.id} project={p} />
        ))}
      </div>
    </main>
  );
}
