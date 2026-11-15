import { useEffect, useState } from 'react';

// Pages live in the address's #part, so the static host needs no rewrite
// rules and a link to a site can be shared: #/site/<id>/<tab>.
export type Route = { page: 'sites' } | { page: 'site'; id: string; tab: string };

export function parseRoute(hash: string): Route {
  const m = /^#\/site\/([0-9a-f-]{36})(?:\/([a-z_]+))?$/i.exec(hash);
  return m ? { page: 'site', id: m[1].toLowerCase(), tab: m[2] ?? 'rfis' } : { page: 'sites' };
}

export function siteHref(id: string, tab?: string): string {
  return `#/site/${id}${tab ? `/${tab}` : ''}`;
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash));
  useEffect(() => {
    const on = () => setRoute(parseRoute(window.location.hash));
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return route;
}
