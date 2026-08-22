"use client";

import { useState } from "react";

type NewProjectData = { company_id: string; name: string; client_name: string };

export function NewProjectForm({
  companyId,
  onSubmit,
}: {
  companyId: string;
  onSubmit: (data: NewProjectData) => void | Promise<void>;
}) {
  const [name, setName] = useState("");
  const [clientName, setClientName] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) {
      setError("Project name is required");
      return;
    }
    setError(null);
    setSubmitting(true);
    try {
      await onSubmit({ company_id: companyId, name, client_name: clientName });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create project");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Project name
        <input
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Client
        <input
          value={clientName}
          onChange={(e) => setClientName(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button type="submit" disabled={submitting} className="rounded bg-slate-900 px-4 py-2 text-white disabled:opacity-50">
        {submitting ? "Creating..." : "Create project"}
      </button>
    </form>
  );
}
