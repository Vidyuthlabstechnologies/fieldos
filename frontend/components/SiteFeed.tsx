import type { FeedItem } from "@/lib/api";

export function SiteFeed({ items }: { items: FeedItem[] }) {
  return (
    <ul className="flex flex-col gap-2">
      {items.map((item) => (
        <li key={`${item.type}-${item.id}`} className="rounded border border-slate-200 p-2">
          <span className="mr-2 rounded bg-slate-100 px-1.5 py-0.5 text-xs uppercase text-slate-500">
            {item.type}
          </span>
          {item.summary}
        </li>
      ))}
    </ul>
  );
}
