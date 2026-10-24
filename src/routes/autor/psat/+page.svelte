<script>
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { api } from '$lib/api.js';
  import { session, isAuthor, isAdmin, toast } from '$lib/state.svelte.js';
  import { CATEGORIES, textLength, fileSize, MAX_ATTACHMENT, isScheduled, isLive, when, localInput } from '$lib/util.js';
  import Editor from '$lib/components/Editor.svelte';

  const editId = $derived(+page.url.searchParams.get('id') || null);
  let d = $state(null), loaded = $state(false), busy = $state(false), uploading = $state(false), uploadingPdf = $state(false), confirmDel = $state(false);
  let hadPoll = false;
  let planning = $state(false), planAt = $state('');

  $effect(() => {
    if (!session.ready || !isAuthor() || loaded) return;
    loaded = true;
    if (!editId) {
      d = { kind: page.url.searchParams.get('druh') === 'question' ? 'question' : 'article', title: '', perex: '', body_html: '',
        category: CATEGORIES[0], cover_path: null, comments_enabled: true, status: 'draft', addPoll: false, attachments: [],
        poll: { question: '', options: ['', ''] } };
      return;
    }
    api.getPost(editId).then((p) => {
      if (!p) { d = false; return; }
      hadPoll = !!p.poll;
      d = { ...p, attachments: p.attachments || [], addPoll: !!p.poll, poll: p.poll ? { question: p.poll.question, options: p.poll.options.map((o) => o.label) } : { question: '', options: ['', ''] } };
    });
  });

  const scheduled = $derived(d && isScheduled(d));
  const live = $derived(d && isLive(d));
  const pollEditable = $derived(d && !live);
  const minPlan = $derived(localInput(new Date(Date.now() + 5 * 60000)));
  function openPlan() {
    const t = d.published_at && scheduled ? new Date(d.published_at) : (() => { const x = new Date(Date.now() + 864e5); x.setHours(8, 0, 0, 0); return x; })();
    planAt = localInput(t); planning = true;
  }
  const missing = $derived(!d ? [] : [
    d.title.trim().length < 3 && 'nadpis',
    !d.perex.trim() && 'shrnutí',
    d.kind === 'article' && textLength(d.body_html) < 20 && 'text',
    d.addPoll && pollEditable && (!d.poll.question.trim() || d.poll.options.filter((o) => o.trim()).length < 2) && 'otázka a aspoň dvě možnosti ankety'
  ].filter(Boolean));

  // fotky z telefonu bývají obří; před nahráním je zmenšíme
  async function shrink(file) {
    if (!file.type.startsWith('image/') || file.type === 'image/gif') return file;
    const img = await createImageBitmap(file);
    const scale = Math.min(1, 1600 / Math.max(img.width, img.height));
    if (scale === 1 && file.size < 600_000) return file;
    const c = Object.assign(document.createElement('canvas'), { width: Math.round(img.width * scale), height: Math.round(img.height * scale) });
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 0.85));
    return new File([blob], file.name.replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' });
  }
  async function pickPhoto(e) {
    const f = e.target.files[0]; if (!f) return;
    uploading = true;
    try { d.cover_path = await api.uploadCover(await shrink(f)); } catch (err) { toast('Fotku se nepodařilo nahrát: ' + err.message); }
    finally { uploading = false; e.target.value = ''; }
  }

  async function pickPdf(e) {
    const list = [...e.target.files]; e.target.value = '';
    for (const f of list) {
      if (f.type !== 'application/pdf' && !/\.pdf$/i.test(f.name)) { toast(`„${f.name}“ není PDF.`); continue; }
      if (f.size > MAX_ATTACHMENT) { toast(`„${f.name}“ má víc než 10 MB. Zkuste ho zmenšit, třeba přes „Uložit jako PDF“ s nižší kvalitou.`); continue; }
      uploadingPdf = true;
      try { d.attachments.push(await api.uploadAttachment(f)); } catch (err) { toast('PDF se nepodařilo nahrát: ' + err.message); }
      finally { uploadingPdf = false; }
    }
  }
  function moveAtt(i, dir) { const a = d.attachments; [a[i], a[i + dir]] = [a[i + dir], a[i]]; }

  // mode: 'draft' | 'now' | 'plan' | 'keep' (uložit změny bez změny data vydání)
  async function save(mode) {
    let publish_at, status = mode === 'draft' ? 'draft' : 'published';
    if (mode === 'plan') {
      const t = new Date(planAt);
      if (isNaN(t) || t <= new Date()) { toast('Zvolte čas v budoucnosti.'); return; }
      publish_at = t.toISOString();
    } else if (mode === 'now' || mode === 'draft') publish_at = null;
    busy = true;
    try {
      const id = await api.savePost({ ...d, status, publish_at, pollEditable: pollEditable || (!hadPoll && d.addPoll),
        poll: d.addPoll ? d.poll : null });
      toast(mode === 'plan' ? `Naplánováno na ${when(publish_at)}. Do té doby ho vidí jen autoři.`
        : { draft: 'Uloženo jako koncept. Vidí ho jen autoři.', now: 'Zveřejněno.', keep: 'Změny uloženy.' }[mode]);
      goto(`/clanek/?id=${id}`);
    } catch (err) { toast(err.message); } finally { busy = false; }
  }
  async function remove() {
    try { await api.deletePost(d.id); toast('Příspěvek smazán.'); goto('/autor/'); } catch (err) { toast(err.message); }
  }
</script>

<svelte:head><title>{editId ? 'Úprava' : 'Nový příspěvek'} · Nezávislí PRO</title></svelte:head>

{#if !session.ready}<p class="empty">Načítám…</p>
{:else if !isAuthor()}<p class="empty">Psát mohou jen autoři. Pokud jím máte být, napište správci webu.</p>
{:else if d === false}<p class="empty">Příspěvek nebyl nalezen.</p>
{:else if d}
  <div class="section-head"><div>
    <h1>{editId ? 'Úprava' : d.kind === 'question' ? 'Nová otázka' : 'Nový článek'}</h1>
    <p class="lede">{live ? 'Příspěvek už je zveřejněný. Změny se projeví hned po uložení.'
      : scheduled ? `Naplánováno na ${when(d.published_at)}. Do té doby ho vidí jen autoři.`
      : 'Rozepsaný text můžete kdykoli uložit jako koncept a dokončit později, nebo naplánovat na konkrétní čas.'}</p>
  </div></div>

  <div class="steps">
    {#if !editId}
      <div class="step"><span class="l"><i>1</i>Co chcete udělat?</span>
        <div class="row">
          <label class="check"><input type="radio" bind:group={d.kind} value="article"><span>Napsat článek<small>Zpráva, shrnutí, vysvětlení</small></span></label>
          <label class="check"><input type="radio" bind:group={d.kind} value="question"><span>Položit otázku<small>Rozjet diskusi k jednomu tématu</small></span></label>
        </div></div>
    {/if}

    <div class="step">
      <label class="l" for="w-title"><i>{editId ? 1 : 2}</i>Nadpis</label>
      <p class="hint">{d.kind === 'question' ? 'Napište otázku tak, jak byste se zeptali souseda.' : 'Co se stalo, jednou větou. Bez zkratek.'}</p>
      <input id="w-title" class="field" bind:value={d.title} maxlength="120" placeholder={d.kind === 'question' ? 'Kde vám v obci chybí přechod?' : 'Zastupitelstvo schválilo rozpočet na rok 2027'}>
      <div class="count">{d.title.length} / 120</div>

      <label class="l sub" for="w-perex">Krátké shrnutí</label>
      <p class="hint">Dvě věty, které si přečte i ten, kdo dál nečte. Objeví se v přehledu a v e-mailu.</p>
      <textarea id="w-perex" class="field" rows="3" bind:value={d.perex} maxlength="300"></textarea>
      <div class="count">{d.perex.length} / 300</div>

      <label class="l sub" for="w-cat">Téma</label>
      <select id="w-cat" class="field" bind:value={d.category}>{#each CATEGORIES as c}<option>{c}</option>{/each}</select>
    </div>

    <div class="step">
      <span class="l"><i>{editId ? 2 : 3}</i>Text {d.kind === 'question' ? '(nepovinný)' : ''}</span>
      <p class="hint">Krátké odstavce. Když je textu víc, pomůže mezititulek.</p>
      <Editor bind:html={d.body_html} placeholder={d.kind === 'question' ? 'Proč se ptáme a co s odpověďmi uděláme…' : 'Začněte psát…'} />
      <div class="photo">
        {#if d.cover_path}<img src={api.coverUrl(d.cover_path)} alt="Náhled fotky">{/if}
        <div class="row">
          <label class="btn ghost">{uploading ? 'Nahrávám…' : d.cover_path ? 'Vyměnit fotku' : 'Přidat fotku'}<input type="file" accept="image/*" onchange={pickPhoto} hidden disabled={uploading}></label>
          {#if d.cover_path}<button type="button" class="linkbtn" onclick={() => (d.cover_path = null)}>Odebrat fotku</button>{/if}
        </div>
        <p class="hint">Používejte jen vlastní fotky, nebo takové, kde máte svolení. Obrázek vytvořený umělou inteligencí označte v textu.</p>
      </div>
    </div>

    <div class="step">
      <span class="l"><i>{editId ? 3 : 4}</i>Přílohy (nepovinné)</span>
      <p class="hint">PDF do 10 MB, třeba zápis, usnesení nebo rozpočet. Název přílohy můžete přepsat, aby bylo jasné, co v ní je.</p>
      {#if d.attachments.length}
        <ul class="atts">
          {#each d.attachments as a, i (a.path)}
            <li>
              <span class="pdf" aria-hidden="true">PDF</span>
              <input class="field" bind:value={a.name} maxlength="160" aria-label={`Název přílohy ${i + 1}`}>
              <span class="meta">{fileSize(a.size_bytes)}</span>
              <span class="ord">
                <button type="button" class="linkbtn" disabled={i === 0} onclick={() => moveAtt(i, -1)} aria-label="Posunout výš">↑</button>
                <button type="button" class="linkbtn" disabled={i === d.attachments.length - 1} onclick={() => moveAtt(i, 1)} aria-label="Posunout níž">↓</button>
                <button type="button" class="linkbtn rm" onclick={() => d.attachments.splice(i, 1)} aria-label={`Odebrat ${a.name}`}>✕</button>
              </span>
            </li>
          {/each}
        </ul>
      {/if}
      <label class="btn ghost addpdf">{uploadingPdf ? 'Nahrávám…' : '+ Přidat PDF'}<input type="file" accept="application/pdf,.pdf" multiple onchange={pickPdf} hidden disabled={uploadingPdf}></label>
      <p class="hint warn">Před nahráním zkontrolujte, že dokument neobsahuje jména, adresy, rodná čísla ani jiné osobní údaje soukromých lidí. Pokud ano, začerněte je.</p>
    </div>

    <div class="step">
      <span class="l"><i>{editId ? 4 : 5}</i>Diskuse a anketa</span>
      <label class="check"><input type="checkbox" bind:checked={d.comments_enabled}><span>Povolit komentáře<small>Doporučujeme vždy. Moderovat můžete i potom.</small></span></label>
      {#if pollEditable || !hadPoll}
        <label class="check"><input type="checkbox" bind:checked={d.addPoll}><span>Přidat anketu<small>Po zveřejnění už ji nejde měnit, aby se nepřepsaly hlasy.</small></span></label>
        {#if d.addPoll}
          <div class="pollopts">
            <input class="field" bind:value={d.poll.question} placeholder="Otázka ankety" aria-label="Otázka ankety" maxlength="200">
            {#each d.poll.options as _, i}
              <div class="row"><input class="field" style="flex:1" bind:value={d.poll.options[i]} placeholder={`Možnost ${i + 1}`} aria-label={`Možnost ${i + 1}`} maxlength="120">
                {#if d.poll.options.length > 2}<button type="button" class="linkbtn" onclick={() => d.poll.options.splice(i, 1)} aria-label="Odebrat možnost">✕</button>{/if}</div>
            {/each}
            {#if d.poll.options.length < 8}<button type="button" class="btn ghost" onclick={() => d.poll.options.push('')}>+ Další možnost</button>{/if}
          </div>
        {/if}
      {:else}<p class="meta">Anketa je zveřejněná a už ji nejde měnit.</p>{/if}
    </div>

    {#if editId && isAdmin()}
      <div class="step">
        <span class="l">Smazat příspěvek</span>
        <p class="hint">Smaže se i všechny komentáře a hlasy. Nejde to vrátit. U zveřejněného příspěvku je lepší diskusi uzavřít.</p>
        {#if confirmDel}<div class="row"><button class="btn danger" onclick={remove}>Ano, smazat</button><button class="btn ghost" onclick={() => (confirmDel = false)}>Ne</button></div>
        {:else}<button class="btn danger" onclick={() => (confirmDel = true)}>Smazat…</button>{/if}
      </div>
    {/if}
  </div>

  <div class="publish">
    {#if planning}
      <label class="plan" for="w-plan">Vydat
        <input id="w-plan" type="datetime-local" class="field" bind:value={planAt} min={minPlan} step="300">
      </label>
      <button class="btn ghost" disabled={busy} onclick={() => (planning = false)}>Zrušit</button>
      <button class="btn" disabled={busy || missing.length > 0 || !planAt} onclick={() => save('plan')}>Naplánovat</button>
    {:else}
      {#if missing.length}<span class="missing">Ještě chybí: {missing.join(', ')}</span>{/if}
      {#if live}
        <button class="btn ghost" disabled={busy} onclick={() => save('draft')}>Stáhnout mezi koncepty</button>
        <button class="btn" disabled={busy || missing.length > 0} onclick={() => save('keep')}>Uložit změny</button>
      {:else if scheduled}
        <button class="btn ghost" disabled={busy} onclick={() => save('draft')}>Zrušit plán</button>
        <button class="btn ghost" disabled={busy || missing.length > 0} onclick={openPlan}>Změnit čas</button>
        <button class="btn ghost" disabled={busy || missing.length > 0} onclick={() => save('keep')}>Uložit změny</button>
        <button class="btn" disabled={busy || missing.length > 0} onclick={() => save('now')}>Zveřejnit hned</button>
      {:else}
        <button class="btn ghost" disabled={busy || d.title.trim().length < 3} onclick={() => save('draft')}>Uložit koncept</button>
        <button class="btn ghost" disabled={busy || missing.length > 0} onclick={openPlan}>Naplánovat…</button>
        <button class="btn" disabled={busy || missing.length > 0} onclick={() => save('now')}>Zveřejnit</button>
      {/if}
    {/if}
  </div>
{/if}

<style>
  .steps { display: flex; flex-direction: column; gap: 16px; }
  .step { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 16px; display: flex; flex-direction: column; }
  .l { display: flex; gap: 10px; align-items: center; font-weight: 700; font-family: var(--f-display); font-size: 16px; margin-bottom: 4px; }
  .l.sub { font-size: 14px; margin-top: 10px; }
  .l i { font-style: normal; width: 24px; height: 24px; border-radius: 50%; background: var(--navy); color: #fff; display: inline-grid; place-items: center; font-size: 13px; flex: none; }
  .hint { font-size: 13px; color: var(--muted); margin: 0 0 8px; }
  .count { font-size: 12px; color: var(--muted); text-align: right; font-variant-numeric: tabular-nums; margin-top: 2px; }
  .photo { display: flex; flex-direction: column; gap: 8px; margin-top: 12px; }
  .photo img { max-height: 200px; object-fit: cover; border-radius: 6px; width: 100%; }
  .photo .hint { margin: 0; }
  .pollopts { display: flex; flex-direction: column; gap: 6px; margin-top: 6px; align-items: stretch; }
  .pollopts > .btn { align-self: flex-start; }
  .publish { position: sticky; bottom: 0; z-index: 4; background: var(--surface); border-top: 1px solid var(--line); margin: 16px calc(-1 * max(16px, env(safe-area-inset-left, 0px))) 0; padding: 12px max(16px, env(safe-area-inset-right, 0px)) calc(12px + env(safe-area-inset-bottom, 0px)) max(16px, env(safe-area-inset-left, 0px)); display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; align-items: center; }
  .atts { list-style: none; margin: 0 0 10px; padding: 0; display: flex; flex-direction: column; gap: 8px; }
  .atts li { display: grid; grid-template-columns: auto 1fr auto auto; gap: 8px; align-items: center; }
  .atts .field { min-width: 0; padding: 7px 10px; }
  .pdf { font-size: 10.5px; font-weight: 700; color: var(--bad); border: 1.5px solid var(--bad); border-radius: 4px; padding: 2px 4px; }
  .ord { display: flex; gap: 10px; }
  .ord .rm { color: var(--bad); }
  .ord button:disabled { opacity: .3; }
  .addpdf { align-self: flex-start; }
  .hint.warn { color: var(--warn); margin-top: 10px; }
  @media (max-width: 520px) { .atts li { grid-template-columns: auto 1fr auto; } .atts .meta { display: none; } }
  .plan { display: flex; align-items: center; gap: 8px; font-weight: 600; margin-right: auto; }
  .plan .field { width: auto; padding: 8px 10px; }
  .missing { font-size: 13px; color: var(--warn); margin-right: auto; }
</style>
