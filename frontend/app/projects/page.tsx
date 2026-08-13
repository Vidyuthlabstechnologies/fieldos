"use client";

import { useEffect, useState } from "react";

import { ProjectCard } from "@/components/ProjectCard";
import { listProjects, type Project } from "@/lib/api";

const DEMO_COMPANY_ID = process.env.NEXT_PUBLIC_DEMO_COMPANY_ID ?? "";

export default function ProjectsPage() {
  const [projects, setProjects] = useState<Project[]>([]);

  useEffect(() => {
    listProjects(DEMO_COMPANY_ID).then(setProjects).catch(console.error);
  }, []);

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
