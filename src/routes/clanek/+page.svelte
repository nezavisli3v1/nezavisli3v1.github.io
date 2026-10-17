<script>
  import { page } from '$app/state';
  import { api } from '$lib/api.js';
  import { session, isAuthor, isAdmin, toast } from '$lib/state.svelte.js';
  import { date, clean, fileSize } from '$lib/util.js';
  import Poll from '$lib/components/Poll.svelte';
  import Comments from '$lib/components/Comments.svelte';

  const id = $derived(+page.url.searchParams.get('id'));
  let post = $state(undefined), closing = $state(false), summary = $state('');
  const load = () => api.getPost(id).then((p) => (post = p));
  $effect(() => { session.profile; id; load(); });
  const cover = $derived(post && api.coverUrl(post.cover_path));

  async function close(e) {
    e.preventDefault();
    try { await api.closeDiscussion(post.id, summary); closing = false; await load(); toast('Diskuse je uzavřená a shrnutí zveřejněné.'); }
    catch (err) { toast(err.message); }
  }
  async function copyLink() {
    try { await navigator.clipboard.writeText(location.href); toast('Odkaz zkopírován. Vložte ho na Facebook nebo do zprávy.'); }
    catch { toast(location.href); }
  }
</script>

<svelte:head><title>{post?.title || 'Článek'} · Nezávislí PRO</title></svelte:head>

{#if post === undefined}<p class="empty">Načítám…</p>
{:else if post === null}<p class="empty">Tenhle příspěvek neexistuje nebo ještě není zveřejněný. <a href="/">Zpět na aktuality</a></p>
{:else}
  <a class="linkbtn" href={post.kind === 'question' ? '/diskuse/' : '/'}>← Zpět</a>
  <article>
    <span class="tag">{post.kind === 'question' ? 'Diskuse · ' : ''}{post.category}</span>
    <h1>{post.title}</h1>
    <div class="meta">{post.author?.display_name}
      {#if post.author?.badge}<span class="badge">{post.author.badge}</span>{/if}
      · {post.status === 'draft' ? 'koncept, vidí jen autoři' : date(post.published_at)}</div>
    {#if cover}<img src={cover} alt="">{/if}
    {#if post.perex}<p class="perex">{post.perex}</p>{/if}
    <div class="body">{@html clean(post.body_html)}</div>
    {#if post.attachments?.length}
      <section class="atts" aria-label="Přílohy">
        <h2>Přílohy</h2>
        {#each post.attachments as a (a.id)}
          <a class="att" href={api.attachmentUrl(a.path)} target="_blank" rel="noopener">
            <span class="pdf" aria-hidden="true">PDF</span>
            <span class="nm">{a.name}</span>
            <span class="meta">{fileSize(a.size_bytes)}</span>
          </a>
        {/each}
      </section>
    {/if}
    {#if post.poll}<Poll poll={post.poll} closed={!!post.closed_at} />{/if}
  </article>

  <div class="row tools">
    <button class="btn ghost" onclick={copyLink}>Zkopírovat odkaz</button>
    {#if isAuthor()}
      <a class="btn ghost" href={`/autor/psat/?id=${post.id}`}>Upravit</a>
      {#if post.status === 'published' && !post.closed_at && post.comments_enabled}
        <button class="btn ghost" onclick={() => (closing = !closing)}>Uzavřít diskusi</button>
      {/if}
    {/if}
  </div>
  {#if closing}
    <form class="box closeform" onsubmit={close}>
      <label for="sum"><b>Co z diskuse vzešlo a co s tím uděláte?</b></label>
      <p class="meta">Shrnutí se zobrazí nad komentáři. Lidé tak uvidí, že zapojit se má smysl.</p>
      <textarea id="sum" class="field" rows="4" bind:value={summary} required minlength="10"></textarea>
      <div class="row"><button class="btn">Uzavřít a zveřejnit shrnutí</button></div>
    </form>
  {/if}

  {#if post.status === 'published'}<Comments {post} />{/if}
{/if}

<style>
  article { margin-top: 14px; }
  h1 { font-size: 28px; margin: 6px 0 8px; }
  img { width: 100%; border-radius: 8px; margin: 12px 0 0; }
  .perex { font-size: 18px; font-weight: 500; margin: 14px 0; }
  .body :global(p) { margin: 0 0 12px; max-width: 65ch; }
  .body :global(h3) { font-size: 19px; margin: 20px 0 8px; }
  .body :global(blockquote) { border-left: 3px solid var(--accent); margin: 12px 0; padding-left: 14px; color: var(--muted); }
  .tools { margin-top: 18px; }
  .atts { margin: 18px 0; display: flex; flex-direction: column; gap: 8px; }
  .atts h2 { font-size: 16px; }
  .att { display: grid; grid-template-columns: auto 1fr auto; gap: 10px; align-items: center; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; color: inherit; text-decoration: none; }
  .att:hover { border-color: var(--link); }
  .nm { font-weight: 600; min-width: 0; overflow-wrap: anywhere; }
  .pdf { font-size: 10.5px; font-weight: 700; color: var(--bad); border: 1.5px solid var(--bad); border-radius: 4px; padding: 2px 4px; }
  .closeform { margin-top: 12px; display: flex; flex-direction: column; gap: 8px; }
  @media (max-width: 520px) { h1 { font-size: 24px; } }
</style>
