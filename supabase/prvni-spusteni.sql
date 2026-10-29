-- PRVNÍ SPUŠTĚNÍ: všechny migrace najednou (001–012).
-- Spustit jen jednou, na prázdném projektu. Supabase → SQL Editor → vložit celé → Run.


-- ════════ supabase/migrations/001_zaklad.sql ════════
-- Nezávislí PRO — základní schéma aplikace
-- Spustit jednou v Supabase: SQL Editor → vložit celý soubor → Run.
--
-- Principy:
--  * Číst smí kdokoli (i nepřihlášený) jen zveřejněný obsah.
--  * Komentovat a hlasovat smí jen přihlášený uživatel, a jen svým jménem.
--  * Psát články, moderovat a měnit stavy slibů smí jen autoři.
--  * Role přiděluje jen správce (admin).
--  * Moderace i změny stavů slibů jdou jen přes funkce, které zapisují důvod.

-- ─────────────────────────────────────────── uživatelé ──
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null default '' check (char_length(display_name) <= 60),
  role          text not null default 'reader' check (role in ('reader','author','admin')),
  badge         text check (badge is null or char_length(badge) <= 30),  -- např. „zastupitel“
  created_at    timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'display_name',''), ''));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'anon')
$$;
create or replace function public.is_author() returns boolean
language sql stable as $$ select public.my_role() in ('author','admin') $$;
create or replace function public.is_admin() returns boolean
language sql stable as $$ select public.my_role() = 'admin' $$;

-- vlastní profil vidí každý, celý seznam jen správce
create policy profiles_self_read  on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_admin_upd  on public.profiles for update using (public.is_admin()) with check (public.is_admin());

-- jméno si uživatel mění jen tímhle, roli tím nezmění
create or replace function public.set_my_name(p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  if char_length(trim(p_name)) < 2 then raise exception 'Jméno je příliš krátké.'; end if;
  update public.profiles set display_name = left(trim(p_name), 60) where id = auth.uid();
end $$;

-- smazání vlastního účtu (GDPR); smaže i komentáře a hlasy
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  if public.is_author() then raise exception 'Účet autora může smazat jen správce.'; end if;
  delete from auth.users where id = auth.uid();
end $$;

-- přehled účtů pro správce, včetně e-mailu (ten jinak nikdo nevidí)
create or replace function public.admin_people()
returns table (id uuid, email text, display_name text, role text, badge text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Jen pro správce.'; end if;
  return query select p.id, u.email::text, p.display_name, p.role, p.badge, p.created_at
    from public.profiles p join auth.users u on u.id = p.id order by p.created_at;
end $$;

-- veřejně vystavené údaje o lidech: jen jméno a štítek
create view public.people as
  select id, display_name, role in ('author','admin') as is_team, badge from public.profiles;

-- ─────────────────────────────────────────── příspěvky ──
create table public.posts (
  id               bigint generated always as identity primary key,
  kind             text not null default 'article' check (kind in ('article','question')),
  title            text not null check (char_length(title) between 3 and 120),
  perex            text not null default '' check (char_length(perex) <= 300),
  body_html        text not null default '',
  category         text not null default 'Zastupitelstvo',
  cover_path       text,
  author_id        uuid not null references public.profiles(id),
  status           text not null default 'draft' check (status in ('draft','published')),
  published_at     timestamptz,
  comments_enabled boolean not null default true,
  closed_at        timestamptz,
  closing_summary  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index posts_feed_idx on public.posts (status, published_at desc);
alter table public.posts enable row level security;

create policy posts_read   on public.posts for select using (status = 'published' or public.is_author());
create policy posts_insert on public.posts for insert with check (public.is_author() and author_id = auth.uid());
create policy posts_update on public.posts for update using (public.is_author()) with check (public.is_author());
create policy posts_delete on public.posts for delete using (public.is_admin());

create or replace function public.posts_touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'published' and new.published_at is null then new.published_at := now(); end if;
  -- autora po vytvoření nelze přepsat
  if tg_op = 'UPDATE' then new.author_id := old.author_id; new.created_at := old.created_at; end if;
  return new;
end $$;
create trigger posts_touch before insert or update on public.posts
  for each row execute function public.posts_touch();

-- uzavření diskuse se shrnutím
create or replace function public.close_discussion(p_post bigint, p_summary text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_author() then raise exception 'Jen autoři mohou uzavřít diskusi.'; end if;
  if char_length(trim(coalesce(p_summary,''))) < 10 then raise exception 'Napište shrnutí, co z diskuse vzešlo.'; end if;
  update public.posts set closed_at = now(), closing_summary = trim(p_summary) where id = p_post;
end $$;

-- ─────────────────────────────────────────── komentáře ──
create table public.comments (
  id            bigint generated always as identity primary key,
  post_id       bigint not null references public.posts(id) on delete cascade,
  parent_id     bigint references public.comments(id) on delete cascade,
  author_id     uuid not null references public.profiles(id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 3000),
  hidden_reason text,
  hidden_by     uuid references public.profiles(id),
  hidden_at     timestamptz,
  created_at    timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);
alter table public.comments enable row level security;

-- přímé čtení tabulky jen pro autory (vidí i text skrytých komentářů);
-- všichni ostatní čtou přes pohled comment_feed, který text skrytých komentářů vynechá
create policy comments_author_read on public.comments for select using (public.is_author());
create policy comments_insert on public.comments for insert with check (author_id = auth.uid());

create or replace function public.comments_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.posts; parent public.comments; recent int;
begin
  select * into p from public.posts where id = new.post_id;
  if p.id is null or p.status <> 'published' then raise exception 'Příspěvek neexistuje.'; end if;
  if not p.comments_enabled then raise exception 'U tohoto příspěvku jsou komentáře vypnuté.'; end if;
  if p.closed_at is not null then raise exception 'Diskuse je uzavřená.'; end if;
  if (select display_name from public.profiles where id = new.author_id) = '' then
    raise exception 'Než začnete komentovat, vyplňte své jméno.'; end if;
  if new.parent_id is not null then
    select * into parent from public.comments where id = new.parent_id;
    if parent.id is null or parent.post_id <> new.post_id then raise exception 'Odpověď nepatří k tomuto příspěvku.'; end if;
    if parent.parent_id is not null then new.parent_id := parent.parent_id; end if;  -- jen jedna úroveň vláken
  end if;
  select count(*) into recent from public.comments
    where author_id = new.author_id and created_at > now() - interval '10 minutes';
  if recent >= 10 then raise exception 'Příliš mnoho komentářů za krátkou dobu. Zkuste to za pár minut.'; end if;
  new.hidden_reason := null; new.hidden_by := null; new.hidden_at := null; new.created_at := now();
  return new;
end $$;
create trigger comments_check before insert on public.comments
  for each row execute function public.comments_check();

create or replace function public.hide_comment(p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_author() then raise exception 'Jen autoři mohou moderovat.'; end if;
  if p_reason not in ('urážka','osobní údaje','spam','mimo téma') then raise exception 'Neplatný důvod.'; end if;
  update public.comments set hidden_reason = p_reason, hidden_by = auth.uid(), hidden_at = now() where id = p_id;
end $$;

create or replace function public.unhide_comment(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_author() then raise exception 'Jen autoři mohou moderovat.'; end if;
  update public.comments set hidden_reason = null, hidden_by = null, hidden_at = null where id = p_id;
end $$;

create view public.comment_feed as
  select c.id, c.post_id, c.parent_id, c.created_at, c.hidden_reason,
         case when c.hidden_reason is null or public.is_author() then c.body end as body,
         c.author_id, pr.display_name as author_name,
         pr.role in ('author','admin') as author_is_team, pr.badge as author_badge
  from public.comments c
  join public.posts p on p.id = c.post_id and (p.status = 'published' or public.is_author())
  join public.profiles pr on pr.id = c.author_id;

-- ─────────────────────────────────────────── ankety ──
create table public.polls (
  id        bigint generated always as identity primary key,
  post_id   bigint not null unique references public.posts(id) on delete cascade,
  question  text not null check (char_length(question) between 3 and 200)
);
create table public.poll_options (
  id        bigint generated always as identity primary key,
  poll_id   bigint not null references public.polls(id) on delete cascade,
  label     text not null check (char_length(label) between 1 and 120),
  position  int not null default 0
);
create table public.poll_votes (
  poll_id    bigint not null references public.polls(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  option_id  bigint not null references public.poll_options(id) on delete cascade,
  voted_at   timestamptz not null default now(),
  primary key (poll_id, user_id)
);
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

create policy polls_read   on public.polls for select using (exists (select 1 from public.posts p where p.id = post_id and (p.status='published' or public.is_author())));
create policy polls_write  on public.polls for all using (public.is_author()) with check (public.is_author());
create policy popt_read    on public.poll_options for select using (true);
create policy popt_write   on public.poll_options for all using (public.is_author()) with check (public.is_author());
-- vlastní hlas vidí jen hlasující; výsledky jdou přes poll_results
create policy votes_own_read on public.poll_votes for select using (user_id = auth.uid());

create or replace function public.vote(p_option bigint) returns void
language plpgsql security definer set search_path = public as $$
declare o public.poll_options; p public.posts;
begin
  if auth.uid() is null then raise exception 'Pro hlasování se přihlaste.'; end if;
  select * into o from public.poll_options where id = p_option;
  if o.id is null then raise exception 'Možnost neexistuje.'; end if;
  select ps.* into p from public.posts ps join public.polls pl on pl.post_id = ps.id where pl.id = o.poll_id;
  if p.status <> 'published' then raise exception 'Anketa není zveřejněná.'; end if;
  if p.closed_at is not null then raise exception 'Anketa je uzavřená.'; end if;
  insert into public.poll_votes (poll_id, user_id, option_id) values (o.poll_id, auth.uid(), o.id)
  on conflict (poll_id, user_id) do update set option_id = excluded.option_id, voted_at = now();
end $$;

create view public.poll_results as
  select o.poll_id, o.id as option_id, o.label, o.position, count(v.user_id)::int as votes
  from public.poll_options o left join public.poll_votes v on v.option_id = o.id
  join public.polls pl on pl.id = o.poll_id
  join public.posts p on p.id = pl.post_id and p.status = 'published'
  group by o.poll_id, o.id, o.label, o.position;

-- ─────────────────────────────────────────── hlídač slibů ──
create table public.chapters (
  id        int generated always as identity primary key,
  position  int not null,
  title     text not null
);
create table public.promises (
  id          int generated always as identity primary key,
  chapter_id  int not null references public.chapters(id) on delete cascade,
  position    int not null,
  text        text not null,
  status      smallint not null default 0 check (status between 0 and 3), -- 0 nezahájeno, 1 rozpracováno, 2 splněno, 3 nepodařilo se
  updated_at  timestamptz not null default now()
);
create table public.promise_log (
  id          bigint generated always as identity primary key,
  promise_id  int not null references public.promises(id) on delete cascade,
  status      smallint not null,
  note        text not null check (char_length(note) between 5 and 1000),
  author_id   uuid not null references public.profiles(id),
  created_at  timestamptz not null default now()
);
alter table public.chapters enable row level security;
alter table public.promises enable row level security;
alter table public.promise_log enable row level security;
create policy chapters_read on public.chapters for select using (true);
create policy promises_read on public.promises for select using (true);
create policy plog_read     on public.promise_log for select using (true);
create policy chapters_adm  on public.chapters for all using (public.is_admin()) with check (public.is_admin());
create policy promises_adm  on public.promises for insert with check (public.is_admin());
create policy promises_del  on public.promises for delete using (public.is_admin());

create or replace function public.set_promise_status(p_promise int, p_status smallint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_author() then raise exception 'Jen autoři mohou měnit stav slibu.'; end if;
  if p_status <> 0 and char_length(trim(coalesce(p_note,''))) < 5 then raise exception 'Napište, co se stalo. Bez vysvětlení se stav nemění.'; end if;
  update public.promises set status = p_status, updated_at = now() where id = p_promise;
  if not found then raise exception 'Slib neexistuje.'; end if;
  insert into public.promise_log (promise_id, status, note, author_id)
  values (p_promise, p_status, coalesce(nullif(trim(coalesce(p_note,'')), ''), 'Stav vrácen na „nezahájeno“.'), auth.uid());
end $$;

-- ─────────────────────────────────────────── přístupová práva ──
grant select on public.people, public.comment_feed, public.poll_results to anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;
revoke execute on function public.delete_my_account() from anon;
grant execute on function public.set_my_name(text), public.vote(bigint), public.hide_comment(bigint,text),
  public.unhide_comment(bigint), public.close_discussion(bigint,text), public.set_promise_status(int,smallint,text)
  to authenticated;
revoke execute on function public.set_my_name(text), public.vote(bigint), public.hide_comment(bigint,text),
  public.unhide_comment(bigint), public.close_discussion(bigint,text), public.set_promise_status(int,smallint,text)
  from anon;

-- ─────────────────────────────────────────── fotky ──
insert into storage.buckets (id, name, public) values ('covers', 'covers', true)
  on conflict (id) do nothing;
create policy covers_read   on storage.objects for select using (bucket_id = 'covers');
create policy covers_upload on storage.objects for insert with check (bucket_id = 'covers' and public.is_author());
create policy covers_delete on storage.objects for delete using (bucket_id = 'covers' and public.is_author());


-- ════════ supabase/migrations/002_program.sql ════════
-- Body volebního programu pro Hlídač slibů.
-- Před spuštěním zkontrolujte, že sedí se zveřejněným programem.
-- Všechny body začínají ve stavu „nezahájeno“; stav se mění jen v aplikaci, s poznámkou.

with ch(pos, title, items) as (values
 (1, 'Bezpečná obec — doprava s rozumem', array[
   'Sčítání dopravy a měření hluku a prašnosti na průtazích',
   'Zklidnění podle dat: úpravy vjezdů, ostrůvky, nasvícené přechody, radary a kontroly policie',
   'Tranzit na tangentu a D3, ne přes náves',
   'Souvislé bezbariérové chodníky v každé osadě a bezpečné spojení mezi nimi',
   'Posílení MHD ve špičce i o víkendu a důstojné zastávky']),
 (2, 'Rozvoj s rozvahou', array[
   'Nejdřív dostavět, potom rozšiřovat zastavitelné plochy',
   'U každého většího záměru doložit dopady na dopravu, školu, vodu a kanalizaci',
   'Jasná a stejná pravidla: limity zastavěnosti, podíl zeleně, parkování na pozemku investora',
   'Kdo staví ve velkém, podílí se na infrastruktuře, kterou zatíží',
   'Změny územního plánu projednávat veřejně a s předstihem']),
 (3, 'Otevřená radnice', array[
   'Videozáznamy zasedání zastupitelstva na webu obce',
   'Veřejná projednání dřív, než je věc rozhodnutá',
   'Srozumitelný rozpočet a přehled zakázek: kolik, komu a proč',
   'Ankety u témat, která se dotýkají všech, s vždy zveřejněným výsledkem',
   'Dny otevřených dveří a setkání se zastupiteli v každé ze tří osad']),
 (4, 'Živá komunita a služby blízko domovu', array[
   'Předvídatelná podpora spolků a společný kalendář akcí ve všech třech osadách',
   'Bankomat v obci a rozšíření zdravotní péče',
   'Kapacita školy a školky drží krok s výstavbou',
   'Bezpečná pěší a cyklistická cesta mezi osadami',
   'Senioři: senior taxi, obědy včetně rozvozu, bezbariérové trasy, klub seniorů']),
 (5, 'Sport a volný čas', array[
   'Dostavba sportovního areálu v Mokrém s harmonogramem a zveřejněnými náklady',
   'Přednost obyvatel obce při využití sportovišť, stabilní podpora klubů a mládeže',
   'Hřiště, workout a běžecký okruh zdarma v každé osadě',
   'Cyklostezky jako doprava: propojení osad, Stromovky a Českých Budějovic',
   'Knihovna, kroužky a prostor pro mládež']),
 (6, 'Zelené Litvínovice', array[
   'Prověřit, jak zvýšit ochranu Litvínovických rybníků jako lokálního biocentra',
   'Voda v krajině: tůně, mokřady, revitalizace břehů, remízky a meze',
   'Méně plošného sekání, více stromů, alejí a kvetoucích ploch',
   'Úspory energie, fotovoltaika na obecních budovách a sdílení energie',
   'Veřejný prostor: stín, lavičky, pitná voda, koše a pořádek',
   'Srozumitelný systém odpadů a férová motivace k třídění']),
 (7, 'Silný soused', array[
   'Pravidelná jednání s Českými Budějovicemi, sousedními obcemi a krajem',
   'Zastoupení obce v kraji, ŘSD, svazcích obcí a místní akční skupině',
   'Společný postup v dopravě: navazující cyklostezky, MHD, koordinace uzavírek',
   'Včasné hlídání připravovaných záměrů v okolí'])
), ins as (
  insert into public.chapters (position, title) select pos, title from ch returning id, position
)
insert into public.promises (chapter_id, position, text)
select ins.id, i.ord, i.txt
from ins join ch on ch.pos = ins.position
cross join lateral unnest(ch.items) with ordinality as i(txt, ord);


-- ════════ supabase/migrations/003_prilohy.sql ════════
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


-- ════════ supabase/migrations/004_planovani.sql ════════
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


-- ════════ supabase/migrations/005_mazani_komentaru.sql ════════
-- Mazání komentářů: každý může smazat svůj komentář, správce jakýkoli.
-- Odpovědi na smazaný komentář se smažou s ním.
-- Spustit v Supabase SQL Editoru jednou (po 001–004).

-- mazat lze jen řádky, které člověk „vidí“; vlastní komentáře proto vidí každý
drop policy if exists comments_own_read on public.comments;
create policy comments_own_read on public.comments for select using (author_id = auth.uid());

drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments for delete
  using (author_id = auth.uid() or public.is_admin());

grant delete on public.comments to authenticated;


-- ════════ supabase/migrations/006_uprava_komentaru.sql ════════
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


-- ════════ supabase/migrations/007_pocitadlo.sql ════════
-- Počítadlo zobrazení: kolikrát byla stránka nebo příspěvek otevřen, po dnech.
-- Neukládá nic o návštěvníkovi (žádná IP, žádné cookies). Čísla vidí jen správce.
-- Spustit v Supabase SQL Editoru jednou (po 001–006).

create table if not exists public.page_views (
  day      date   not null default (now() at time zone 'Europe/Prague')::date,
  path     text   not null check (char_length(path) between 1 and 120),
  post_id  bigint references public.posts(id) on delete cascade,
  views    int    not null default 0,
  primary key (day, path)
);
create index if not exists page_views_post_idx on public.page_views (post_id);
alter table public.page_views enable row level security;
-- žádné politiky: tabulku nikdo nečte ani nezapisuje přímo, jen přes funkce níže

create or replace function public.track_view(p_path text, p_post bigint default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_path text := left(coalesce(p_path, ''), 120);
begin
  if v_path !~ '^/[a-z0-9/_-]*$' then return; end if;   -- jen naše adresy
  if p_post is not null then
    if not exists (select 1 from public.posts where id = p_post and public.post_is_live(status, published_at)) then return; end if;
    v_path := '/clanek/' || p_post;
  end if;
  insert into public.page_views (day, path, post_id, views)
  values ((now() at time zone 'Europe/Prague')::date, v_path, p_post, 1)
  on conflict (day, path) do update set views = public.page_views.views + 1;
end $$;

-- denní součty za posledních N dní (včetně dnů s nulou)
create or replace function public.stats_daily(p_days int default 30)
returns table (day date, views bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Jen pro správce.'; end if;
  return query
    select d::date, coalesce(sum(v.views), 0)::bigint
    from generate_series((now() at time zone 'Europe/Prague')::date - (least(greatest(p_days, 1), 366) - 1),
                         (now() at time zone 'Europe/Prague')::date, interval '1 day') d
    left join public.page_views v on v.day = d::date
    group by d order by d;
end $$;

-- součty podle stránek a příspěvků za posledních N dní
create or replace function public.stats_pages(p_days int default 30)
returns table (path text, post_id bigint, title text, views bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Jen pro správce.'; end if;
  return query
    select v.path, v.post_id, p.title, sum(v.views)::bigint
    from public.page_views v left join public.posts p on p.id = v.post_id
    where v.day > (now() at time zone 'Europe/Prague')::date - least(greatest(p_days, 1), 3660)
    group by v.path, v.post_id, p.title
    order by 4 desc;
end $$;

grant execute on function public.track_view(text, bigint) to anon, authenticated;
grant execute on function public.stats_daily(int), public.stats_pages(int) to authenticated;
revoke execute on function public.stats_daily(int), public.stats_pages(int) from anon;


-- ════════ supabase/migrations/008_uzemni_plan.sql ════════
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


-- ════════ supabase/migrations/009_anonymni_hlasovani.sql ════════
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


-- ════════ supabase/migrations/010_dopravni_znaceni.sql ════════
-- Další stálá stránka: Pasport a projekt svislého dopravního značení a dopravního zařízení.
-- Používá stejné tabulky jako Územní plán, jen povolí nový název stránky.
-- Spustit v Supabase SQL Editoru jednou (po 001–009).

alter table public.page_sections drop constraint if exists page_sections_page_check;
alter table public.page_sections add constraint page_sections_page_check
  check (page in ('uzemni-plan', 'dopravni-znaceni'));


-- ════════ supabase/migrations/011_pripnuti.sql ════════
-- Připnutí příspěvku nahoru v Aktualitách / Diskusi. Připnuté jsou první (nejnověji připnuté nahoře),
-- ostatní dál podle data zveřejnění. Připínat smí autoři.
-- Spustit v Supabase SQL Editoru jednou (po 001–010).

alter table public.posts add column if not exists pinned_at timestamptz;

create or replace function public.set_pinned(p_post bigint, p_pinned boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_author() then raise exception 'Připínat mohou jen autoři.'; end if;
  update public.posts set pinned_at = case when p_pinned then now() end where id = p_post;
  if not found then raise exception 'Příspěvek neexistuje.'; end if;
end $$;

grant execute on function public.set_pinned(bigint, boolean) to authenticated;
revoke execute on function public.set_pinned(bigint, boolean) from anon;


-- ════════ supabase/migrations/012_odber_emailem.sql ════════
-- Odběr novinek e-mailem: registrovaný čtenář si v Můj účet zapne nové články a/nebo nové diskuse.
-- Po zveřejnění (i naplánovaném) databáze do 5 minut sama rozešle e-mail přes Brevo API.
-- Spustit v Supabase SQL Editoru jednou (po 001–011).
-- Klíč k Brevo API se ukládá zvlášť do trezoru (Vault), viz README — v tomto souboru není.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- ── kdo co odebírá
alter table public.profiles add column if not exists notify_articles boolean not null default false;
alter table public.profiles add column if not exists notify_discussions boolean not null default false;
alter table public.profiles add column if not exists unsub_token uuid not null default gen_random_uuid();

create or replace function public.set_my_notifications(p_articles boolean, p_discussions boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nejste přihlášeni.'; end if;
  update public.profiles set notify_articles = p_articles, notify_discussions = p_discussions where id = auth.uid();
end $$;

-- odhlášení odkazem z e-mailu, bez přihlášení
create or replace function public.unsubscribe(p_token uuid, p_kind text default 'all') returns text
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  update public.profiles
     set notify_articles    = case when p_kind in ('all','articles') then false else notify_articles end,
         notify_discussions = case when p_kind in ('all','discussions') then false else notify_discussions end
   where unsub_token = p_token
  returning display_name into who;
  return coalesce(who, '');
end $$;

-- ── které příspěvky rozeslat
alter table public.posts add column if not exists notify boolean not null default true;
alter table public.posts add column if not exists notified_at timestamptz;
-- už zveřejněné příspěvky se po zapnutí funkce zpětně nerozesílají
update public.posts set notified_at = now() where notified_at is null and status = 'published' and published_at <= now();

create table if not exists public.notification_log (
  id          bigint generated always as identity primary key,
  post_id     bigint references public.posts(id) on delete set null,
  recipients  int not null,
  request_id  bigint,
  note        text,
  created_at  timestamptz not null default now()
);
alter table public.notification_log enable row level security;
drop policy if exists nlog_admin on public.notification_log;
create policy nlog_admin on public.notification_log for select using (public.is_admin());

-- ── rozeslání (volá ho pg_cron každých 5 minut)
create or replace function public.send_pending_notifications() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  p record; key text; versions jsonb; n int; req bigint; sent int := 0;
  site constant text := 'https://nezavisli3v1.cz';
  html text;
begin
  select decrypted_secret into key from vault.decrypted_secrets where name = 'brevo_api_key' limit 1;
  if key is null then return 0; end if;

  for p in
    select * from public.posts
     where status = 'published' and published_at <= now() and notified_at is null
       and published_at > now() - interval '2 days'
     order by published_at
  loop
    -- označit hned, aby se nic neposlalo dvakrát
    update public.posts set notified_at = now() where id = p.id;
    if not p.notify then continue; end if;

    select jsonb_agg(jsonb_build_object(
             'to', jsonb_build_array(jsonb_build_object('email', u.email)),
             'params', jsonb_build_object('unsub',
               site || '/odhlasit/?t=' || pr.unsub_token || '&k=' || case when p.kind = 'question' then 'discussions' else 'articles' end))),
           count(*)
      into versions, n
      from public.profiles pr join auth.users u on u.id = pr.id
     where u.email is not null
       and case when p.kind = 'question' then pr.notify_discussions else pr.notify_articles end;

    if coalesce(n, 0) = 0 then
      insert into public.notification_log (post_id, recipients, note) values (p.id, 0, 'nikdo neodebírá');
      continue;
    end if;

    html := '<div style="font-family:Arial,sans-serif;color:#16233F;max-width:560px">'
         || '<p style="font-size:12px;letter-spacing:.05em;text-transform:uppercase;color:#1565A0;margin:0 0 6px">'
         || case when p.kind = 'question' then 'Nová diskuse' else 'Nový článek' end || ' · ' || p.category || '</p>'
         || '<h1 style="font-size:22px;margin:0 0 10px">' || replace(replace(p.title, '<', '&lt;'), '>', '&gt;') || '</h1>'
         || '<p style="font-size:16px;line-height:1.5;margin:0 0 18px">' || replace(replace(p.perex, '<', '&lt;'), '>', '&gt;') || '</p>'
         || '<p><a href="' || site || '/clanek/?id=' || p.id || '" style="display:inline-block;background:#2E7D3A;color:#fff;font-weight:bold;padding:12px 20px;border-radius:8px;text-decoration:none">'
         || case when p.kind = 'question' then 'Zapojit se do diskuse' else 'Přečíst na webu' end || '</a></p>'
         || '<p style="font-size:12px;color:#5B6578;margin-top:28px">Tento e-mail dostáváte, protože jste si na nezavisli3v1.cz zapnuli odběr. '
         || '<a href="{{ params.unsub }}" style="color:#5B6578">Odhlásit odběr</a><br>Nezávislí PRO Mokré, Šindlovy Dvory a Litvínovice</p></div>';

    -- Brevo: jedna zpráva, každý příjemce zvlášť (nevidí ostatní adresy), nejvýš 1000 na volání
    select net.http_post(
      url := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('api-key', key, 'content-type', 'application/json', 'accept', 'application/json'),
      body := jsonb_build_object(
        'sender', jsonb_build_object('name', 'Nezávislí PRO', 'email', 'info@nezavisli3v1.cz'),
        'subject', case when p.kind = 'question' then 'Nová diskuse: ' else '' end || p.title,
        'htmlContent', html,
        'messageVersions', versions)
    ) into req;

    insert into public.notification_log (post_id, recipients, request_id) values (p.id, n, req);
    sent := sent + n;
  end loop;
  return sent;
end $$;

revoke execute on function public.send_pending_notifications() from public, anon, authenticated;
grant execute on function public.set_my_notifications(boolean, boolean) to authenticated;
grant execute on function public.unsubscribe(uuid, text) to anon, authenticated;

-- každých 5 minut
select cron.schedule('nz-rozeslat-novinky', '*/5 * * * *', $$select public.send_pending_notifications()$$);

