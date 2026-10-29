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
