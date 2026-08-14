"use client";

import { useEffect, useState } from "react";

import { ProjectCard } from "@/components/ProjectCard";
import { createCompany, listMyCompanies, listProjects, type Company, type Project } from "@/lib/api";

export default function ProjectsPage() {
  const [company, setCompany] = useState<Company | null | undefined>(undefined); // undefined = loading
  const [projects, setProjects] = useState<Project[]>([]);
  const [newCompanyName, setNewCompanyName] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
        <a href="/projects/new" className="rounded bg-slate-900 px-4 py-2 text-white">
          New project
        </a>
      </div>
      <div className="grid gap-3">
        {projects.map((p) => (
          <ProjectCard key={p.id} project={p} />
        ))}
      </div>
    </main>
  );
}
