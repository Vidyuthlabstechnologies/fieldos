"use client";

import { useState } from "react";

type NewProjectData = { company_id: string; name: string; client_name: string };

export function NewProjectForm({
  companyId,
  onSubmit,
}: {
  companyId: string;
  onSubmit: (data: NewProjectData) => void;
}) {
  const [name, setName] = useState("");
  const [clientName, setClientName] = useState("");

  function handleSubmit() {
    onSubmit({ company_id: companyId, name, client_name: clientName });
  }

  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Project name
        <input
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
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
        Create project
      </button>
    </div>
  );
}
