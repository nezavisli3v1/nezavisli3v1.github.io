-- Hlasování v anketách i bez přihlášení.
-- Nepřihlášený návštěvník hlasuje náhodným klíčem, který si pamatuje jeho prohlížeč:
-- jeden prohlížeč = jeden hlas v anketě, hlas jde změnit. Kdo smaže data prohlížeče
-- nebo použije jiný, může hlasovat znovu, proto databáze navíc omezuje počet nových
-- anonymních hlasů z jedné IP adresy. IP se neukládá, jen její otisk (hash).
-- Přihlášení hlasují dál svým účtem; když se přihlásí, jejich anonymní hlas
-- ze stejného prohlížeče se zruší, aby nehlasovali dvakrát.
-- Spustit v Supabase SQL Editoru jednou (po 001–008).

-- hlas patří buď účtu (user_id), nebo prohlížeči (voter_key)
alter table public.poll_votes drop constraint if exists poll_votes_pkey;
alter table public.poll_votes add column if not exists id bigint generated always as identity primary key;
alter table public.poll_votes alter column user_id drop not null;
alter table public.poll_votes add column if not exists voter_key uuid;
alter table public.poll_votes add column if not exists ip_hash text;
alter table public.poll_votes drop constraint if exists poll_votes_owner_chk;
alter table public.poll_votes add constraint poll_votes_owner_chk check ((user_id is null) <> (voter_key is null));
create unique index if not exists poll_votes_user_uq on public.poll_votes (poll_id, user_id) where user_id is not null;
create unique index if not exists poll_votes_key_uq  on public.poll_votes (poll_id, voter_key) where voter_key is not null;
create index if not exists poll_votes_ip_idx on public.poll_votes (poll_id, ip_hash, voted_at) where voter_key is not null;

-- výsledky počítají všechny hlasy (dříve count(user_id), což by anonymní vynechalo)
create or replace view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, o.position, count(v.option_id)::int as votes
  from public.poll_options o left join public.poll_votes v on v.option_id = o.id
  join public.polls pl on pl.id = o.poll_id
  join public.posts p on p.id = pl.post_id and public.post_is_live(p.status, p.published_at)
  group by o.poll_id, o.id, o.label, o.position;

-- hlasování: přihlášený účtem, nepřihlášený klíčem prohlížeče
create or replace function public.vote_any(p_option bigint, p_key uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.poll_options; p public.posts; ip text; recent int;
begin
  select * into o from public.poll_options where id = p_option;
  if o.id is null then raise exception 'Možnost neexistuje.'; end if;
  select ps.* into p from public.posts ps join public.polls pl on pl.post_id = ps.id where pl.id = o.poll_id;
  if p.id is null or not public.post_is_live(p.status, p.published_at) then raise exception 'Anketa není zveřejněná.'; end if;
  if p.closed_at is not null then raise exception 'Anketa je uzavřená.'; end if;

  if auth.uid() is not null then
    insert into public.poll_votes (poll_id, user_id, option_id) values (o.poll_id, auth.uid(), o.id)
    on conflict (poll_id, user_id) where user_id is not null
    do update set option_id = excluded.option_id, voted_at = now();
    if p_key is not null then
      delete from public.poll_votes where poll_id = o.poll_id and voter_key = p_key;
    end if;
    return;
  end if;

  if p_key is null then raise exception 'Hlas se nepodařilo uložit. Obnovte stránku.'; end if;
  -- změna už odevzdaného hlasu do limitu nepočítá
  if exists (select 1 from public.poll_votes where poll_id = o.poll_id and voter_key = p_key) then
    update public.poll_votes set option_id = o.id, voted_at = now() where poll_id = o.poll_id and voter_key = p_key;
    return;
  end if;
  ip := split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1);
  ip := md5('nezavisli3v1:' || coalesce(nullif(trim(ip), ''), 'neznama'));
  select count(*) into recent from public.poll_votes
    where poll_id = o.poll_id and ip_hash = ip and voter_key is not null and voted_at > now() - interval '1 hour';
  if recent >= 20 then raise exception 'Z vaší sítě přišlo do této ankety příliš mnoho hlasů. Zkuste to později, nebo se přihlaste.'; end if;
  insert into public.poll_votes (poll_id, voter_key, option_id, ip_hash) values (o.poll_id, p_key, o.id, ip)
  on conflict (poll_id, voter_key) where voter_key is not null
  do update set option_id = excluded.option_id, voted_at = now();
end $$;

-- můj hlas v anketě (přihlášený podle účtu, nepřihlášený podle klíče)
create or replace function public.my_vote(p_poll bigint, p_key uuid default null) returns bigint
language sql stable security definer set search_path = public as $$
  select option_id from public.poll_votes
  where poll_id = p_poll
    and ((auth.uid() is not null and user_id = auth.uid())
      or (auth.uid() is null and p_key is not null and voter_key = p_key))
  limit 1
$$;

revoke all on function public.vote_any(bigint, uuid) from public;
revoke all on function public.my_vote(bigint, uuid) from public;
grant execute on function public.vote_any(bigint, uuid) to anon, authenticated;
grant execute on function public.my_vote(bigint, uuid) to anon, authenticated;
grant select on public.poll_results to anon, authenticated;
