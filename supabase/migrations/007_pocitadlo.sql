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
