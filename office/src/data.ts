import type { SupabaseClient } from '@supabase/supabase-js';

export type Company = { id: string; name: string; role: string };
export type Site = {
  id: string;
  name: string;
  client_name: string | null;
  status: string;
  start_date: string | null;
  end_date: string | null;
};

// The companies this person belongs to, by name.
export async function loadCompanies(db: SupabaseClient, userId: string): Promise<Company[]> {
  const { data, error } = await db
    .from('company_members')
    .select('company_id, role, companies(name)')
    .eq('user_id', userId);
  if (error) throw error;
  type Row = { company_id: string; role: string; companies: { name: string } | { name: string }[] | null };
  return ((data ?? []) as Row[])
    .map((r) => {
      const c = Array.isArray(r.companies) ? r.companies[0] : r.companies;
      return { id: r.company_id, name: c?.name ?? 'Company', role: r.role };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

// The sites of one company this person may see (the server decides which).
export async function loadSites(db: SupabaseClient, companyId: string): Promise<Site[]> {
  const { data, error } = await db
    .from('projects')
    .select('id, name, client_name, status, start_date, end_date')
    .eq('company_id', companyId)
    .order('name');
  if (error) throw error;
  return sortSites((data ?? []) as Site[]);
}

const STATUS_ORDER: Record<string, number> = { active: 0, planning: 1, on_hold: 2, completed: 3 };

// Running sites first, then planned, on hold, completed; by name within each.
export function sortSites(sites: Site[]): Site[] {
  return [...sites].sort(
    (a, b) => (STATUS_ORDER[a.status] ?? 9) - (STATUS_ORDER[b.status] ?? 9) || a.name.localeCompare(b.name),
  );
}

export function matchesSearch(s: Site, q: string): boolean {
  const needle = q.trim().toLowerCase();
  if (!needle) return true;
  return s.name.toLowerCase().includes(needle) || (s.client_name ?? '').toLowerCase().includes(needle);
}

// Remembers the last company picked, per browser.
const LAST = 'fieldos-office-company';
export function lastCompany(): string | null {
  try {
    return localStorage.getItem(LAST);
  } catch {
    return null;
  }
}
export function rememberCompany(id: string): void {
  try {
    localStorage.setItem(LAST, id);
  } catch {
    /* private window: not remembered */
  }
}
