-- Další stálá stránka: Pasport a projekt svislého dopravního značení a dopravního zařízení.
-- Používá stejné tabulky jako Územní plán, jen povolí nový název stránky.
-- Spustit v Supabase SQL Editoru jednou (po 001–009).

alter table public.page_sections drop constraint if exists page_sections_page_check;
alter table public.page_sections add constraint page_sections_page_check
  check (page in ('uzemni-plan', 'dopravni-znaceni'));
