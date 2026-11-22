import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { account, cloudReady, company, row, site, type Account } from './cloud';
import { sheets, unzip } from './xlsxread';

test.skip(!cloudReady, 'needs the local FieldOS cloud (see playwright.config.ts)');

const today = () => new Date().toISOString().slice(0, 10);

async function signIn(page: Page, a: Account) {
  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
}

// An owner's site with money both ways, and a site engineer who joined by code.
async function setUp() {
  const owner = await account('money');
  const co = await company(owner, 'Asha Builders');
  const s = await site(owner, co, 'Tower A', 'active', 'Sunrise Homes');
  const s2 = await site(owner, co, 'Villa B');
  const at = (d: string) => `${d}T06:00:00Z`;

  await row(owner, 'site_expenses', { project_id: s, category: 'Material', amount: 11800, incurred_on: today(), recorded_by: owner.id, paid_to: 'Sri Cement', mode: 'bank', gst_pct: 18 });
  await row(owner, 'site_expenses', { project_id: s, category: 'Labour', amount: 4500, incurred_on: today(), recorded_by: owner.id, paid_to: 'Ramesh', mode: 'cash' });
  const wrong = await row(owner, 'site_expenses', { project_id: s, category: 'Fuel', amount: 999, incurred_on: today(), recorded_by: owner.id });
  const v = await owner.db.from('site_expenses').update({ voided: true, void_reason: 'Typed twice' }).eq('id', wrong);
  if (v.error) throw v.error;
  await row(owner, 'site_expenses', { project_id: s2, category: 'Transport', amount: 700, incurred_on: today(), recorded_by: owner.id });

  const pay = await row(owner, 'site_payments_received', { project_id: s, amount: 50000, received_on: at(today()), from_party: 'Sunrise Homes', mode: 'upi', recorded_by: owner.id });
  const bill = await row(owner, 'site_client_bills', {
    project_id: s, kind: 'ra', bill_number: 'RA-1', bill_date: today(), client_name: 'Sunrise Homes', lines: '[]', gross: 80000, net_payable: 72000, recorded_by: owner.id,
  });
  await row(owner, 'site_bill_allocations', { project_id: s, payment_id: pay, bill_id: bill, amount: 40000, created_by: owner.id });

  const vendor = await row(owner, 'vendors', { company_id: co, name: 'Sri Cement' });
  await row(owner, 'site_supplier_invoices', { project_id: s, supplier_id: vendor, invoice_number: 'SC-77', invoice_date: today(), amount: 11800, gst_amount: 1800, recorded_by: owner.id });

  const eng = await account('eng');
  const code = await owner.db.from('companies').select('join_code').eq('id', co).single();
  if (code.error) throw code.error;
  const joined = await eng.db.rpc('join_company', { p_code: code.data.join_code });
  if (joined.error || joined.data?.error) throw new Error(`join: ${joined.error?.message ?? joined.data.error}`);
  return { owner, eng, co, s, s2 };
}

test('an owner sees the site’s whole money and downloads it as Excel', async ({ page }) => {
  const { owner, s } = await setUp();
  await signIn(page, owner);

  // All sites at a glance, with the company's cash position.
  const all = page.getByTestId('company-money');
  await expect(all.getByTestId(`money-site-${s}`)).toContainText('₹50,000.00');
  await expect(all.getByTestId(`money-site-${s}`)).toContainText('₹16,300.00');
  await expect(all.getByTestId(`money-site-${s}`)).toContainText('₹33,700.00');
  await expect(all.getByTestId(`money-site-${s}`)).toContainText('₹32,000.00');
  await expect(all.getByTestId('money-all-sites')).toContainText('₹17,000.00');

  await page.getByTestId('sites').getByRole('link', { name: 'Tower A' }).click();
  await page.getByTestId('tab-money').click();
  await expect(page.getByTestId('fig-received')).toContainText('₹50,000.00');
  await expect(page.getByTestId('fig-spent')).toContainText('₹16,300.00');
  await expect(page.getByTestId('fig-balance')).toContainText('₹33,700.00');
  await expect(page.getByTestId('fig-due')).toContainText('₹32,000.00');
  await expect(page.getByTestId('spent-total')).toHaveText('₹16,300.00');
  await expect(page.getByTestId('spent')).toContainText('Cancelled');
  await expect(page.getByTestId('by-category')).toContainText('Material');

  await page.getByTestId('money-search').fill('ramesh');
  await expect(page.getByTestId('spent-total')).toHaveText('₹4,500.00');
  await page.getByTestId('money-search').fill('');
  await page.getByTestId('money-show-cancelled').uncheck();
  await expect(page.getByTestId('spent')).not.toContainText('Cancelled');
  await page.getByTestId('money-show-cancelled').check();

  await page.getByTestId('money-received').click();
  await expect(page.getByTestId('received')).toContainText('Sunrise Homes');
  await expect(page.getByTestId('received')).toContainText('UPI');
  await page.getByTestId('money-bills').click();
  await expect(page.getByTestId('bills')).toContainText('RA-1');
  await expect(page.getByTestId('bills')).toContainText('₹32,000.00');
  await page.getByTestId('money-invoices').click();
  await expect(page.getByTestId('invoices')).toContainText('SC-77');

  const [dl] = await Promise.all([page.waitForEvent('download'), page.getByTestId('money-export').click()]);
  expect(dl.suggestedFilename()).toMatch(/^Tower A Money \d{4}-\d{2}-\d{2}\.xlsx$/);
  const book = sheets(unzip(readFileSync((await dl.path())!)));
  expect([...book.keys()]).toEqual(['Money', 'Spent', 'Received', 'Client bills', 'Supplier invoices']);
  expect(book.get('Money')![1]).toEqual(['Tower A', 16300, 11800, 50000, 33700, 72000, 32000]);
  expect(book.get('Spent')!).toHaveLength(4);
  expect(book.get('Client bills')![1]).toContain(40000);
});

test('a site engineer sees what was spent, never money received or client bills', async ({ page }) => {
  const { eng, s } = await setUp();
  await signIn(page, eng);
  await expect(page.getByTestId('company-name')).toHaveText('Asha Builders');
  await expect(page.getByTestId('company-money')).toHaveCount(0);

  await page.getByTestId('sites').getByRole('link', { name: 'Tower A' }).click();
  await page.getByTestId('tab-money').click();
  await expect(page.getByTestId('fig-spent')).toContainText('₹16,300.00');
  await expect(page.getByTestId('money-in-hidden')).toBeVisible();
  for (const id of ['fig-received', 'fig-balance', 'fig-due', 'money-received', 'money-bills']) {
    await expect(page.getByTestId(id)).toHaveCount(0);
  }

  const [dl] = await Promise.all([page.waitForEvent('download'), page.getByTestId('money-export').click()]);
  const book = sheets(unzip(readFileSync((await dl.path())!)));
  expect([...book.keys()]).toEqual(['Money', 'Spent', 'Supplier invoices']);

  // Asked directly, the server gives them nothing either.
  for (const table of ['site_payments_received', 'site_client_bills', 'site_bill_allocations']) {
    const { data } = await eng.db.from(table).select('id').eq('project_id', s);
    expect(data, table).toEqual([]);
  }
});

test('another company sees none of it', async ({ page }) => {
  const { s } = await setUp();
  const stranger = await account('stranger');
  await company(stranger, 'Bharat Infra');
  for (const table of ['site_expenses', 'site_payments_received', 'site_client_bills', 'site_supplier_invoices']) {
    const { data } = await stranger.db.from(table).select('id').eq('project_id', s);
    expect(data, table).toEqual([]);
  }
  await signIn(page, stranger);
  await expect(page.getByTestId('company-name')).toHaveText('Bharat Infra');
  await page.goto(`./#/site/${s}/money`);
  await expect(page.getByTestId('site-not-found')).toBeVisible();
});
