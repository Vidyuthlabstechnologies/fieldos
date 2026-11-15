import { expect, test } from '@playwright/test';
import { account, cloudReady, company, site } from './cloud';

test.skip(!cloudReady, 'needs the local FieldOS cloud (see playwright.config.ts)');

test('an owner signs in and sees their own sites, never another company’s', async ({ page }) => {
  const a = await account('a');
  const b = await account('b');
  const aCo = await company(a, 'Asha Builders');
  const bCo = await company(b, 'Bharat Infra');
  const aRunning = await site(a, aCo, 'Tower A', 'active', 'Sunrise Homes');
  const aPlanned = await site(a, aCo, 'Annexe', 'planning');
  const bSite = await site(b, bCo, 'Secret Site', 'active');

  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill('wrong password');
  await page.getByTestId('sign-in').click();
  await expect(page.getByRole('alert')).toHaveText('Email or password is wrong.');

  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await expect(page.getByTestId('company-name')).toHaveText('Asha Builders');
  await expect(page.getByTestId(`site-${aRunning}`)).toContainText('Tower A');
  await expect(page.getByTestId(`site-${aRunning}`)).toContainText('Sunrise Homes');
  await expect(page.getByTestId(`site-${aRunning}`)).toContainText('Running');
  await expect(page.getByTestId(`site-${aPlanned}`)).toContainText('Planning');
  // Running sites come first.
  await expect(page.locator('tbody tr').first()).toContainText('Tower A');
  await expect(page.getByTestId(`site-${bSite}`)).toHaveCount(0);
  await expect(page.getByText('Secret Site')).toHaveCount(0);
  await expect(page.getByTestId('company-picker')).toHaveCount(0);

  // Search narrows the list.
  await page.getByTestId('site-search').fill('annex');
  await expect(page.locator('tbody tr')).toHaveCount(1);
  await page.getByTestId('site-search').fill('');

  // Still signed in after a reload; then signs out.
  await page.reload();
  await expect(page.getByTestId('company-name')).toHaveText('Asha Builders');
  await page.getByTestId('sign-out').click();
  await expect(page.getByTestId('sign-in')).toBeVisible();

  // Even asked directly, the server gives A nothing of B's.
  const { data } = await a.db.from('projects').select('id').eq('company_id', bCo);
  expect(data).toEqual([]);
});

test('someone in two companies picks one, and the choice is remembered', async ({ page }) => {
  const a = await account('two');
  const first = await company(a, 'Alpha Constructions');
  const second = await company(a, 'Zeta Projects');
  await site(a, first, 'Alpha Site');
  await site(a, second, 'Zeta Site');

  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await expect(page.getByTestId('company-name')).toHaveText('Alpha Constructions');
  await expect(page.getByText('Alpha Site')).toBeVisible();

  await page.getByTestId('company-picker').selectOption(second);
  await expect(page.getByTestId('company-name')).toHaveText('Zeta Projects');
  await expect(page.getByText('Zeta Site')).toBeVisible();
  await expect(page.getByText('Alpha Site')).toHaveCount(0);

  await page.reload();
  await expect(page.getByTestId('company-name')).toHaveText('Zeta Projects');
});

test('an account with no company is told what to do', async ({ page }) => {
  const a = await account('none');
  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await expect(page.getByTestId('no-company')).toContainText('create or join one');
});
