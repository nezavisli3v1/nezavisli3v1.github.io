# nezavisli3v1.cz

Web a aplikace uskupení **Nezávislí PRO Mokré, Šindlovy Dvory a Litvínovice**: zprávy ze zastupitelstva, diskuse s anketami a Hlídač slibů.

- **Web** je sada hotových souborů, které zveřejňuje GitHub Pages.
- **Data** (články, komentáře, ankety, sliby, účty) jsou v databázi Supabase v EU (Frankfurt).
- **Oprávnění** hlídá databáze, ne web. Kdo není autor, článek nenapíše, ani kdyby web obešel.

Bez nastavené databáze se web spustí v **ukázkovém režimu** s vymyšleným obsahem. Hodí se k ukázce i k vývoji.

## Role

| role | může |
|---|---|
| nepřihlášený | číst |
| čtenář | navíc komentovat, odpovídat a hlasovat v anketách |
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
2. **SQL Editor:** vložte celý `supabase/migrations/001_zaklad.sql` a spusťte. Pak totéž s `002_program.sql` a `003_prilohy.sql`. Předtím zkontrolujte, že body programu v něm sedí se zveřejněným programem.
3. **Authentication → URL Configuration:**
   - Site URL: `https://nezavisli3v1.cz`
   - Redirect URLs: `https://nezavisli3v1.cz/**` a `https://nezavisli3v1.github.io/**`
4. **Authentication → Emails → Magic Link:** předmět „Přihlášení na nezavisli3v1.cz“, obsah zkopírujte z `supabase/email/prihlaseni.html`.
5. **Authentication → Emails → SMTP Settings:** nastavte odesílání přes Brevo (nebo jinou službu). Vestavěné odesílání Supabase posílá jen pár e-mailů za hodinu a hodí se jen na zkoušku.
6. **Project Settings → API:** zkopírujte *Project URL* a *anon public* klíč. Klíč je veřejný, smí být ve webu.

### 3. Propojení

1. V repozitáři: **Settings → Secrets and variables → Actions → Variables**, přidejte:
   - `PUBLIC_SUPABASE_URL` = Project URL
   - `PUBLIC_SUPABASE_ANON_KEY` = anon public klíč
2. **Actions → Nasazení webu → Run workflow.** Za dvě minuty je web na https://nezavisli3v1.github.io.

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
npm run dev        # ukázkový režim na http://localhost:5173
```

S opravdovou databází: zkopírujte `.env.example` do `.env` a vyplňte. Každý commit do větve `main` se sám zveřejní.

| složka | co tam je |
|---|---|
| `src/routes/` | stránky (aktuality, diskuse, článek, sliby, přihlášení, účet, psaní, lidé) |
| `src/lib/api-supabase.js` | všechny dotazy do databáze |
| `src/lib/api-demo.js` | ukázkový režim |
| `supabase/migrations/` | databáze a pravidla přístupu |

Změny databáze přidávejte jako nový soubor `supabase/migrations/004_…sql`, nikdy nepřepisujte staré.

## Připravuje se

- upozornění do telefonu a e-maily odběratelům při zveřejnění,
- přenos obsahu a přesměrování starých odkazů z WordPressu,
- mapa podnětů.
