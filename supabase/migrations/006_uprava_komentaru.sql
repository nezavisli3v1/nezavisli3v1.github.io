-- Úprava komentářů: autor může upravit text svého komentáře, dokud je diskuse otevřená.
-- U upraveného komentáře se zobrazuje „upraveno“. Skrytý komentář upravit nejde.
-- Spustit v Supabase SQL Editoru jednou (po 001–005).

alter table public.comments add column if not exists edited_at timestamptz;

drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments for update
  using (author_id = auth.uid()) with check (author_id = auth.uid());

create or replace function public.comments_guard_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.posts;
begin
  -- tyhle údaje se po vložení nemění nikdy
  new.post_id := old.post_id; new.parent_id := old.parent_id;
  new.author_id := old.author_id; new.created_at := old.created_at;

  if new.body is distinct from old.body then
    if old.author_id is distinct from auth.uid() then raise exception 'Upravit lze jen vlastní komentář.'; end if;
    if old.hidden_reason is not null then raise exception 'Skrytý komentář nejde upravit.'; end if;
    select * into p from public.posts where id = old.post_id;
    if not public.post_is_live(p.status, p.published_at) or p.closed_at is not null or not p.comments_enabled then
      raise exception 'Diskuse je uzavřená, komentář už nejde upravit.'; end if;
    new.edited_at := now();
  else
    new.edited_at := old.edited_at;
  end if;

  -- skrývat a obnovovat smí jen autoři webu (přes hide_comment / unhide_comment)
  if (new.hidden_reason, new.hidden_by, new.hidden_at) is distinct from (old.hidden_reason, old.hidden_by, old.hidden_at)
     and not public.is_author() then
    raise exception 'K této akci nemáte oprávnění.';
  end if;
  return new;
end $$;

drop trigger if exists comments_guard_update on public.comments;
create trigger comments_guard_update before update on public.comments
  for each row execute function public.comments_guard_update();

create or replace view public.comment_feed as
  select c.id, c.post_id, c.parent_id, c.created_at, c.hidden_reason,
         case when c.hidden_reason is null or public.is_author() then c.body end as body,
         c.author_id, pr.display_name as author_name,
         pr.role in ('author','admin') as author_is_team, pr.badge as author_badge,
         c.edited_at
  from public.comments c
  join public.posts p on p.id = c.post_id and (public.post_is_live(p.status, p.published_at) or public.is_author())
  join public.profiles pr on pr.id = c.author_id;

grant select on public.comment_feed to anon, authenticated;
grant update on public.comments to authenticated;
