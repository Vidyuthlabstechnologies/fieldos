type Project = {
  id: string;
  name: string;
  client_name?: string | null;
  status: string;
};

export function ProjectCard({ project }: { project: Project }) {
  return (
    <a
      href={`/projects/${project.id}`}
      className="block rounded-lg border border-slate-200 p-4 hover:border-slate-400"
    >
      <h3 className="font-semibold text-slate-900">{project.name}</h3>
      {project.client_name && <p className="text-sm text-slate-500">{project.client_name}</p>}
      <span className="mt-2 inline-block rounded bg-slate-100 px-2 py-0.5 text-xs uppercase text-slate-600">
        {project.status}
      </span>
    </a>
  );
}
