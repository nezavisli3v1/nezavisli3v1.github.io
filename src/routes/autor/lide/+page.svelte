<script>
  import { api } from '$lib/api.js';
  import { session, isAdmin, toast } from '$lib/state.svelte.js';

  let people = $state(null), q = $state('');
  const load = () => api.listProfiles().then((p) => (people = p)).catch((e) => toast(e.message));
  $effect(() => { session.profile; if (isAdmin()) load(); });
  const shown = $derived((people || []).filter((p) => !q || `${p.display_name} ${p.email}`.toLowerCase().includes(q.toLowerCase()))
    .sort((a, b) => (a.role === 'reader') - (b.role === 'reader')));
  const admins = $derived((people || []).filter((p) => p.role === 'admin').length);

  async function set(p, patch) {
    if (p.role === 'admin' && patch.role && patch.role !== 'admin' && admins <= 1) { toast('Musí zůstat aspoň jeden správce.'); return; }
    try { await api.updateProfile(p.id, patch); await load(); toast('Uloženo.'); } catch (e) { toast(e.message); }
  }
</script>

<svelte:head><title>Lidé · Nezávislí PRO</title></svelte:head>

{#if !session.ready}<p class="empty">Načítám…</p>
{:else if !isAdmin()}<p class="empty">Tahle část je jen pro správce.</p>
{:else}
  <div class="section-head"><div><h1>Lidé</h1>
    <p class="lede">Nového autora přidáte tak, že se nejdřív sám jednou přihlásí e-mailem. Pak ho tady najdete a nastavíte mu roli.</p></div></div>
  <input class="field" bind:value={q} placeholder="Hledat jméno nebo e-mail" aria-label="Hledat" style="margin-bottom:14px">
  {#if !people}<p class="empty">Načítám…</p>{:else}
  <div class="list">
    {#each shown as p (p.id)}
      <div class="person">
        <div class="id"><b>{p.display_name || '(bez jména)'}</b><span class="meta">{p.email}</span></div>
        <div class="row">
          <select class="field" value={p.role} onchange={(e) => set(p, { role: e.target.value })} aria-label={`Role ${p.display_name}`}>
            <option value="reader">čtenář</option><option value="author">autor</option><option value="admin">správce</option>
          </select>
          <input class="field badgein" value={p.badge || ''} placeholder="štítek" aria-label="Štítek u jména" maxlength="30"
            onchange={(e) => set(p, { badge: e.target.value.trim() || null })}>
        </div>
      </div>
    {/each}
  </div>
  {/if}
  <p class="meta">Autor může psát, moderovat a měnit stavy slibů. Správce navíc přiděluje role a maže příspěvky. Štítek se zobrazuje u jména v diskusi.</p>
{/if}

<style>
  .list { display: flex; flex-direction: column; margin-bottom: 16px; }
  .person { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; padding: 10px 0; border-top: 1px solid var(--line); align-items: center; }
  .id { display: flex; flex-direction: column; min-width: 0; overflow-wrap: anywhere; }
  .person select { width: auto; }
  .badgein { width: 190px; }
</style>
