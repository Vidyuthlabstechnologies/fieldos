import { expect, test } from '@playwright/test';
import { account, cloudReady, company, row, site } from './cloud';

test.skip(!cloudReady, 'needs the local FieldOS cloud (see playwright.config.ts)');

const iso = (offset: number) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

test('the schedule draws the site’s tasks, pushes late work and marks the critical path', async ({ page }) => {
  const a = await account('gantt');
  const co = await company(a, 'Asha Builders');
  const s = await site(a, co, 'Tower A');
  const other = await account('gantt-other');
  const theirs = await site(other, await company(other, 'Bharat Infra'), 'Secret');

  // Footings were due yesterday and are still open: today at the earliest,
  // so the slab linked after them moves a day; plastering runs alongside.
  const foot = await row(a, 'tasks', { project_id: s, title: 'Footings', start_date: iso(-5), due_date: iso(-1), status: 'in_progress' });
  const slab = await row(a, 'tasks', { project_id: s, title: 'Ground slab', start_date: iso(0), due_date: iso(4) });
  const plaster = await row(a, 'tasks', { project_id: s, title: 'Plastering', start_date: iso(0), due_date: iso(2) });
  const done = await row(a, 'tasks', { project_id: s, title: 'Site clearing', start_date: iso(-10), due_date: iso(-8), status: 'done', progress: 100 });
  await row(a, 'tasks', { project_id: s, title: 'Order lift', status: 'todo' });
  await row(a, 'site_task_constraints', { project_id: s, task_id: slab, kind: 'predecessor', description: 'Footings', link_id: foot, raised_by: a.id });

  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await page.getByTestId('sites').getByRole('link', { name: 'Tower A' }).click();
  await page.getByTestId('tab-schedule').click();

  await expect(page.getByTestId('gantt')).toBeVisible();
  await expect(page.getByTestId(`bar-${foot}`)).toHaveAttribute('data-finish', iso(0));
  await expect(page.getByTestId(`bar-${slab}`)).toHaveAttribute('data-start', iso(1));
  await expect(page.getByTestId(`bar-${slab}`)).toHaveAttribute('data-finish', iso(5));
  await expect(page.getByTestId(`bar-${slab}`)).toHaveAttribute('data-kind', 'critical');
  await expect(page.getByTestId(`bar-${foot}`)).toHaveAttribute('data-kind', 'critical');
  await expect(page.getByTestId(`bar-${plaster}`)).toHaveAttribute('data-kind', 'heading');
  await expect(page.getByTestId(`bar-${done}`)).toHaveAttribute('data-kind', 'done');
  await expect(page.getByTestId(`link-${foot}-${slab}`)).toBeAttached();
  await expect(page.getByTestId('today-line')).toBeAttached();
  await expect(page.getByTestId('days-late')).toContainText('1');
  await expect(page.getByTestId('critical-count')).toContainText('2');
  await expect(page.getByTestId(`task-${slab}`)).toContainText('Footings');
  await expect(page.getByTestId(`task-${plaster}`)).toContainText('3');
  await expect(page.getByTestId('undated')).toContainText('Order lift');

  await page.getByTestId('gantt-zoom').selectOption('month');
  await expect(page.getByTestId(`bar-${slab}`)).toBeAttached();

  // Another company's schedule stays out of reach, in the page and asked directly.
  const { data } = await a.db.from('tasks').select('id').eq('project_id', theirs);
  expect(data).toEqual([]);
  await page.goto(`./#/site/${theirs}/schedule`);
  await expect(page.getByTestId('site-not-found')).toBeVisible();
});

test('a site with no tasks says so', async ({ page }) => {
  const a = await account('gantt-empty');
  await site(a, await company(a, 'Empty Co'), 'Plot 9');
  await page.goto('./');
  await page.getByTestId('email').fill(a.email);
  await page.getByTestId('password').fill(a.password);
  await page.getByTestId('sign-in').click();
  await page.getByTestId('sites').getByRole('link', { name: 'Plot 9' }).click();
  await page.getByTestId('tab-schedule').click();
  await expect(page.getByTestId('schedule-empty')).toBeVisible();
});
