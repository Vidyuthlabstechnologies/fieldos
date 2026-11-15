const fmt = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });

/** "2026-11-15" (or a timestamp) as the browser's short date; '' when empty. */
export function day(d: string | null): string {
  if (!d) return '';
  const [y, m, dd] = d.slice(0, 10).split('-').map(Number);
  return fmt.format(new Date(y, m - 1, dd));
}
