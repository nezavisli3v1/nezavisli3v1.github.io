<script>
  import { api } from '$lib/api.js';
  import { session, isAdmin, toast } from '$lib/state.svelte.js';

  const RANGES = [7, 30, 90];
  const PAGE_NAMES = { '/': 'Aktuality (úvod)', '/diskuse/': 'Diskuse', '/sliby/': 'Hlídač slibů', '/pravidla/': 'Pravidla a ochrana údajů', '/prihlaseni/': 'Přihlášení' };
  const fmtDay = new Intl.DateTimeFormat('cs-CZ', { weekday: 'short', day: 'numeric', month: 'numeric' });
  const fmtShort = new Intl.DateTimeFormat('cs-CZ', { day: 'numeric', month: 'numeric' });
  const num = new Intl.NumberFormat('cs-CZ');

  let days = $state(30), daily = $state(null), pages = $state(null), hover = $state(null);

  $effect(() => {
    if (!isAdmin()) return;
    const d = days;
    daily = null; pages = null; hover = null;
    Promise.all([api.statsDaily(d), api.statsPages(d)])
      .then(([a, b]) => { daily = a.map((r) => ({ day: new Date(r.day + 'T12:00:00'), views: Number(r.views) })); pages = b; })
      .catch((e) => toast(e.message));
  });

  const total = $derived(daily ? daily.reduce((s, r) => s + r.views, 0) : 0);
  const today = $derived(daily?.at(-1)?.views ?? 0);
  const best = $derived(daily?.length ? daily.reduce((a, b) => (b.views > a.views ? b : a)) : null);
  const posts = $derived((pages || []).filter((p) => p.post_id));
  const other = $derived((pages || []).filter((p) => !p.post_id));

  // osa: „hezké“ maximum a tři čáry mřížky
  function niceMax(v) {
    if (v <= 4) return 4;
    const p = 10 ** Math.floor(Math.log10(v)), n = v / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
  }
  const max = $derived(niceMax(Math.max(1, ...(daily || []).map((r) => r.views))));
  const W = 640, H = 180, PAD_L = 36, PAD_B = 22, PAD_T = 8;
  const plotW = W - PAD_L, plotH = H - PAD_B - PAD_T;
  const step = $derived(daily ? plotW / daily.length : 0);
  const barW = $derived(Math.max(2, step - 2));           // 2px mezera mezi sloupci
  const y = (v) => PAD_T + plotH - (v / max) * plotH;
  function bar(i, v) {                                      // zaoblený jen horní konec, 4px
    const x = PAD_L + i * step + 1, top = y(v), h = PAD_T + plotH - top, r = Math.min(4, barW / 2, h);
    if (h <= 0) return '';
    return `M${x},${PAD_T + plotH}V${top + r}Q${x},${top} ${x + r},${top}H${x + barW - r}Q${x + barW},${top} ${x + barW},${top + r}V${PAD_T + plotH}Z`;
  }
  const ticks = $derived(daily ? [0, Math.floor((daily.length - 1) / 2), daily.length - 1] : []);
</script>

<svelte:head><title>Statistiky · Nezávislí PRO</title></svelte:head>

{#if !session.ready}<p class="empty">Načítám…</p>
{:else if !isAdmin()}<p class="empty">Tahle část je jen pro správce.</p>
{:else}
  <div class="section-head"><div><h1>Statistiky</h1>
    <p class="lede">Kolikrát byly stránky otevřeny. Počítá se každé otevření, ne jednotliví lidé, a nic se o návštěvnících neukládá. Nepočítají se návštěvy autorů ani návštěvy ze zařízení, kde se někdy autor přihlásil, a to ani po odhlášení. Čísla vidí jen správce.</p></div>
    <div class="range" role="group" aria-label="Období">
      {#each RANGES as r}<button aria-pressed={days === r} onclick={() => (days = r)}>{r} dní</button>{/each}
    </div>
  </div>

  {#if !daily}<p class="empty">Načítám…</p>
  {:else}
    <div class="tiles">
      <div class="tile"><span>Za {days} dní</span><b>{num.format(total)}</b></div>
      <div class="tile"><span>Průměr za den</span><b>{num.format(Math.round(total / days))}</b></div>
      <div class="tile"><span>Dnes</span><b>{num.format(today)}</b></div>
      <div class="tile"><span>Nejlepší den</span><b>{best && best.views ? num.format(best.views) : '–'}</b><small>{best && best.views ? fmtDay.format(best.day) : ''}</small></div>
    </div>

    <section class="box chart">
      <div class="chead"><h2>Zobrazení po dnech</h2>
        <span class="readout" aria-live="polite">{hover !== null ? `${fmtDay.format(daily[hover].day)}: ${num.format(daily[hover].views)} zobrazení` : 'Najeďte na sloupec'}</span></div>
      <div class="svgwrap">
        <svg viewBox="0 0 {W} {H}" role="img" aria-label="Sloupcový graf zobrazení po dnech za posledních {days} dní" onmouseleave={() => (hover = null)}>
          {#each [0, max / 2, max] as t}
            <line x1={PAD_L} x2={W} y1={y(t)} y2={y(t)} class="grid" />
            <text x={PAD_L - 6} y={y(t) + 4} class="ax" text-anchor="end">{num.format(t)}</text>
          {/each}
          {#each daily as r, i}
            <path d={bar(i, r.views)} class="bar" class:on={hover === i} />
            <rect x={PAD_L + i * step} y={PAD_T} width={step} height={plotH} class="hit"
              role="button" tabindex="0" aria-label={`${fmtDay.format(r.day)}: ${r.views} zobrazení`}
              onmouseenter={() => (hover = i)} onfocus={() => (hover = i)} onblur={() => (hover = null)} />
          {/each}
          {#each ticks as i}
            <text x={PAD_L + i * step + step / 2} y={H - 6} class="ax" text-anchor={i === 0 ? 'start' : i === daily.length - 1 ? 'end' : 'middle'}>{fmtShort.format(daily[i].day)}</text>
          {/each}
        </svg>
      </div>
    </section>

    <div class="cols">
      <section class="box">
        <h2>Příspěvky</h2>
        {#if !posts.length}<p class="meta">Za toto období žádné zobrazení příspěvků.</p>
        {:else}
          <table><thead><tr><th>Příspěvek</th><th class="n">Zobrazení</th></tr></thead><tbody>
            {#each posts as p (p.path)}
              <tr><td><a href={`/clanek/?id=${p.post_id}`}>{p.title || '(smazaný příspěvek)'}</a></td><td class="n">{num.format(p.views)}</td></tr>
            {/each}
          </tbody></table>
        {/if}
      </section>
      <section class="box">
        <h2>Stránky</h2>
        {#if !other.length}<p class="meta">Za toto období žádná zobrazení.</p>
        {:else}
          <table><thead><tr><th>Stránka</th><th class="n">Zobrazení</th></tr></thead><tbody>
            {#each other as p (p.path)}
              <tr><td>{PAGE_NAMES[p.path] || p.path}</td><td class="n">{num.format(p.views)}</td></tr>
            {/each}
          </tbody></table>
        {/if}
      </section>
    </div>
  {/if}
{/if}

<style>
  .range { display: flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
  .range button { border: 0; background: var(--surface); padding: 7px 12px; font-size: 14px; font-weight: 600; color: var(--muted); }
  .range button + button { border-left: 1px solid var(--line); }
  .range button[aria-pressed="true"] { background: var(--navy); color: #fff; }
  .tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-bottom: 14px; }
  .tile { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; display: flex; flex-direction: column; }
  .tile span { font-size: 12px; color: var(--muted); }
  .tile b { font-family: var(--f-display); font-size: 24px; font-variant-numeric: tabular-nums; }
  .tile small { font-size: 12px; color: var(--muted); }
  .box { margin-bottom: 14px; }
  h2 { font-size: 16px; margin-bottom: 8px; }
  .chead { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; flex-wrap: wrap; }
  .readout { font-size: 13px; color: var(--muted); font-variant-numeric: tabular-nums; }
  .svgwrap { overflow-x: auto; }
  svg { width: 100%; height: auto; display: block; min-width: 320px; }
  .grid { stroke: var(--line); stroke-width: 1; }
  .ax { fill: var(--muted); font-size: 11px; font-variant-numeric: tabular-nums; }
  .bar { fill: var(--accent); opacity: .85; }
  .bar.on { opacity: 1; }
  .hit { fill: transparent; cursor: default; }
  .hit:focus { outline: none; }
  .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
  .cols .box { margin: 0; min-width: 0; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th { text-align: left; font-size: 12px; color: var(--muted); font-weight: 600; padding: 4px 0; border-bottom: 1px solid var(--line); }
  td { padding: 7px 0; border-bottom: 1px solid var(--line); vertical-align: top; overflow-wrap: anywhere; }
  .n { text-align: right; padding-left: 10px; font-variant-numeric: tabular-nums; white-space: nowrap; }
  @media (max-width: 620px) { .tiles { grid-template-columns: repeat(2, 1fr); } .cols { grid-template-columns: 1fr; } .ax { font-size: 19px; } }
</style>
