<script>
  import '@fontsource/inter/400.css';
  import '@fontsource/inter/500.css';
  import '@fontsource/inter/600.css';
  import '@fontsource/inter/700.css';
  import '@fontsource/archivo/700.css';
  import '@fontsource/archivo/800.css';
  import '../app.css';
  import { page } from '$app/state';
  import { api } from '$lib/api.js';
  import { session, toastState, startSession, isAuthor, isAdmin } from '$lib/state.svelte.js';

  let { children } = $props();
  startSession();

  let demoUser = $state(null);

  // počítadlo: jedno zobrazení na otevřenou stránku; tým se nepočítá, administrace taky ne
  // Zařízení, kde se někdy přihlásil autor, se nepočítá ani po odhlášení (týmové testování).
  const TEAM_KEY = 'nz-tymove-zarizeni';
  const teamDevice = () => { try { return localStorage.getItem(TEAM_KEY) === '1'; } catch { return false; } };
  $effect(() => { if (isAuthor()) { try { localStorage.setItem(TEAM_KEY, '1'); } catch {} } });
  let lastTracked = '';
  $effect(() => {
    const url = page.url;
    if (!session.ready || isAuthor() || teamDevice()) return;
    const key = url.pathname + url.search;
    if (key === lastTracked || /^\/(autor|ucet|prihlaseni)/.test(url.pathname)) return;
    lastTracked = key;
    const id = url.pathname === '/clanek/' ? +url.searchParams.get('id') || null : null;
    api.trackView(url.pathname, id);
  });
  const path = $derived(page.url.pathname);
  const tabs = $derived([
    { href: '/', label: 'Aktuality', on: path === '/' || path.startsWith('/clanek') },
    { href: '/diskuse/', label: 'Diskuse', on: path.startsWith('/diskuse') },
    { href: '/uzemni-plan/', label: 'Územní plán', on: path.startsWith('/uzemni-plan') },
    { href: '/sliby/', label: 'Hlídač slibů', on: path.startsWith('/sliby') },
    ...(isAuthor() ? [{ href: '/autor/', label: 'Psaní', on: path.startsWith('/autor') && !path.startsWith('/autor/lide') && !path.startsWith('/autor/statistiky') }] : []),
    ...(isAdmin() ? [{ href: '/autor/statistiky/', label: 'Statistiky', on: path.startsWith('/autor/statistiky') }] : []),
    ...(isAdmin() ? [{ href: '/autor/lide/', label: 'Lidé', on: path.startsWith('/autor/lide') }] : [])
  ]);
</script>

<header class="top">
  <div class="wrap">
    <a class="brand" href="/">
      <b>NEZÁVISLÍ <span>PRO</span> <span class="kost" aria-hidden="true"><i></i><i></i><i></i></span></b>
      <small>Mokré · Šindlovy Dvory · Litvínovice</small>
    </a>
    {#if session.ready}
      {#if session.user}
        <a class="who" href="/ucet/">{session.profile?.display_name || 'Můj účet'}</a>
      {:else}
        <a class="who" href={`/prihlaseni/?next=${encodeURIComponent(path)}`}>Přihlásit</a>
      {/if}
    {/if}
  </div>
</header>

{#if api.demo}
  <div class="demo"><div class="wrap">
    <span>Ukázkový režim: obsah je vymyšlený a po obnovení stránky zmizí. Zobrazit jako</span>
    <select class="demosel" bind:value={demoUser} onchange={() => api.demoAs(demoUser)} aria-label="Zobrazit jako">
      {#each api.demoUsers as u}<option value={u.id}>{u.label}</option>{/each}
    </select>
  </div></div>
{/if}

<nav class="tabs" aria-label="Hlavní menu"><div class="wrap">
  {#each tabs as t}<a href={t.href} aria-current={t.on ? 'page' : undefined}>{t.label}</a>{/each}
</div></nav>

<main><div class="wrap">{@render children()}</div></main>

<footer><div class="wrap">
  <span><b>Nezávislí PRO</b> Mokré, Šindlovy Dvory a Litvínovice</span>
  <span><a href="/pravidla/">Pravidla diskuse a ochrana údajů</a> · info@nezavisli3v1.cz</span>
</div></footer>

{#if toastState.text}<div class="toast" role="status">{toastState.text}</div>{/if}

<style>
  .top { background: var(--head); color: #fff; }
  .top .wrap { padding-block: calc(14px + env(safe-area-inset-top, 0px)) 12px; display: flex; align-items: center; gap: 12px; }
  .brand { display: flex; flex-direction: column; gap: 2px; margin-right: auto; color: #fff; text-decoration: none; }
  .brand b { font-family: var(--f-display); font-weight: 800; letter-spacing: .04em; font-size: 18px; }
  .brand b span { font-weight: 700; opacity: .85; }
  .brand small { font-size: 11.5px; opacity: .75; letter-spacing: .03em; }
  .kost { display: inline-flex; gap: 4px; vertical-align: middle; }
  .kost i { width: 7px; height: 7px; display: block; }
  .kost i:nth-child(1) { background: #8FA3C8; } .kost i:nth-child(2) { background: #5DBB6D; } .kost i:nth-child(3) { background: #4A9BE0; }
  .who { color: #fff; font-size: 14px; font-weight: 600; text-decoration: none; border: 1px solid rgba(255,255,255,.35); border-radius: 999px; padding: 6px 14px; max-width: 45vw; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .demo { background: var(--warnsoft); color: var(--warn); font-size: 13px; }
  .demo .wrap { padding-block: 7px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .demosel { border: 1px solid currentColor; background: var(--surface); color: var(--fg); border-radius: 6px; padding: 2px 6px; font-size: 13px; }
  .tabs { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; background: var(--surface); border-bottom: 1px solid var(--line); }
  .tabs .wrap { display: flex; gap: 2px; overflow-x: auto; scrollbar-width: none; }
  .tabs a { padding: 12px 12px 10px; font-weight: 600; font-size: 14px; color: var(--muted); border-bottom: 3px solid transparent; white-space: nowrap; text-decoration: none; }
  .tabs a[aria-current] { color: var(--fg); border-bottom-color: var(--accent); }
  footer { border-top: 1px solid var(--line); font-size: 13px; color: var(--muted); }
  footer .wrap { padding-block: 18px calc(18px + env(safe-area-inset-bottom, 0px)); display: flex; flex-direction: column; gap: 4px; }
  .toast { position: fixed; left: 50%; bottom: calc(20px + env(safe-area-inset-bottom, 0px)); transform: translateX(-50%); background: var(--navy); color: #fff; padding: 10px 16px; border-radius: 8px; font-size: 14px; z-index: 20; box-shadow: 0 6px 20px rgba(0,0,0,.2); max-width: calc(100% - 32px); }
  @media (max-width: 520px) { .tabs a { padding: 11px 9px 9px; font-size: 13.5px; } }
</style>
