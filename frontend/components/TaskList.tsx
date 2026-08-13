import type { Task } from "@/lib/api";

const STATUSES: Task["status"][] = ["todo", "in_progress", "done", "blocked"];

export function TaskList({
  tasks,
  onStatusChange,
}: {
  tasks: Task[];
  onStatusChange: (taskId: string, status: Task["status"]) => void;
}) {
  return (
    <ul className="flex flex-col gap-2">
      {tasks.map((task) => (
        <li key={task.id} className="flex items-center justify-between rounded border border-slate-200 p-2">
          <span>{task.title}</span>
          <select
            value={task.status}
            onChange={(e) => onStatusChange(task.id, e.target.value as Task["status"])}
            className="rounded border border-slate-300 p-1 text-sm"
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </li>
      ))}
    </ul>
  );
}
