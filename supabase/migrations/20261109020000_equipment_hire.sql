-- Machines by the hour and the hire register (app schema v12). Onsite's
-- reviews ask for JCB and other machines charged per hour, and for a
-- record of machines taken on rent: from whom, since when, when they go
-- back. Every column is nullable or has a default, so older app versions
-- keep inserting as before.

alter table equipment
  add column if not exists hourly_rate numeric(10, 2) check (hourly_rate >= 0),
  add column if not exists ownership text not null default 'own' check (ownership in ('own', 'hired')),
  add column if not exists hired_from text check (char_length(hired_from) <= 120),
  add column if not exists hired_on date,
  add column if not exists return_due_on date,
  add column if not exists returned_on date;

alter table equipment drop constraint if exists equipment_hire_dates_in_order;
alter table equipment add constraint equipment_hire_dates_in_order
  check ((return_due_on is null or hired_on is null or return_due_on >= hired_on)
     and (returned_on is null or hired_on is null or returned_on >= hired_on));
