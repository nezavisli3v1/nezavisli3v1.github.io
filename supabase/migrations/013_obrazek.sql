-- Obrázek bez článku (kreslený vtip, fotka dne): nový druh příspěvku 'picture'.
-- Nadpis i text jsou nepovinné, povinný je jen obrázek. Patří do Aktualit a do odběru nových článků.
-- Spustit v Supabase SQL Editoru jednou (po 001–012).

alter table public.posts drop constraint if exists posts_kind_check;
alter table public.posts add constraint posts_kind_check check (kind in ('article','question','picture'));

alter table public.posts drop constraint if exists posts_title_check;
alter table public.posts add constraint posts_title_check
  check (char_length(title) <= 120 and (kind = 'picture' or char_length(title) >= 3));

-- obrázek musí mít obrázek (koncept může být rozpracovaný)
alter table public.posts drop constraint if exists posts_picture_image;
alter table public.posts add constraint posts_picture_image
  check (kind <> 'picture' or status = 'draft' or cover_path is not null);

-- e-mail odběratelům: u obrázku je obrázek přímo v e-mailu, nadpis nepovinný
create or replace function public.send_pending_notifications() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare
  p record; key text; versions jsonb; n int; req bigint; sent int := 0;
  site constant text := 'https://nezavisli3v1.cz';
  img_base constant text := 'https://doxuzmvntnsbasgbdiot.supabase.co/storage/v1/object/public/covers/';
  label text; subject text;
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

    label := case p.kind when 'question' then 'Nová diskuse' when 'picture' then 'Nový obrázek' else 'Nový článek' end;
    subject := case when p.kind = 'question' then 'Nová diskuse: ' || p.title
                    when p.kind = 'picture' then coalesce(nullif(p.title, ''), 'Nový obrázek na nezavisli3v1.cz')
                    else p.title end;
    html := '<div style="font-family:Arial,sans-serif;color:#16233F;max-width:560px">'
         || '<p style="font-size:12px;letter-spacing:.05em;text-transform:uppercase;color:#1565A0;margin:0 0 6px">'
         || label || case when p.kind = 'picture' then '' else ' · ' || p.category end || '</p>'
         || case when p.title <> '' then '<h1 style="font-size:22px;margin:0 0 10px">' || replace(replace(p.title, '<', '&lt;'), '>', '&gt;') || '</h1>' else '' end
         || case when p.kind = 'picture' and p.cover_path is not null then
              '<p style="margin:0 0 12px"><a href="' || site || '/clanek/?id=' || p.id || '"><img src="' || img_base || p.cover_path || '" alt="" style="max-width:100%;height:auto;border-radius:8px"></a></p>' else '' end
         || case when p.perex <> '' then '<p style="font-size:16px;line-height:1.5;margin:0 0 18px">' || replace(replace(p.perex, '<', '&lt;'), '>', '&gt;') || '</p>' else '' end
         || '<p><a href="' || site || '/clanek/?id=' || p.id || '" style="display:inline-block;background:#2E7D3A;color:#fff;font-weight:bold;padding:12px 20px;border-radius:8px;text-decoration:none">'
         || case p.kind when 'question' then 'Zapojit se do diskuse' when 'picture' then 'Podívat se na webu' else 'Přečíst na webu' end || '</a></p>'
         || '<p style="font-size:12px;color:#5B6578;margin-top:28px">Tento e-mail dostáváte, protože jste si na nezavisli3v1.cz zapnuli odběr. '
         || '<a href="{{ params.unsub }}" style="color:#5B6578">Odhlásit odběr</a><br>Nezávislí PRO Mokré, Šindlovy Dvory a Litvínovice</p></div>';

    -- Brevo: jedna zpráva, každý příjemce zvlášť (nevidí ostatní adresy), nejvýš 1000 na volání
    select net.http_post(
      url := 'https://api.brevo.com/v3/smtp/email',
      headers := jsonb_build_object('api-key', key, 'content-type', 'application/json', 'accept', 'application/json'),
      body := jsonb_build_object(
        'sender', jsonb_build_object('name', 'Nezávislí PRO', 'email', 'info@nezavisli3v1.cz'),
        'subject', subject,
        'htmlContent', html,
        'messageVersions', versions)
    ) into req;

    insert into public.notification_log (post_id, recipients, request_id) values (p.id, n, req);
    sent := sent + n;
  end loop;
  return sent;
end $$;

revoke execute on function public.send_pending_notifications() from public, anon, authenticated;
