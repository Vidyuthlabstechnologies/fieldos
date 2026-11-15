import { useState, type FormEvent } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { returnUrl } from './supabase';
import { t } from './strings';

export function SignIn({ db }: { db: SupabaseClient }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await db.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) setError(error.status === 400 ? t.signInFailed : t.loadFailed);
  }

  async function google() {
    setError(null);
    const { error } = await db.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: returnUrl() } });
    if (error) setError(t.loadFailed);
  }

  return (
    <main className="center">
      <div className="card signin">
        <h1>{t.appName}</h1>
        <p className="muted">{t.tagline}</p>
        <form onSubmit={submit}>
          <label>
            {t.email}
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              data-testid="email"
            />
          </label>
          <label>
            {t.password}
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              data-testid="password"
            />
          </label>
          {error && (
            <p role="alert" className="error">
              {error}
            </p>
          )}
          <button type="submit" disabled={busy} data-testid="sign-in">
            {busy ? t.signingIn : t.signIn}
          </button>
        </form>
        <button type="button" className="secondary" onClick={google} data-testid="google">
          {t.orGoogle}
        </button>
        <p className="muted small">{t.signInHelp}</p>
      </div>
    </main>
  );
}
