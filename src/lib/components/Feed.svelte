<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor } from '$lib/state.svelte.js';
  import PostCard from './PostCard.svelte';
  let { kind = null, title, lede, newLabel } = $props();

  let posts = $state(null), error = $state('');
  $effect(() => {
    session.profile; // znovu načíst po přihlášení / změně role
    api.listPosts({ kind }).then((p) => (posts = p)).catch((e) => (error = e.message));
  });
</script>

<div class="section-head">
  <div><h1>{title}</h1><p class="lede">{lede}</p></div>
  {#if isAuthor()}<a class="btn" href={`/autor/psat/?druh=${kind || 'article'}`}>{newLabel}</a>{/if}
</div>

{#if error}<p class="error">{error}</p>
{:else if !posts}<p class="empty">Načítám…</p>
{:else if !posts.length}<p class="empty">Zatím tu nic není.</p>
{:else}<div class="feed">{#each posts as p (p.id)}<PostCard post={p} />{/each}</div>{/if}

<style>.feed { display: flex; flex-direction: column; gap: 12px; }</style>
