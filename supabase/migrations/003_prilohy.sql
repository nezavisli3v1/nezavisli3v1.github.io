-- PDF přílohy k článkům a otázkám. Přidávají jen autoři.
-- Spustit v Supabase SQL Editoru po 001 a 002.

create table public.attachments (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.posts(id) on delete cascade,
  path        text not null unique,
  name        text not null check (char_length(name) between 1 and 160),
  size_bytes  int not null check (size_bytes between 1 and 10485760),
  position    int not null default 0,
  created_at  timestamptz not null default now()
);
create index attachments_post_idx on public.attachments (post_id, position);
alter table public.attachments enable row level security;

create policy att_read on public.attachments for select
  using (exists (select 1 from public.posts p where p.id = post_id and (p.status = 'published' or public.is_author())));
create policy att_write on public.attachments for all
  using (public.is_author()) with check (public.is_author());

-- úložiště: jen PDF, nejvýš 10 MB
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', true, 10485760, array['application/pdf'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy att_files_read   on storage.objects for select using (bucket_id = 'attachments');
create policy att_files_upload on storage.objects for insert with check (bucket_id = 'attachments' and public.is_author());
create policy att_files_delete on storage.objects for delete using (bucket_id = 'attachments' and public.is_author());
