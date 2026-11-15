import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// The office app talks to the same FieldOS cloud as the phones, with the
// public anon key only. Every read and write goes through the server's
// row-level security and guard triggers, so this app can never see or do
// more than the signed-in person could on their phone.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const configured = Boolean(url && anonKey);

export const supabase: SupabaseClient | null = configured
  ? createClient(url!, anonKey!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
    })
  : null;

// Where Google sends the person back after sign-in: this app's own page.
// The address must be on the Supabase Auth redirect list.
export function returnUrl(): string {
  return window.location.origin + import.meta.env.BASE_URL;
}
