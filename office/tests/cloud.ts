import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// Test helpers against the local FieldOS cloud. The service role only makes
// confirmed accounts; everything else is done as the account itself, through
// the same functions and row-level security the phones use.
const url = process.env.API_URL ?? '';
const anon = process.env.ANON_KEY ?? '';
const service = process.env.SERVICE_ROLE_KEY ?? '';

export const cloudReady = Boolean(url && anon && service);

const opts = { auth: { persistSession: false, autoRefreshToken: false } };

export type Account = { email: string; password: string; id: string; db: SupabaseClient };

export async function account(tag: string): Promise<Account> {
  const email = `office-${tag}-${crypto.randomUUID().slice(0, 8)}@example.com`;
  const password = `Pw-${crypto.randomUUID()}`;
  const admin = createClient(url, service, opts);
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw error;
  const db = createClient(url, anon, opts);
  const signIn = await db.auth.signInWithPassword({ email, password });
  if (signIn.error) throw signIn.error;
  return { email, password, id: data.user.id, db };
}

export async function company(a: Account, name: string): Promise<string> {
  const id = crypto.randomUUID();
  const { error } = await a.db.rpc('ensure_company', { p_company_id: id, p_name: name });
  if (error) throw error;
  return id;
}

export async function site(a: Account, companyId: string, name: string, status = 'active', client?: string) {
  const id = crypto.randomUUID();
  const { error } = await a.db.from('projects').insert({ id, company_id: companyId, name, status, client_name: client ?? null });
  if (error) throw error;
  return id;
}

// One row written as the account itself, so the server's guards apply.
export async function row(a: Account, table: string, values: Record<string, unknown>): Promise<string> {
  const id = (values.id as string | undefined) ?? crypto.randomUUID();
  const { error } = await a.db.from(table).insert({ id, ...values });
  if (error) throw new Error(`${table}: ${error.message}`);
  return id;
}

// Moves a row's raised time back, as the service role (the phones stamp it).
export async function backdate(table: string, id: string, createdAt: string) {
  const admin = createClient(url, service, opts);
  const { error } = await admin.from(table).update({ created_at: createdAt }).eq('id', id);
  if (error) throw new Error(`${table}: ${error.message}`);
}

