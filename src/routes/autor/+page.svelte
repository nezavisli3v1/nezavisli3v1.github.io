<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor } from '$lib/state.svelte.js';
  import PostCard from '$lib/components/PostCard.svelte';
  import { isScheduled } from '$lib/util.js';

  let posts = $state(null);
  $effect(() => { session.profile; if (isAuthor()) api.listPosts({ drafts: true }).then((p) => (posts = p)); });
  const drafts = $derived(posts?.filter((p) => p.status === 'draft') ?? []);
  const planned = $derived(posts?.filter(isScheduled).sort((a, b) => a.published_at.localeCompare(b.published_at)) ?? []);
  const published = $derived(posts?.filter((p) => p.status === 'published' && !isScheduled(p)) ?? []);
</script>

<svelte:head><title>Psaní · Nezávislí PRO</title></svelte:head>

{#if !session.ready}<p class="empty">Načítám…</p>
{:else if !isAuthor()}<p class="empty">Tahle část je jen pro autory.</p>
{:else}
  <div class="section-head"><div><h1>Psaní</h1><p class="lede">Rozepsané koncepty, naplánované a zveřejněné příspěvky. Klepnutím otevřete úpravu.</p></div>
    <div class="row"><a class="btn" href="/autor/psat/?druh=article">Napsat článek</a><a class="btn ghost" href="/autor/psat/?druh=question">Položit otázku</a></div></div>

  <h2>Koncepty ({drafts.length})</h2>
  {#if !posts}<p class="empty">Načítám…</p>
  {:else if !drafts.length}<p class="meta">Žádné rozepsané koncepty.</p>
  {:else}<div class="feed">{#each drafts as p (p.id)}<PostCard post={p} href={`/autor/psat/?id=${p.id}`} />{/each}</div>{/if}

  {#if planned.length}
    <h2>Naplánované ({planned.length})</h2>
    <div class="feed">{#each planned as p (p.id)}<PostCard post={p} href={`/autor/psat/?id=${p.id}`} />{/each}</div>
  {/if}

  <h2>Zveřejněné ({published.length})</h2>
  <div class="feed">{#each published as p (p.id)}<PostCard post={p} href={`/autor/psat/?id=${p.id}`} />{/each}</div>
{/if}

<style>
  h2 { font-size: 18px; margin: 22px 0 10px; }
  .feed { display: flex; flex-direction: column; gap: 12px; }
</style>
