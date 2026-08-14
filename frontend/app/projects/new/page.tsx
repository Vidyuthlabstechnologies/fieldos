"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

import { NewProjectForm } from "@/components/NewProjectForm";
import { createProject, listMyCompanies } from "@/lib/api";

export default function NewProjectPage() {
  const router = useRouter();
  const [companyId, setCompanyId] = useState<string | null>(null);

  useEffect(() => {
    listMyCompanies().then((companies) => setCompanyId(companies[0]?.id ?? null));
  }, []);

  async function handleSubmit(data: { company_id: string; name: string; client_name: string }) {
    const project = await createProject(data);
    router.push(`/projects/${project.id}`);
  }

  if (!companyId) {
    return <main className="mx-auto max-w-md p-6">Loading...</main>;
  }

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="mb-4 text-2xl font-bold">New Project</h1>
      <NewProjectForm companyId={companyId} onSubmit={handleSubmit} />
    </main>
  );
}
