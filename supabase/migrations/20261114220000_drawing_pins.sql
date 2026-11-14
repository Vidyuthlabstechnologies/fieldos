-- Pins and markup on drawings (global gap 3): a spot on a drawing revision
-- with a note, a link to the defect, RFI or task raised there, or a
-- freehand markup. Same columns as the phone's drawing_pins table, in
-- snake_case, so the site-execution sync mapper covers it.
--
-- x and y are fractions of the page (0..1), so a pin stays put at any zoom
-- and screen size. A pin is never deleted, only removed (removed_at), so the
-- record of what was marked where stays.

create table if not exists site_drawing_pins (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  drawing_id uuid not null references site_drawings(id) on delete cascade,
  revision_id uuid not null references site_drawing_revisions(id) on delete cascade,
  page int not null default 0 check (page between 0 and 999),
  x double precision not null check (x between 0 and 1),
  y double precision not null check (y between 0 and 1),
  kind text not null check (kind in ('note', 'defect', 'rfi', 'task', 'markup')),
  link_id uuid,
  label text not null check (char_length(label) between 1 and 300),
  -- markup only: [[x,y,x,y,...], ...] page fractions, one list per stroke.
  strokes text check (char_length(strokes) <= 40000),
  color text not null default 'red' check (color in ('red', 'blue', 'green', 'black')),
  created_by uuid not null,
  removed_at timestamptz,
  removed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_drawing_pins_project_idx on site_drawing_pins (project_id);
create index if not exists site_drawing_pins_drawing_idx on site_drawing_pins (drawing_id);

-- Added as yourself, on a revision of that drawing on the same site. Only
-- removal changes a pin afterwards: by whoever placed it, or the owner or a
-- project manager.
create or replace function site_drawing_pins_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.created_by is distinct from me then
      raise exception 'Pins are added as yourself.' using errcode = '42501';
    end if;
    if new.removed_at is not null then
      raise exception 'A new pin cannot be removed already.' using errcode = '42501';
    end if;
    if not exists (select 1 from site_drawing_revisions r join site_drawings d on d.id = r.drawing_id
                   where r.id = new.revision_id and d.id = new.drawing_id and d.project_id = new.project_id) then
      raise exception 'The pin belongs to another site''s drawing.' using errcode = '42501';
    end if;
    return new;
  end if;
  if (new.project_id, new.drawing_id, new.revision_id, new.page, new.x, new.y, new.kind, new.link_id, new.label,
      new.strokes, new.color, new.created_by)
     is distinct from
     (old.project_id, old.drawing_id, old.revision_id, old.page, old.x, old.y, old.kind, old.link_id, old.label,
      old.strokes, old.color, old.created_by) then
    raise exception 'A pin cannot be changed, only removed.' using errcode = '42501';
  end if;
  if old.removed_at is not null
     and (new.removed_at is distinct from old.removed_at or new.removed_by is distinct from old.removed_by) then
    raise exception 'A removed pin stays removed as it was.' using errcode = '42501';
  end if;
  if new.removed_at is not null and old.removed_at is null then
    if new.removed_by is distinct from me then
      raise exception 'Pins are removed as yourself.' using errcode = '42501';
    end if;
    if me is distinct from old.created_by and not coalesce(is_project_owner_or_pm(new.project_id), false) then
      raise exception 'Only whoever placed the pin, the owner or a project manager removes it.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function site_drawing_pins_guard() from public, anon, authenticated;

drop trigger if exists site_drawing_pins_stamp on site_drawing_pins;
create trigger site_drawing_pins_stamp before insert or update on site_drawing_pins
  for each row execute function site_execution_stamp();
drop trigger if exists site_drawing_pins_guard on site_drawing_pins;
create trigger site_drawing_pins_guard before insert or update on site_drawing_pins
  for each row execute function site_drawing_pins_guard();
drop trigger if exists site_drawing_pins_log_sync_change on site_drawing_pins;
create trigger site_drawing_pins_log_sync_change after insert or update or delete on site_drawing_pins
  for each row execute function log_sync_change();

alter table site_drawing_pins enable row level security;
revoke all on table site_drawing_pins from anon, authenticated;
grant select, insert, update on table site_drawing_pins to authenticated;

drop policy if exists "site reads drawing pins" on site_drawing_pins;
create policy "site reads drawing pins" on site_drawing_pins for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site adds drawing pins" on site_drawing_pins;
create policy "site adds drawing pins" on site_drawing_pins for insert
  to authenticated with check ((select has_project_access(project_id)));
drop policy if exists "site updates drawing pins" on site_drawing_pins;
create policy "site updates drawing pins" on site_drawing_pins for update
  to authenticated using ((select has_project_access(project_id)))
  with check ((select has_project_access(project_id)));
