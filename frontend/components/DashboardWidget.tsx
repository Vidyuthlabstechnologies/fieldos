import type { Dashboard } from "@/lib/api";

export function DashboardWidget({ dashboard }: { dashboard: Dashboard }) {
  return (
    <div className="grid grid-cols-3 gap-3">
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.percent_tasks_complete}%</div>
        <div className="text-xs text-slate-500">Tasks complete</div>
      </div>
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.dpr_streak_days}</div>
        <div className="text-xs text-slate-500">Day DPR streak</div>
      </div>
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.open_issue_count}</div>
        <div className="text-xs text-slate-500">Open issues</div>
      </div>
    </div>
  );
}
