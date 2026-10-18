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
