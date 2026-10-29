<script>
  import { goto } from '$app/navigation';
  import { api } from '$lib/api.js';
  import { session, refreshProfile, toast } from '$lib/state.svelte.js';

  let name = $state(''), confirmDelete = $state(false);
  $effect(() => { name = session.profile?.display_name || ''; });
  $effect(() => { if (session.ready && !session.user) goto('/prihlaseni/?next=/ucet/', { replaceState: true }); });
  const ROLE = { reader: 'čtenář', author: 'autor', admin: 'správce' };

  async function save(e) { e.preventDefault(); try { await api.setMyName(name); await refreshProfile(); toast('Jméno uloženo.'); } catch (err) { toast(err.message); } }
  const hasNotify = $derived(session.profile && 'notify_articles' in session.profile);
  async function setNotify(field, value) {
    const a = field === 'a' ? value : !!session.profile.notify_articles, d = field === 'd' ? value : !!session.profile.notify_discussions;
    try { await api.setMyNotifications(a, d); await refreshProfile(); toast(value ? 'Odběr zapnut. Nové příspěvky vám přijdou e-mailem.' : 'Odběr vypnut.'); }
    catch (err) { toast(err.message); }
  }
  async function out() { await api.signOut(); goto('/'); }
  async function del() { try { await api.deleteMyAccount(); toast('Účet i vaše komentáře jsou smazané.'); goto('/'); } catch (err) { toast(err.message); } }
</script>

<svelte:head><title>Můj účet · Nezávislí PRO</title></svelte:head>

{#if session.profile}
<div class="narrow">
  <h1>Můj účet</h1>
  <p class="meta">{session.profile.email} · {ROLE[session.profile.role]}</p>
  <form class="box" onsubmit={save}>
    <label for="nm"><b>Jméno u komentářů</b></label>
    <input id="nm" class="field" bind:value={name} required minlength="2" maxlength="60">
    <button class="btn">Uložit</button>
  </form>
  {#if hasNotify}
    <div class="box">
      <b>Odběr e-mailem</b>
      <p class="meta">Pošleme vám e-mail, když na webu vyjde něco nového. Odhlásit se můžete tady nebo odkazem v každém e-mailu.</p>
      <label class="check"><input type="checkbox" checked={session.profile.notify_articles} onchange={(e) => setNotify('a', e.target.checked)}><span>Nové články v Aktualitách</span></label>
      <label class="check"><input type="checkbox" checked={session.profile.notify_discussions} onchange={(e) => setNotify('d', e.target.checked)}><span>Nové otázky v Diskusi</span></label>
      <p class="meta">E-maily chodí na {session.profile.email}.</p>
    </div>
  {/if}
  <button class="btn ghost" onclick={out}>Odhlásit se</button>
  {#if session.profile.role === 'reader'}
    <div class="box">
      <b>Smazat účet</b>
      <p class="meta">Smaže se účet, vaše komentáře i hlasy v anketách. Nejde to vrátit.</p>
      {#if confirmDelete}
        <div class="row"><button class="btn danger" onclick={del}>Ano, smazat natrvalo</button><button class="btn ghost" onclick={() => (confirmDelete = false)}>Ne</button></div>
      {:else}<button class="btn danger" onclick={() => (confirmDelete = true)}>Smazat účet…</button>{/if}
    </div>
  {/if}
</div>
{/if}

<style>
  .narrow { max-width: 440px; margin: 20px auto; display: flex; flex-direction: column; gap: 14px; }
  h1 { font-size: 26px; }
  .box { display: flex; flex-direction: column; gap: 8px; align-items: flex-start; }
  .box .field { width: 100%; }
  .box p { margin: 0; }
</style>
