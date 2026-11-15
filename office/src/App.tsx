import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { configured, supabase } from './supabase';
import { t } from './strings';
import { SignIn } from './SignIn';
import { Sites } from './Sites';
import { SitePage } from './SitePage';
import { useRoute } from './route';

export function App() {
  const route = useRoute();
  const [session, setSession] = useState<Session | null | undefined>(undefined);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  if (!configured || !supabase) {
    return (
      <main className="center">
        <h1>{t.appName}</h1>
        <p role="alert">{t.notConfigured}</p>
      </main>
    );
  }
  if (session === undefined) {
    return (
      <main className="center">
        <p>{t.loading}</p>
      </main>
    );
  }
  if (!session) return <SignIn db={supabase} />;
  if (route.page === 'site') return <SitePage db={supabase} session={session} id={route.id} tab={route.tab} />;
  return <Sites db={supabase} session={session} />;
}
