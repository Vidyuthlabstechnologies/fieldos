import { expect, test } from '@playwright/test';
import { account, backdate, cloudReady, company, row, site } from './cloud';

test.skip(!cloudReady, 'needs the local FieldOS cloud (see playwright.config.ts)');

const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);
const daysAhead = (n: number) => new Date(Date.now() + n * 86_400_000).toISOString().slice(0, 10);

test('a site’s dashboard and registers show what the site raised', async ({ page }) => {
  const a = await account('reg');
  const b = await account('other');
  const co = await company(a, 'Asha Builders');
  const s = await site(a, co, 'Tower A', 'active', 'Sunrise Homes');
  const bSite = await site(b, await company(b, 'Bharat Infra'), 'Secret Site');
  const me = { raised_by: a.id, project_id: s };

  // Drawings: one with an approved and a pending revision, one with none approved.
  const d1 = await row(a, 'site_drawings', { project_id: s, number: 'A-101', title: 'Ground floor plan', created_by: a.id });
  const d2 = await row(a, 'site_drawings', { project_id: s, number: 'S-201', title: 'Footing details', discipline: 'structural', created_by: a.id });
  await row(a, 'site_drawing_revisions', {
    project_id: s, drawing_id: d1, rev: 'B', file_path: `${s}/d/b.pdf`, mime_type: 'application/pdf', uploaded_by: a.id,
  });
  const v2 = await row(a, 'site_drawing_revisions', {
    project_id: s, drawing_id: d2, rev: 'A', file_path: `${s}/d/a.pdf`, mime_type: 'application/pdf', uploaded_by: a.id,
  });
  const ok = await a.db
    .from('site_drawing_revisions')
    .update({ status: 'approved', decided_by: a.id, decided_at: new Date().toISOString() })
    .eq('id', v2);
  if (ok.error) throw ok.error;

  // RFIs: RFI-1 overdue, RFI-2 answered, RFI-3 closed (hidden until asked).
  const r1 = await row(a, 'site_rfis', { ...me, question: 'Lintel level at grid C?', asked_of: 'Architect', due_on: daysAgo(3) });
  const r2 = await row(a, 'site_rfis', { ...me, question: 'Tile make for lobby?', due_on: daysAhead(5) });
  const r3 = await row(a, 'site_rfis', { ...me, question: 'Old question', status: 'closed' });
  await backdate('site_rfis', r1, '2026-01-01T00:00:00Z');
  await backdate('site_rfis', r2, '2026-01-02T00:00:00Z');
  await backdate('site_rfis', r3, '2026-01-03T00:00:00Z');

  // Submittals: one overdue for review, one to revise.
  const s1 = await row(a, 'site_submittals', { ...me, title: 'Waterproofing membrane', kind: 'product_data', required_by: daysAgo(2) });
  const s2 = await row(a, 'site_submittals', { ...me, title: 'Rebar shop drawings', kind: 'shop_drawing' });
  await backdate('site_submittals', s1, '2026-01-01T00:00:00Z');
  await backdate('site_submittals', s2, '2026-01-02T00:00:00Z');

  // Defects: a critical one and a minor one.
  const f1 = await row(a, 'site_defects', { ...me, description: 'Crack in column C4', severity: 'critical', location: 'Level 2', due_on: daysAgo(1) });
  const f2 = await row(a, 'site_defects', { ...me, description: 'Paint patch', severity: 'minor' });

  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await page.getByTestId('sites').getByRole('link', { name: 'Tower A' }).click();

  await expect(page.getByTestId('site-name')).toHaveText('Tower A');
  await expect(page.getByTestId('tile-rfis')).toContainText('2 open');
  await expect(page.getByTestId('tile-rfis')).toContainText('1 overdue');
  await expect(page.getByTestId('tile-submittals')).toContainText('2 waiting for review');
  await expect(page.getByTestId('tile-submittals')).toContainText('1 overdue');
  await expect(page.getByTestId('tile-defects')).toContainText('2 open');
  await expect(page.getByTestId('tile-defects')).toContainText('1 critical');
  await expect(page.getByTestId('tile-drawings')).toContainText('2 on the register');
  await expect(page.getByTestId('tile-drawings')).toContainText('1 to approve');

  // RFIs (the first tab): numbered by the order raised, overdue flagged, closed hidden.
  await expect(page.getByTestId(`rfi-${r1}`)).toContainText('RFI-1');
  await expect(page.getByTestId(`rfi-${r1}`)).toContainText('Architect');
  await expect(page.getByTestId(`rfi-${r1}`)).toContainText('overdue');
  await expect(page.getByTestId(`rfi-${r2}`)).toContainText('RFI-2');
  await expect(page.getByTestId(`rfi-${r2}`)).not.toContainText('overdue');
  await expect(page.getByTestId(`rfi-${r3}`)).toHaveCount(0);
  await page.getByTestId('show-closed').check();
  await expect(page.getByTestId(`rfi-${r3}`)).toContainText('RFI-3');
  await expect(page.getByTestId(`rfi-${r3}`)).toContainText('Closed');

  await page.getByTestId('tab-submittals').click();
  await expect(page.getByTestId(`submittal-${s1}`)).toContainText('SUB-1');
  await expect(page.getByTestId(`submittal-${s1}`)).toContainText('Product data');
  await expect(page.getByTestId(`submittal-${s1}`)).toContainText('overdue');
  await expect(page.getByTestId(`submittal-${s2}`)).toContainText('Shop drawing');

  await page.getByTestId('tab-defects').click();
  await expect(page.locator('[data-testid=defects] tbody tr').first()).toContainText('Crack in column C4');
  await expect(page.getByTestId(`defect-${f1}`)).toContainText('Critical');
  await expect(page.getByTestId(`defect-${f1}`)).toContainText('overdue');
  await expect(page.getByTestId(`defect-${f2}`)).toContainText('Minor');

  await page.getByTestId('tab-drawings').click();
  await expect(page.getByTestId(`drawing-${d1}`)).toContainText('A-101');
  await expect(page.getByTestId(`drawing-${d1}`)).toContainText('None approved yet');
  await expect(page.getByTestId(`drawing-${d2}`)).toContainText('Structural');
  await expect(page.getByTestId(`drawing-${d2}`)).toContainText('Rev A');

  // The address keeps the tab, so a link can be shared.
  await page.reload();
  await expect(page.getByTestId(`drawing-${d1}`)).toBeVisible();

  // Another company's site, even with its address, shows nothing.
  await page.goto(`./#/site/${bSite}`);
  await expect(page.getByTestId('site-not-found')).toBeVisible();
  await expect(page.getByText('Secret Site')).toHaveCount(0);

  await page.getByTestId('all-sites').click();
  await expect(page.getByTestId('company-name')).toHaveText('Asha Builders');
});

test('an empty site says so on each register', async ({ page }) => {
  const a = await account('empty');
  const s = await site(a, await company(a, 'Empty Co'), 'Plot 7');
  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await page.getByTestId('sites').getByRole('link', { name: 'Plot 7' }).click();
  await expect(page.getByTestId('rfis-empty')).toBeVisible();
  for (const tab of ['submittals', 'defects', 'drawings']) {
    await page.getByTestId(`tab-${tab}`).click();
    await expect(page.getByTestId(`${tab}-empty`)).toBeVisible();
  }
  expect(page.url()).toContain(`#/site/${s}/drawings`);
});

test('a site with more than 1000 defects counts every one of them', async ({ page }) => {
  // The server hands out 1000 rows per request; a big handover logs more.
  const a = await account('many');
  const s = await site(a, await company(a, 'Handover Co'), 'Block 9');
  const rows = Array.from({ length: 1205 }, (_, i) => ({
    id: crypto.randomUUID(), project_id: s, raised_by: a.id, description: `Snag ${i + 1}`, severity: i === 1204 ? 'critical' : 'minor',
  }));
  for (let i = 0; i < rows.length; i += 500) {
    const { error } = await a.db.from('site_defects').insert(rows.slice(i, i + 500));
    if (error) throw error;
  }
  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await page.getByTestId('sites').getByRole('link', { name: 'Block 9' }).click();
  await expect(page.getByTestId('tile-defects')).toContainText('1205 open');
  await expect(page.getByTestId('tile-defects')).toContainText('1 critical');
});
