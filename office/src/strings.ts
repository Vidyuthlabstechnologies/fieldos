// English labels. Other languages come from the phone app's label tables in
// a later step, so keep every label here (no text written inline in pages).
export const t = {
  appName: 'FieldOS Office',
  tagline: 'Your sites, from the office.',
  notConfigured: 'This copy of FieldOS Office has no cloud address set. See office/README.md.',
  email: 'Email',
  password: 'Password',
  signIn: 'Sign in',
  signingIn: 'Signing in…',
  orGoogle: 'Sign in with Google',
  signInHelp: 'Use the same account you sign in with on the FieldOS app.',
  signOut: 'Sign out',
  signInFailed: 'Email or password is wrong.',
  loading: 'Loading…',
  loadFailed: 'Could not load. Check your internet and try again.',
  tryAgain: 'Try again',
  company: 'Company',
  noCompany: 'This account isn’t in a company yet. Open the FieldOS app and create or join one first.',
  sites: 'Sites',
  noSites: 'No sites in this company yet.',
  searchSites: 'Search sites',
  noMatch: 'No site matches that search.',
  client: 'Client',
  dates: 'Dates',
  status: 'Status',
  statusLabels: {
    planning: 'Planning',
    active: 'Running',
    on_hold: 'On hold',
    completed: 'Completed',
  } as Record<string, string>,
  roleLabels: {
    owner: 'Owner',
    project_manager: 'Project manager',
    site_engineer: 'Site engineer',
    accounts: 'Accounts',
    storekeeper: 'Storekeeper',
    viewer: 'Viewer',
  } as Record<string, string>,
};

export function statusLabel(s: string): string {
  return t.statusLabels[s] ?? s;
}

export function roleLabel(r: string): string {
  return t.roleLabels[r] ?? r;
}
