<script>
  import { api } from '$lib/api.js';
  import { toast } from '$lib/state.svelte.js';
  import { fileSize } from '$lib/util.js';
  import { prepareImage } from '$lib/images.js';
  import Editor from './Editor.svelte';

  // Úprava jednoho oddílu stálé stránky: nadpis, text, obrázky a PDF.
  let { page, section = null, position = 0, onsaved, oncancel } = $props();

  let d = $state({
    id: section?.id ?? null, title: section?.title ?? '', body_html: section?.body_html ?? '', position: section?.position ?? position,
    files: (section?.files ?? []).map((f) => ({ ...f }))
  });
  let busy = $state(false), uploading = $state(''), confirmDel = $state(false);
  const MAX = 25 * 1024 * 1024;

  async function addImages(e) {
    const list = [...e.target.files]; e.target.value = '';
    for (const [i, f] of list.entries()) {
      uploading = `Nahrávám obrázek ${i + 1} z ${list.length}…`;
      try {
        if (f.size > 60 * 1024 * 1024) throw new Error('soubor je příliš velký');
        const prepared = await prepareImage(f);
        if (prepared.main.blob.size > MAX) throw new Error('ani po zmenšení se nevejde do 25 MB');
        d.files.push(await api.uploadPageFile(f, prepared));
      } catch (err) { toast(`„${f.name}“ se nepodařilo nahrát: ${err.message || 'neznámý formát obrázku'}. Zkuste JPG nebo PNG.`); }
    }
    uploading = '';
  }
  async function addPdfs(e) {
    const list = [...e.target.files]; e.target.value = '';
    for (const [i, f] of list.entries()) {
      if (f.type !== 'application/pdf' && !/\.pdf$/i.test(f.name)) { toast(`„${f.name}“ není PDF.`); continue; }
      if (f.size > MAX) { toast(`„${f.name}“ má víc než 25 MB.`); continue; }
      uploading = `Nahrávám PDF ${i + 1} z ${list.length}…`;
      try { d.files.push(await api.uploadPageFile(f)); } catch (err) { toast('PDF se nepodařilo nahrát: ' + err.message); }
    }
    uploading = '';
  }
  function move(i, dir) { const a = d.files; [a[i], a[i + dir]] = [a[i + dir], a[i]]; }

  async function save() {
    if (!d.title.trim()) { toast('Oddíl potřebuje nadpis.'); return; }
    busy = true;
    try { await api.saveSection(page, d); toast('Oddíl uložen.'); onsaved?.(); }
    catch (err) { toast(err.message); } finally { busy = false; }
  }
  async function remove() {
    busy = true;
    try { await api.deleteSection(d.id); toast('Oddíl smazán i se soubory.'); onsaved?.(); }
    catch (err) { toast(err.message); } finally { busy = false; }
  }
</script>

<div class="sed">
  <label class="l" for={`st-${d.id ?? 'new'}`}>Nadpis oddílu</label>
  <input id={`st-${d.id ?? 'new'}`} class="field" bind:value={d.title} maxlength="160" placeholder="Např. Platný územní plán, Změna č. 2">

  <span class="l">Text</span>
  <p class="hint">Co oddíl obsahuje, odkud dokumenty pocházejí a od kdy platí. Odkaz na oficiální verzi na webu obce pomůže.</p>
  <Editor bind:html={d.body_html} placeholder="Krátký popis…" />

  <span class="l">Obrázky a PDF</span>
  <p class="hint">Výkresy nahrajte jako obrázky (JPG, PNG), ať je jde prohlížet přímo na webu. Velké se samy zmenší na 3200 px. Úplné dokumenty přidejte jako PDF, do 25 MB.</p>
  {#if d.files.length}
    <ul class="files">
      {#each d.files as f, i (f.path)}
        <li>
          {#if f.kind === 'image'}<img src={api.pageFileUrl(f.thumb_path || f.path)} alt="">{:else}<span class="pdf" aria-hidden="true">PDF</span>{/if}
          <input class="field" bind:value={f.name} maxlength="160" aria-label={`Název souboru ${i + 1}`}>
          <span class="meta sz">{fileSize(f.size_bytes)}</span>
          <span class="ord">
            <button type="button" class="linkbtn" disabled={i === 0} onclick={() => move(i, -1)} aria-label="Posunout výš">↑</button>
            <button type="button" class="linkbtn" disabled={i === d.files.length - 1} onclick={() => move(i, 1)} aria-label="Posunout níž">↓</button>
            <button type="button" class="linkbtn rm" onclick={() => d.files.splice(i, 1)} aria-label={`Odebrat ${f.name}`}>✕</button>
          </span>
        </li>
      {/each}
    </ul>
  {/if}
  <div class="row">
    <label class="btn ghost">+ Přidat obrázky<input type="file" accept="image/*" multiple onchange={addImages} hidden disabled={!!uploading}></label>
    <label class="btn ghost">+ Přidat PDF<input type="file" accept="application/pdf,.pdf" multiple onchange={addPdfs} hidden disabled={!!uploading}></label>
    {#if uploading}<span class="meta">{uploading}</span>{/if}
  </div>
  <p class="hint warn">Zveřejňujte jen dokumenty obce nebo vlastní. U dokumentů zkontrolujte, že neobsahují jména a adresy soukromých osob.</p>

  <div class="row actions">
    {#if d.id}
      {#if confirmDel}
        <span class="meta">Smazat oddíl i se všemi soubory?</span>
        <button type="button" class="btn danger" disabled={busy} onclick={remove}>Ano, smazat</button>
        <button type="button" class="btn ghost" onclick={() => (confirmDel = false)}>Ne</button>
      {:else}<button type="button" class="btn danger" onclick={() => (confirmDel = true)}>Smazat oddíl…</button>{/if}
    {/if}
    <span class="sp"></span>
    <button type="button" class="btn ghost" onclick={() => oncancel?.()}>Zrušit</button>
    <button type="button" class="btn" disabled={busy || !!uploading || !d.title.trim()} onclick={save}>Uložit oddíl</button>
  </div>
</div>

<style>
  .sed { background: var(--surface); border: 2px solid var(--link); border-radius: 10px; padding: 16px; display: flex; flex-direction: column; gap: 6px; }
  .l { font-weight: 700; font-family: var(--f-display); font-size: 15px; margin-top: 8px; }
  .hint { font-size: 13px; color: var(--muted); margin: 0 0 4px; }
  .hint.warn { color: var(--warn); margin-top: 6px; }
  .files { list-style: none; margin: 4px 0 8px; padding: 0; display: flex; flex-direction: column; gap: 8px; }
  .files li { display: grid; grid-template-columns: 56px 1fr auto auto; gap: 8px; align-items: center; }
  .files img { width: 56px; height: 40px; object-fit: cover; border-radius: 4px; border: 1px solid var(--line); }
  .files .field { min-width: 0; padding: 7px 10px; }
  .pdf { justify-self: center; font-size: 10.5px; font-weight: 700; color: var(--bad); border: 1.5px solid var(--bad); border-radius: 4px; padding: 2px 4px; }
  .ord { display: flex; gap: 10px; }
  .ord .rm { color: var(--bad); }
  .ord button:disabled { opacity: .3; }
  .actions { margin-top: 10px; }
  .sp { flex: 1; }
  @media (max-width: 520px) { .files li { grid-template-columns: 48px 1fr auto; } .files .sz { display: none; } .files img { width: 48px; } }
</style>
