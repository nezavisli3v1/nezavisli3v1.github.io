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
