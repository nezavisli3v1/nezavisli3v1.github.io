<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor, toast } from '$lib/state.svelte.js';
  import { clean, date, fileSize } from '$lib/util.js';
  import SectionEditor from '$lib/components/SectionEditor.svelte';

  const PAGE = 'uzemni-plan';
  let sections = $state(null), editing = $state(null), lb = $state(null); // lb = { s, i } otevřený obrázek

  const load = () => api.listSections(PAGE).then((r) => (sections = r)).catch((e) => toast(e.message));
  $effect(() => { session.profile; load(); });

  const images = (s) => s.files.filter((f) => f.kind === 'image');
  const pdfs = (s) => s.files.filter((f) => f.kind === 'pdf');
  const current = $derived(lb && images(lb.s)[lb.i]);

  function step(dir) { const n = images(lb.s).length; lb = { s: lb.s, i: (lb.i + dir + n) % n }; }
  function key(e) {
    if (!lb) return;
    if (e.key === 'Escape') lb = null;
    else if (e.key === 'ArrowRight') step(1);
    else if (e.key === 'ArrowLeft') step(-1);
  }
  async function moveSection(i, dir) {
    const ids = sections.map((s) => s.id); [ids[i], ids[i + dir]] = [ids[i + dir], ids[i]];
    try { await api.reorderSections(ids); await load(); } catch (e) { toast(e.message); }
  }
  function saved() { editing = null; load(); }
</script>

<svelte:head><title>Územní plán · Nezávislí PRO</title></svelte:head>
<svelte:window onkeydown={key} />

<div class="section-head"><div><h1>Územní plán</h1>
  <p class="lede">Územní plán obce Litvínovice a jeho změny přehledně na jednom místě. Výkresy si můžete rozkliknout a přiblížit, úplné dokumenty stáhnout v PDF.</p></div>
  {#if isAuthor() && editing === null && sections}<button class="btn ghost" onclick={() => (editing = 'new')}>+ Přidat oddíl</button>{/if}
</div>

{#if !sections}<p class="empty">Načítám…</p>
{:else}
  {#if !sections.length && editing !== 'new'}<p class="empty">Zatím tu nic není.{#if isAuthor()} Začněte tlačítkem „Přidat oddíl“.{/if}</p>{/if}

  {#each sections as s, si (s.id)}
    {#if editing === s.id}
      <SectionEditor page={PAGE} section={s} onsaved={saved} oncancel={() => (editing = null)} />
    {:else}
      <section class="sec">
        <div class="shead">
          <h2>{s.title}</h2>
          {#if isAuthor() && editing === null}
            <span class="tools">
              <button class="linkbtn" disabled={si === 0} onclick={() => moveSection(si, -1)} aria-label="Posunout oddíl výš">↑</button>
              <button class="linkbtn" disabled={si === sections.length - 1} onclick={() => moveSection(si, 1)} aria-label="Posunout oddíl níž">↓</button>
              <button class="linkbtn" onclick={() => (editing = s.id)}>Upravit</button>
            </span>
          {/if}
        </div>
        <p class="meta">Aktualizováno {date(s.updated_at)}</p>
        {#if s.body_html}<div class="body">{@html clean(s.body_html)}</div>{/if}

        {#if images(s).length}
          <div class="gallery">
            {#each images(s) as f, i (f.id)}
              <button class="thumb" onclick={() => (lb = { s, i })} aria-label={`Zobrazit ${f.name}`}>
                <img src={api.pageFileUrl(f.thumb_path || f.path)} alt={f.name} loading="lazy">
                <span>{f.name}</span>
              </button>
            {/each}
          </div>
        {/if}
        {#if pdfs(s).length}
          <div class="docs">
            {#each pdfs(s) as f (f.id)}
              <a class="doc" href={api.pageFileUrl(f.path)} target="_blank" rel="noopener">
                <span class="pdf" aria-hidden="true">PDF</span><span class="nm">{f.name}</span><span class="meta">{fileSize(f.size_bytes)}</span>
              </a>
            {/each}
          </div>
        {/if}
      </section>
    {/if}
  {/each}

  {#if editing === 'new'}
    <SectionEditor page={PAGE} position={sections.length} onsaved={saved} oncancel={() => (editing = null)} />
  {/if}
{/if}

{#if lb && current}
  <div class="lb" role="dialog" aria-modal="true" aria-label={current.name}>
    <button class="lbbg" aria-label="Zavřít" onclick={() => (lb = null)}></button>
    <figure>
      <img src={api.pageFileUrl(current.path)} alt={current.name}>
      <figcaption>
        <span>{current.name}{#if images(lb.s).length > 1}{` · ${lb.i + 1} / ${images(lb.s).length}`}{/if}</span>
        <a href={api.pageFileUrl(current.path)} target="_blank" rel="noopener">Otevřít v plné velikosti</a>
      </figcaption>
    </figure>
    {#if images(lb.s).length > 1}
      <button class="nav prev" onclick={() => step(-1)} aria-label="Předchozí">‹</button>
      <button class="nav next" onclick={() => step(1)} aria-label="Další">›</button>
    {/if}
    <button class="close" onclick={() => (lb = null)} aria-label="Zavřít">✕</button>
  </div>
{/if}

<style>
  .sec { margin-bottom: 28px; padding-bottom: 20px; border-bottom: 1px solid var(--line); }
  .sec:last-of-type { border-bottom: 0; }
  .shead { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; }
  h2 { font-size: 21px; }
  .tools { display: flex; gap: 14px; flex: none; }
  .tools button:disabled { opacity: .3; }
  .body { margin-top: 8px; }
  .body :global(p) { margin: 0 0 10px; max-width: 65ch; }
  .body :global(h3) { font-size: 17px; margin: 14px 0 6px; }
  .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; margin: 14px 0; }
  .thumb { border: 1px solid var(--line); background: var(--surface); border-radius: 8px; padding: 0; overflow: hidden; text-align: left; display: flex; flex-direction: column; }
  .thumb:hover { border-color: var(--link); }
  .thumb img { width: 100%; aspect-ratio: 4 / 3; object-fit: cover; display: block; background: var(--soft); }
  .thumb span { padding: 8px 10px; font-size: 14px; font-weight: 600; }
  .docs { display: flex; flex-direction: column; gap: 8px; margin-top: 10px; }
  .doc { display: grid; grid-template-columns: auto 1fr auto; gap: 10px; align-items: center; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; color: inherit; text-decoration: none; }
  .doc:hover { border-color: var(--link); }
  .nm { font-weight: 600; min-width: 0; overflow-wrap: anywhere; }
  .pdf { font-size: 10.5px; font-weight: 700; color: var(--bad); border: 1.5px solid var(--bad); border-radius: 4px; padding: 2px 4px; }
  :global(.sed) { margin-bottom: 24px; }

  .lb { position: fixed; inset: 0; z-index: 30; background: #0B0F1A; display: grid; place-items: center; padding: calc(16px + env(safe-area-inset-top, 0px)) max(16px, env(safe-area-inset-right, 0px)) calc(16px + env(safe-area-inset-bottom, 0px)) max(16px, env(safe-area-inset-left, 0px)); }
  .lbbg { position: absolute; inset: 0; background: transparent; border: 0; padding: 0; cursor: zoom-out; }
  figure { position: relative; margin: 0; max-width: 100%; max-height: 100%; display: flex; flex-direction: column; gap: 8px; }
  figure img { max-width: 100%; max-height: calc(100vh - 110px); object-fit: contain; border-radius: 4px; background: #fff; }
  figcaption { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; color: #fff; font-size: 14px; }
  figcaption a { color: #9fd0ff; }
  .nav, .close { position: absolute; border: 0; background: rgba(255,255,255,.14); color: #fff; border-radius: 50%; width: 44px; height: 44px; font-size: 26px; line-height: 1; }
  .nav:hover, .close:hover { background: rgba(255,255,255,.26); }
  .prev { left: max(12px, env(safe-area-inset-left, 0px)); top: 50%; transform: translateY(-50%); }
  .next { right: max(12px, env(safe-area-inset-right, 0px)); top: 50%; transform: translateY(-50%); }
  .close { top: calc(12px + env(safe-area-inset-top, 0px)); right: max(12px, env(safe-area-inset-right, 0px)); font-size: 18px; }
</style>
