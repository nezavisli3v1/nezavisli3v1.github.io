-- Odložené publikování: příspěvek se stavem 'published' a published_at v budoucnosti
-- je do té chvíle vidět jen autorům. Nic se nespouští automaticky, rozhoduje čas při čtení.
-- Spustit v Supabase SQL Editoru jednou (po 001–003).

create or replace function public.post_is_live(p_status text, p_published_at timestamptz) returns boolean
language sql stable as $$ select p_status = 'published' and p_published_at is not null and p_published_at <= now() $$;

-- čtení příspěvků
drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select
  using (public.post_is_live(status, published_at) or public.is_author());

-- ankety a přílohy naplánovaného příspěvku zatím jen pro autory
drop policy if exists polls_read on public.polls;
create policy polls_read on public.polls for select
  using (exists (select 1 from public.posts p where p.id = post_id and (public.post_is_live(p.status, p.published_at) or public.is_author())));
drop policy if exists att_read on public.attachments;
create policy att_read on public.attachments for select
  using (exists (select 1 from public.posts p where p.id = post_id and (public.post_is_live(p.status, p.published_at) or public.is_author())));

create or replace view public.comment_feed as
  select c.id, c.post_id, c.parent_id, c.created_at, c.hidden_reason,
         case when c.hidden_reason is null or public.is_author() then c.body end as body,
         c.author_id, pr.display_name as author_name,
         pr.role in ('author','admin') as author_is_team, pr.badge as author_badge
  from public.comments c
  join public.posts p on p.id = c.post_id and (public.post_is_live(p.status, p.published_at) or public.is_author())
  join public.profiles pr on pr.id = c.author_id;

create or replace view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, o.position, count(v.user_id)::int as votes
  from public.poll_options o left join public.poll_votes v on v.option_id = o.id
  join public.polls pl on pl.id = o.poll_id
  join public.posts p on p.id = pl.post_id and public.post_is_live(p.status, p.published_at)
  group by o.poll_id, o.id, o.label, o.position;

-- komentovat a hlasovat jde až po vydání
create or replace function public.comments_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.posts; parent public.comments; recent int;
begin
  select * into p from public.posts where id = new.post_id;
  if p.id is null or not public.post_is_live(p.status, p.published_at) then raise exception 'Příspěvek neexistuje.'; end if;
  if not p.comments_enabled then raise exception 'U tohoto příspěvku jsou komentáře vypnuté.'; end if;
  if p.closed_at is not null then raise exception 'Diskuse je uzavřená.'; end if;
  if (select display_name from public.profiles where id = new.author_id) = '' then
    raise exception 'Než začnete komentovat, vyplňte své jméno.'; end if;
  if new.parent_id is not null then
    select * into parent from public.comments where id = new.parent_id;
    if parent.id is null or parent.post_id <> new.post_id then raise exception 'Odpověď nepatří k tomuto příspěvku.'; end if;
    if parent.parent_id is not null then new.parent_id := parent.parent_id; end if;
  end if;
  select count(*) into recent from public.comments
    where author_id = new.author_id and created_at > now() - interval '10 minutes';
  if recent >= 10 then raise exception 'Příliš mnoho komentářů za krátkou dobu. Zkuste to za pár minut.'; end if;
  new.hidden_reason := null; new.hidden_by := null; new.hidden_at := null; new.created_at := now();
  return new;
end $$;

create or replace function public.vote(p_option bigint) returns void
language plpgsql security definer set search_path = public as $$
declare o public.poll_options; p public.posts;
begin
  if auth.uid() is null then raise exception 'Pro hlasování se přihlaste.'; end if;
  select * into o from public.poll_options where id = p_option;
  if o.id is null then raise exception 'Možnost neexistuje.'; end if;
  select ps.* into p from public.posts ps join public.polls pl on pl.post_id = ps.id where pl.id = o.poll_id;
  if not public.post_is_live(p.status, p.published_at) then raise exception 'Anketa není zveřejněná.'; end if;
  if p.closed_at is not null then raise exception 'Anketa je uzavřená.'; end if;
  insert into public.poll_votes (poll_id, user_id, option_id) values (o.poll_id, auth.uid(), o.id)
  on conflict (poll_id, user_id) do update set option_id = excluded.option_id, voted_at = now();
end $$;

-- koncept nemá datum vydání; zveřejnění bez data = teď
create or replace function public.posts_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'draft' then new.published_at := null; end if;
  if new.status = 'published' and new.published_at is null then new.published_at := now(); end if;
  if tg_op = 'UPDATE' then new.author_id := old.author_id; new.created_at := old.created_at; end if;
  return new;
end $$;

grant select on public.comment_feed, public.poll_results to anon, authenticated;
