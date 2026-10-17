<script>
  import { api } from '$lib/api.js';
  import { session, isAuthor, toast } from '$lib/state.svelte.js';
  import { STATUS, date } from '$lib/util.js';

  let chapters = $state(null), openId = $state(null), newStatus = $state(0), note = $state(''), busy = $state(false);
  const load = () => api.listPromises().then((c) => (chapters = c));
  $effect(() => { session.profile; load(); });
  const all = $derived(chapters ? chapters.flatMap((c) => c.promises) : []);
  const counts = $derived(STATUS.map((_, i) => all.filter((p) => p.status === i).length));
  const COLORS = ['var(--line)', 'var(--link)', 'var(--accent)', 'var(--bad)'];

  function toggle(p) { openId = openId === p.id ? null : p.id; newStatus = p.status; note = ''; }
  async function save(e, p) {
    e.preventDefault(); busy = true;
    try { await api.setPromiseStatus(p.id, +newStatus, note); note = ''; await load(); toast('Stav uložen a zapsán do historie.'); }
    catch (err) { toast(err.message); } finally { busy = false; }
  }
</script>

<svelte:head><title>Hlídač slibů · Nezávislí PRO</title></svelte:head>

<div class="section-head"><div><h1>Hlídač slibů</h1>
  <p class="lede">Každý bod našeho programu a jak s ním jsme. U každé změny píšeme, co se stalo a proč. Klepnutím na bod zobrazíte historii.</p></div></div>

{#if !chapters}<p class="empty">Načítám…</p>
{:else}
  <div class="summary">{#each STATUS as s, i}<div class="sum"><b>{counts[i]}</b><span>{s}</span></div>{/each}</div>
  <div class="progress" role="img" aria-label={STATUS.map((s, i) => `${s}: ${counts[i]}`).join(', ')}>
    {#each counts as n, i}<i style:width={(n / all.length) * 100 + '%'} style:background={COLORS[i]}></i>{/each}
  </div>

  {#each chapters as ch, ci (ch.id)}
    <section class="chapter">
      <h2>{ci + 1}. {ch.title} <em>{ch.promises.filter((p) => p.status === 2).length} z {ch.promises.length} splněno</em></h2>
      {#each ch.promises as p (p.id)}
        <div class="promise">
          <button class="head" onclick={() => toggle(p)} aria-expanded={openId === p.id}>
            <span class="txt">{p.text}</span><span class="st st-{p.status}">{STATUS[p.status]}</span>
          </button>
          {#if openId === p.id}
            <div class="detail">
              {#if p.log.length}
                <ol class="log">{#each p.log as l (l.id)}<li><b>{date(l.created_at)} · {STATUS[l.status]}</b> {l.note} <span class="meta">({l.author?.display_name})</span></li>{/each}</ol>
              {:else}<span class="meta">Zatím žádný záznam.</span>{/if}
              {#if isAuthor()}
                <form class="row" onsubmit={(e) => save(e, p)}>
                  <select class="field" style="width:auto" bind:value={newStatus} aria-label="Nový stav">
                    {#each STATUS as s, i}<option value={i}>{s}</option>{/each}
                  </select>
                  <input class="field" style="flex:1;min-width:180px" bind:value={note} placeholder="Co se stalo? (povinné)" required minlength="5" aria-label="Poznámka ke změně">
                  <button class="btn" disabled={busy}>Uložit</button>
                </form>
              {/if}
            </div>
          {/if}
        </div>
      {/each}
    </section>
  {/each}
{/if}

<style>
  .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin: 6px 0 14px; }
  .sum { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 10px; display: flex; flex-direction: column; }
  .sum b { font-family: var(--f-display); font-size: 24px; font-variant-numeric: tabular-nums; }
  .sum span { font-size: 12px; color: var(--muted); }
  .progress { display: flex; height: 8px; border-radius: 4px; overflow: hidden; background: var(--soft); margin-bottom: 24px; }
  .chapter { margin-bottom: 24px; }
  h2 { font-size: 17px; margin-bottom: 6px; }
  h2 em { font-style: normal; color: var(--muted); font-family: var(--f-body); font-size: 13px; font-weight: 500; margin-left: 6px; }
  .promise { border-top: 1px solid var(--line); }
  .head { width: 100%; border: 0; background: none; text-align: left; padding: 11px 0; display: grid; grid-template-columns: 1fr auto; gap: 12px; align-items: start; }
  .txt { min-width: 0; }
  .st { font-size: 11.5px; font-weight: 600; padding: 3px 8px; border-radius: 999px; white-space: nowrap; }
  .st-0 { background: var(--soft); color: var(--muted); } .st-1 { background: var(--bluesoft); color: var(--link); }
  .st-2 { background: var(--greensoft); color: var(--accent); } .st-3 { background: var(--badsoft); color: var(--bad); }
  .detail { padding: 0 0 14px; font-size: 14px; display: flex; flex-direction: column; gap: 10px; }
  .log { list-style: none; margin: 0; padding: 0 0 0 12px; border-left: 2px solid var(--line); display: flex; flex-direction: column; gap: 6px; }
  @media (max-width: 520px) { .summary { grid-template-columns: repeat(2, 1fr); } }
</style>
