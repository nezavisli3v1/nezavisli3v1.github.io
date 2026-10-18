<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor, isAdmin, toast, refreshProfile } from '$lib/state.svelte.js';
  import { date, HIDE_REASONS } from '$lib/util.js';
  let { post } = $props();

  let list = $state([]), text = $state(''), name = $state(''), busy = $state(false);
  let replyTo = $state(null), replyText = $state(''), modFor = $state(null), delFor = $state(null);
  const canDelete = (c) => session.user && (c.author_id === session.user.id || isAdmin());

  const load = () => api.listComments(post.id).then((c) => (list = c));
  $effect(() => { session.profile; load(); });
  const roots = $derived(list.filter((c) => !c.parent_id));
  const repliesOf = (id) => list.filter((c) => c.parent_id === id);
  const open = $derived(post.comments_enabled && !post.closed_at);
  const needName = $derived(session.user && !session.profile?.display_name);
  const loginHref = $derived(`/prihlaseni/?next=${encodeURIComponent(`/clanek/?id=${post.id}`)}`);

  async function send(body, parentId) {
    busy = true;
    try {
      if (needName) { await api.setMyName(name); await refreshProfile(); }
      await api.addComment(post.id, body, parentId);
      await load(); toast(parentId ? 'Odpověď přidána.' : 'Komentář přidán.');
      return true;
    } catch (e) { toast(e.message); return false; } finally { busy = false; }
  }
  async function submit(e) { e.preventDefault(); if (text.trim() && await send(text)) text = ''; }
  async function submitReply(e) { e.preventDefault(); if (replyText.trim() && await send(replyText, replyTo)) { replyTo = null; replyText = ''; } }
  async function del(c) {
    try { await api.deleteComment(c.id); delFor = null; await load(); toast('Komentář smazán.'); } catch (e) { toast(e.message); }
  }
  async function hide(id, why) { try { await api.hideComment(id, why); modFor = null; await load(); toast(`Komentář je skrytý. Důvod „${why}“ vidí všichni.`); } catch (e) { toast(e.message); } }
  async function unhide(id) { try { await api.unhideComment(id); await load(); } catch (e) { toast(e.message); } }
</script>

{#snippet comment(c, depth)}
  <div class="c" class:official={c.author_is_team && !c.hidden_reason}>
    <div class="who">{c.author_name}
      {#if c.author_badge}<span class="badge">{c.author_badge}</span>{:else if c.author_is_team}<span class="badge blue">Nezávislí PRO</span>{/if}
      <span class="meta">{date(c.created_at)}</span></div>
    {#if c.hidden_reason}
      <div class="hidden">Komentář skryl moderátor. Důvod: {c.hidden_reason}.
        {#if isAuthor()}<br><span class="orig">Původní text (vidí jen autoři): {c.body}</span> <button class="linkbtn" onclick={() => unhide(c.id)}>Obnovit</button>{/if}
        {#if isAdmin()} · <button class="linkbtn danger" onclick={() => (delFor = delFor === c.id ? null : c.id)}>Smazat</button>{/if}
      </div>
    {:else}
      <p>{c.body}</p>
      <div class="acts">
        {#if open && depth === 0}<button onclick={() => { replyTo = replyTo === c.id ? null : c.id; replyText = ''; }}>Odpovědět</button>{/if}
        {#if isAuthor() && !c.author_is_team}<button class="mod" onclick={() => (modFor = modFor === c.id ? null : c.id)}>Skrýt</button>{/if}
        {#if canDelete(c)}<button class="mod" onclick={() => (delFor = delFor === c.id ? null : c.id)}>Smazat</button>{/if}
      </div>
      {#if modFor === c.id}
        <div class="modbox"><b>Proč komentář skrýváte? Důvod uvidí všichni.</b>
          <div class="row">{#each HIDE_REASONS as r}<button onclick={() => hide(c.id, r)}>{r}</button>{/each}</div></div>
      {/if}
    {/if}
    {#if delFor === c.id}
      <div class="modbox"><b>Smazat komentář natrvalo?{depth === 0 && repliesOf(c.id).length ? ` Smažou se i odpovědi (${repliesOf(c.id).length}).` : ''}</b>
        <div class="row"><button onclick={() => del(c)}>Ano, smazat</button><button class="keep" onclick={() => (delFor = null)}>Ne</button></div></div>
    {/if}
    {#if replyTo === c.id}
      {#if session.user}
        <form class="form" onsubmit={submitReply}>
          <textarea class="field" bind:value={replyText} placeholder="Vaše odpověď…" rows="3" required maxlength="3000"></textarea>
          {#if needName}<input class="field" bind:value={name} placeholder="Vaše jméno (zobrazí se u komentáře)" required minlength="2">{/if}
          <div class="row"><button class="btn" disabled={busy}>Odpovědět</button><button type="button" class="btn ghost" onclick={() => (replyTo = null)}>Zrušit</button></div>
        </form>
      {:else}<p class="meta"><a href={loginHref}>Přihlaste se</a> a odpovězte.</p>{/if}
    {/if}
    {#if depth === 0 && repliesOf(c.id).length}
      <div class="replies">{#each repliesOf(c.id) as r (r.id)}{@render comment(r, 1)}{/each}</div>
    {/if}
  </div>
{/snippet}

<section>
  <h2>Diskuse ({list.length})</h2>
  {#if post.closed_at}
    <div class="closed"><b>Diskuse je uzavřená. Co z ní vzešlo:</b>{post.closing_summary}</div>
  {:else if !post.comments_enabled}
    <p class="meta">U tohoto příspěvku jsou komentáře vypnuté.</p>
  {:else}
    <p class="meta">Mažeme jen urážky, osobní údaje a spam. Kritiku nikdy. <a href="/pravidla/">Pravidla diskuse</a></p>
  {/if}

  {#each roots as c (c.id)}{@render comment(c, 0)}{/each}

  {#if open}
    {#if !session.ready}
    {:else if session.user}
      <form class="form" onsubmit={submit}>
        <label class="meta" for="c-text">Napište svůj názor</label>
        <textarea id="c-text" class="field" bind:value={text} rows="4" required maxlength="3000"></textarea>
        {#if needName}<input class="field" bind:value={name} placeholder="Vaše jméno (zobrazí se u komentáře)" required minlength="2">{/if}
        <div class="row"><button class="btn" disabled={busy || !text.trim()}>Odeslat</button>
          <span class="meta">Píšete jako {session.profile?.display_name || 'nový uživatel'}</span></div>
      </form>
    {:else}
      <div class="login"><b>Chcete se zapojit?</b> <a href={loginHref}>Přihlaste se e-mailem</a>. Bez hesla, stačí klepnout na odkaz, který vám přijde.</div>
    {/if}
  {/if}
</section>

<style>
  h2 { font-size: 20px; margin: 30px 0 6px; }
  .c { padding: 12px 0; border-top: 1px solid var(--line); }
  .who { font-weight: 600; font-size: 14px; display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  p { margin: 4px 0 6px; max-width: 65ch; white-space: pre-line; overflow-wrap: anywhere; }
  .acts { display: flex; gap: 16px; font-size: 13px; }
  .acts button { border: 0; background: none; padding: 0; color: var(--muted); font-weight: 600; }
  .acts .mod { color: var(--bad); }
  .danger { color: var(--bad); }
  .modbox .keep { border-color: var(--line); color: var(--fg); }
  .replies { margin-left: 18px; border-left: 2px solid var(--line); padding-left: 14px; }
  .replies .c:first-child { border-top: 0; }
  .official { background: var(--greensoft); margin: 0 -10px; padding: 12px 10px; border-radius: 8px; border-top-color: transparent; }
  .hidden { font-size: 13.5px; color: var(--muted); font-style: italic; background: var(--soft); border-radius: 6px; padding: 8px 10px; margin: 4px 0; }
  .orig { font-style: normal; }
  .modbox { background: var(--badsoft); border-radius: 8px; padding: 10px; margin: 6px 0; display: flex; flex-direction: column; gap: 8px; font-size: 13.5px; }
  .modbox button { border: 1px solid var(--bad); color: var(--bad); background: none; border-radius: 6px; padding: 5px 10px; font-size: 13px; }
  .form { display: flex; flex-direction: column; gap: 8px; margin-top: 14px; }
  .closed, .login { background: var(--soft); border-radius: 8px; padding: 12px 14px; margin: 12px 0; }
  .closed b { display: block; margin-bottom: 4px; }
</style>
