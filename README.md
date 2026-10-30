# nezavisli3v1.cz

Web a aplikace uskupení **Nezávislí PRO Mokré, Šindlovy Dvory a Litvínovice**: zprávy ze zastupitelstva, diskuse s anketami a Hlídač slibů.

- **Web** je sada hotových souborů, které zveřejňuje GitHub Pages.
- **Data** (články, komentáře, ankety, sliby, účty) jsou v databázi Supabase v EU (Frankfurt).
- **Oprávnění** hlídá databáze, ne web. Kdo není autor, článek nenapíše, ani kdyby web obešel.

S proměnnou `PUBLIC_DEMO=1` se web spustí v **ukázkovém režimu** s vymyšleným obsahem. Hodí se k ukázce i k vývoji.

## Role

| role | může |
|---|---|
| nepřihlášený | číst a hlasovat v anketách (jeden hlas na prohlížeč) |
| čtenář | navíc komentovat a odpovídat; hlasuje svým účtem |
| autor | navíc psát a zveřejňovat, moderovat komentáře, uzavírat diskuse, měnit stavy slibů |
| správce | navíc přidělovat role a mazat příspěvky |

Přihlášení je bez hesla, odkazem z e-mailu.

---

## Jednorázové nastavení

Počítejte zhruba s hodinou. Pořadí je důležité.

### 1. GitHub

1. Na github.com založte organizaci **nezavisli3v1** (zdarma) a přidejte do ní aspoň dva vlastníky.
2. Vytvořte v ní veřejný repozitář **nezavisli3v1.github.io**. Díky tomuhle jménu poběží web ještě před přesměrováním domény na adrese https://nezavisli3v1.github.io a dá se vyzkoušet.
3. Nahrajte do něj obsah této složky.
4. **Settings → Pages → Source: GitHub Actions.**

### 2. Supabase

1. Na supabase.com založte projekt. **Region: Central EU (Frankfurt).** Heslo k databázi si uložte, aplikace ho nepotřebuje.
2. **SQL Editor:** vložte celý `supabase/migrations/001_zaklad.sql` a spusťte. Pak totéž s `002_program.sql`, `003_prilohy.sql`, `004_planovani.sql`, `005_mazani_komentaru.sql`, `006_uprava_komentaru.sql`, `007_pocitadlo.sql`, `008_uzemni_plan.sql`, `009_anonymni_hlasovani.sql`, `010_dopravni_znaceni.sql`, `011_pripnuti.sql`, `012_odber_emailem.sql` a `013_obrazek.sql` (nebo vše najednou: `supabase/prvni-spusteni.sql`). Předtím zkontrolujte, že body programu v něm sedí se zveřejněným programem.
3. **Odběr e-mailem:** v Brevu vytvořte API klíč (Settings → SMTP & API → API Keys) a v SQL Editoru ho uložte do trezoru: `select vault.create_secret('KLÍČ', 'brevo_api_key');`. Klíč nikam jinam nekopírujte. Bez klíče se e-maily prostě neposílají. Co se rozeslalo, ukáže `select * from notification_log order by id desc;`.
3. **Authentication → URL Configuration:**
   - Site URL: `https://nezavisli3v1.cz`
   - Redirect URLs: `https://nezavisli3v1.cz/**` a `https://nezavisli3v1.github.io/**`
4. **Authentication → Emails → Magic Link:** předmět „Přihlášení na nezavisli3v1.cz“, obsah zkopírujte z `supabase/email/prihlaseni.html`.
5. **Authentication → Emails → SMTP Settings:** nastavte odesílání přes Brevo (nebo jinou službu). Vestavěné odesílání Supabase posílá jen pár e-mailů za hodinu a hodí se jen na zkoušku.
6. **Project Settings → API:** zkopírujte *Project URL* a *anon public* klíč. Klíč je veřejný, smí být ve webu.

### 3. Propojení

Adresa projektu a **publishable** klíč jsou v `src/lib/config.js`. Klíč je veřejný a smí být ve webu. Klíč *secret* ani *service_role* do kódu nikdy nedávejte.

### 4. První správce

1. Na webu se přihlaste svým e-mailem a vyplňte jméno.
2. V Supabase v **SQL Editoru** spusťte (s vaším e-mailem):
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'vas@email.cz');
   ```
3. Obnovte web. Objeví se záložky **Psaní** a **Lidé**. Další autory už přidáváte v záložce Lidé.

### 5. Doména (Active24)

Až bude web na nezavisli3v1.github.io fungovat:

1. V GitHubu **Settings → Pages → Custom domain:** `nezavisli3v1.cz`.
2. V Active24 v **DNS záznamech domény** nastavte:

   | typ | název | hodnota |
   |---|---|---|
   | A | @ | 185.199.108.153 |
   | A | @ | 185.199.109.153 |
   | A | @ | 185.199.110.153 |
   | A | @ | 185.199.111.153 |
   | CNAME | www | nezavisli3v1.github.io. |

   Původní A záznamy webu (na WordPress) smažte. **MX záznamy a vše kolem e-mailu nechte beze změny**, jinak přestane chodit pošta na @nezavisli3v1.cz.
3. Po pár hodinách v GitHubu zaškrtněte **Enforce HTTPS**.
4. Hosting WordPressu zrušte až poté, co máte přenesený obsah a ověřené, že pošta funguje.

---

## Vývoj

```bash
npm install
npm run dev                  # s ostrou databází na http://localhost:5173
PUBLIC_DEMO=1 npm run dev    # ukázkový režim
```

Každý commit do větve `main` se sám zveřejní.

| složka | co tam je |
|---|---|
| `src/routes/` | stránky (aktuality, diskuse, článek, sliby, přihlášení, účet, psaní, lidé) |
| `src/lib/api-supabase.js` | všechny dotazy do databáze |
| `src/lib/api-demo.js` | ukázkový režim |
| `supabase/migrations/` | databáze a pravidla přístupu |

Změny databáze přidávejte jako nový soubor `supabase/migrations/014_…sql`, nikdy nepřepisujte staré.

## Připravuje se

- upozornění do telefonu a e-maily odběratelům při zveřejnění,
- přenos obsahu a přesměrování starých odkazů z WordPressu,
- mapa podnětů.
