<script>
  import { api } from '$lib/api.js';
  import { date, plural, isScheduled, when } from '$lib/util.js';
  let { post, href = `/clanek/?id=${post.id}` } = $props();
  const cover = $derived(api.coverUrl(post.cover_path));
</script>

<a class="post" class:q={post.kind === 'question'} {href}>
  <span class="tag">{post.kind === 'question' ? 'Diskuse · ' : ''}{post.category}</span>
  {#if cover}<img src={cover} alt="" loading="lazy">{/if}
  <h2>{post.title}</h2>
  {#if post.perex}<p>{post.perex}</p>{/if}
  <span class="foot">
    <span class="meta">{post.author?.display_name} · {post.status === 'draft' ? 'upraveno ' + date(post.updated_at) : isScheduled(post) ? 'vyjde ' + when(post.published_at) : date(post.published_at)}</span>
    {#if post.pinned_at}<span class="badge">📌 Připnuto</span>{/if}
    {#if post.status === 'draft'}<span class="badge warn">koncept</span>{/if}
    {#if isScheduled(post)}<span class="badge blue">naplánováno</span>{/if}
    {#if post.status === 'published' && !isScheduled(post)}<span class="chip">{plural(post.comment_count, 'komentář', 'komentáře', 'komentářů')}</span>{/if}
    {#if post.has_poll}<span class="chip">Anketa</span>{/if}
    {#if post.closed_at}<span class="chip">Uzavřeno</span>{/if}
  </span>
</a>

<style>
  .post { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 16px 18px; display: flex; flex-direction: column; gap: 6px; color: inherit; text-decoration: none; }
  .post:hover { border-color: var(--link); }
  .post.q { border-left: 4px solid var(--accent); }
  h2 { font-size: 19px; }
  p { margin: 0; color: var(--muted); }
  img { width: 100%; max-height: 220px; object-fit: cover; border-radius: 6px; }
  .foot { display: flex; gap: 14px; flex-wrap: wrap; align-items: center; margin-top: 4px; }
  .chip { font-size: 12.5px; font-weight: 600; color: var(--muted); }
</style>
