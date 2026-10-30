<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor, refreshProfile, toast } from '$lib/state.svelte.js';
  import PostCard from './PostCard.svelte';
  let { kind = null, title, lede, newLabel } = $props();

  let posts = $state(null), error = $state('');
  // nabídka odběru: přihlášený bez odběru → zapnout jedním klepnutím, nepřihlášený → přihlásit
  const field = $derived(kind === 'question' ? 'notify_discussions' : 'notify_articles');
  const showCta = $derived(session.ready && (!session.user || (session.profile && field in session.profile && !session.profile[field])));
  async function subscribe() {
    const p = session.profile;
    try {
      await api.setMyNotifications(kind === 'question' ? !!p.notify_articles : true, kind === 'question' ? true : !!p.notify_discussions);
      await refreshProfile(); toast('Odběr zapnut. Nové příspěvky vám přijdou e-mailem. Změnit to můžete v Můj účet.');
    } catch (e) { toast(e.message); }
  }
  $effect(() => {
    session.profile; // znovu načíst po přihlášení / změně role
    api.listPosts({ kind }).then((p) => (posts = p)).catch((e) => (error = e.message));
  });
</script>

<div class="section-head">
  <div><h1>{title}</h1><p class="lede">{lede}</p></div>
  {#if isAuthor()}<div class="row">
    {#if kind === 'article'}<a class="btn ghost" href="/autor/psat/?druh=picture">Vložit obrázek</a>{/if}
    <a class="btn" href={`/autor/psat/?druh=${kind || 'article'}`}>{newLabel}</a>
  </div>{/if}
</div>

{#if showCta}
  <div class="cta">
    <span>{kind === 'question' ? 'Chcete vědět o nových diskusích?' : 'Chcete dostávat nové články e-mailem?'}</span>
    {#if session.user}<button class="btn ghost" onclick={subscribe}>Odebírat e-mailem</button>
    {:else}<a class="btn ghost" href={`/prihlaseni/?next=${encodeURIComponent('/ucet/')}`}>Přihlásit a odebírat</a>{/if}
  </div>
{/if}

{#if error}<p class="error">{error}</p>
{:else if !posts}<p class="empty">Načítám…</p>
{:else if !posts.length}<p class="empty">Zatím tu nic není.</p>
{:else}<div class="feed">{#each posts as p (p.id)}<PostCard post={p} />{/each}</div>{/if}

<style>
  .feed { display: flex; flex-direction: column; gap: 12px; }
  .cta { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; background: var(--bluesoft); border-radius: 10px; padding: 10px 14px; margin-bottom: 14px; font-size: 14.5px; font-weight: 600; }
  .cta .btn { padding: 7px 12px; font-size: 14px; background: var(--surface); }
</style>
