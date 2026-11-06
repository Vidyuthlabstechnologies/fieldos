-- Task planning: how far along a task is (moved forward from the daily
-- report), its priority, and when work is planned to start. With the due
-- date these give the phone's delay view and look-ahead list.

alter table tasks
  add column if not exists progress integer not null default 0 check (progress between 0 and 100),
  add column if not exists priority text not null default 'normal' check (priority in ('high', 'normal', 'low')),
  add column if not exists start_date date;
