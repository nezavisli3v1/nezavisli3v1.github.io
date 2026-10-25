<script>
  import { api } from '$lib/api.js';
  import { session, toast } from '$lib/state.svelte.js';
  let { poll, closed = false } = $props();

  let res = $state(null);
  const load = () => api.pollResults(poll.id).then((r) => (res = r));
  $effect(() => { session.user; load(); });
  const total = $derived(res ? Object.values(res.votes).reduce((a, b) => a + b, 0) : 0);
  const shown = $derived(res && (res.mine !== null || closed));

  async function vote(id) {
    if (closed) return;
    try { await api.vote(id); await load(); } catch (e) { toast(e.message); }
  }
</script>

<div class="poll">
  <h3>{poll.question}</h3>
  {#each poll.options as o (o.id)}
    {@const pct = total ? Math.round(((res?.votes[o.id] || 0) / total) * 100) : 0}
    <button class="opt" class:mine={res?.mine === o.id} onclick={() => vote(o.id)} disabled={closed} aria-pressed={res?.mine === o.id}>
      <span class="bar" style:width={shown ? pct + '%' : '0'}></span>
      <span class="lbl">{o.label}</span>
      {#if shown}<b>{pct} %</b>{/if}
    </button>
  {/each}
  <span class="meta">
    {#if closed}Anketa je uzavřená · {total} hlasů
    {:else if res?.mine === null}Klepnutím hlasujte. Výsledky uvidíte po hlasování.
    {:else}{total} hlasů · svůj hlas můžete změnit{/if}
  </span>
</div>

<style>
  .poll { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; margin: 18px 0; display: flex; flex-direction: column; gap: 8px; }
  h3 { font-size: 16px; margin-bottom: 2px; }
  .opt { position: relative; border: 1px solid var(--line); border-radius: 6px; padding: 10px 12px; background: none; text-align: left; overflow: hidden; display: flex; justify-content: space-between; gap: 10px; }
  .opt:disabled { cursor: default; }
  .bar { position: absolute; inset: 0 auto 0 0; background: var(--greensoft); transition: width .4s; }
  .lbl, b { position: relative; }
  b { font-variant-numeric: tabular-nums; }
  .mine { border-color: var(--accent); font-weight: 600; }
</style>
