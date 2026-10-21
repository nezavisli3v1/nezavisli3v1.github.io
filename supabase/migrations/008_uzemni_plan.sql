-- Stránka Územní plán: oddíly s textem, obrázky (výkresy) a PDF přílohami.
-- Číst může každý, upravovat autoři. Tabulky jsou obecné (sloupec page), aby šly
-- později použít i pro další stálé stránky.
-- Spustit v Supabase SQL Editoru jednou (po 001–007).

create table if not exists public.page_sections (
  id          bigint generated always as identity primary key,
  page        text not null default 'uzemni-plan' check (page in ('uzemni-plan')),
  position    int not null default 0,
  title       text not null check (char_length(title) between 1 and 160),
  body_html   text not null default '',
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null
);
create index if not exists page_sections_page_idx on public.page_sections (page, position);

create table if not exists public.section_files (
  id          bigint generated always as identity primary key,
  section_id  bigint not null references public.page_sections(id) on delete cascade,
  kind        text not null check (kind in ('image','pdf')),
  path        text not null unique,
  thumb_path  text,
  name        text not null check (char_length(name) between 1 and 160),
  size_bytes  int not null check (size_bytes between 1 and 26214400),
  width       int,
  height      int,
  position    int not null default 0
);
create index if not exists section_files_section_idx on public.section_files (section_id, position);

alter table public.page_sections enable row level security;
alter table public.section_files enable row level security;

drop policy if exists sections_read on public.page_sections;
create policy sections_read on public.page_sections for select using (true);
drop policy if exists sections_write on public.page_sections;
create policy sections_write on public.page_sections for all using (public.is_author()) with check (public.is_author());

drop policy if exists sfiles_read on public.section_files;
create policy sfiles_read on public.section_files for select using (true);
drop policy if exists sfiles_write on public.section_files;
create policy sfiles_write on public.section_files for all using (public.is_author()) with check (public.is_author());

create or replace function public.sections_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;
drop trigger if exists sections_touch on public.page_sections;
create trigger sections_touch before insert or update on public.page_sections
  for each row execute function public.sections_touch();

-- úložiště: obrázky a PDF do 25 MB (výkresy bývají velké)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pages', 'pages', true, 26214400, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists pages_files_read on storage.objects;
create policy pages_files_read on storage.objects for select using (bucket_id = 'pages');
drop policy if exists pages_files_upload on storage.objects;
create policy pages_files_upload on storage.objects for insert with check (bucket_id = 'pages' and public.is_author());
drop policy if exists pages_files_delete on storage.objects;
create policy pages_files_delete on storage.objects for delete using (bucket_id = 'pages' and public.is_author());

grant select on public.page_sections, public.section_files to anon, authenticated;
grant insert, update, delete on public.page_sections, public.section_files to authenticated;
