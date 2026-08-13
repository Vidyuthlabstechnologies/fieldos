"use client";

import { useRouter } from "next/navigation";

import { NewProjectForm } from "@/components/NewProjectForm";
import { createProject } from "@/lib/api";

const DEMO_COMPANY_ID = process.env.NEXT_PUBLIC_DEMO_COMPANY_ID ?? "";

export default function NewProjectPage() {
  const router = useRouter();

  async function handleSubmit(data: { company_id: string; name: string; client_name: string }) {
    const project = await createProject(data);
    router.push(`/projects/${project.id}`);
  }

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="mb-4 text-2xl font-bold">New Project</h1>
      <NewProjectForm companyId={DEMO_COMPANY_ID} onSubmit={handleSubmit} />
    </main>
  );
}
