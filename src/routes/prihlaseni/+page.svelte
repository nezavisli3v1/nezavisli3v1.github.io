<script>
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { api } from '$lib/api.js';
  import { session, refreshProfile, toast } from '$lib/state.svelte.js';

  const next = $derived(page.url.searchParams.get('next') || '/');
  let email = $state(''), sent = $state(false), busy = $state(false), name = $state(''), error = $state('');

  // po přihlášení: chybí-li jméno, zeptat se; jinak pokračovat, odkud uživatel přišel
  $effect(() => { if (session.user && session.profile?.display_name) goto(next, { replaceState: true }); });

  async function send(e) {
    e.preventDefault(); busy = true; error = '';
    try { await api.signIn(email.trim(), next); sent = !api.demo; }
    catch (err) { error = err.message; } finally { busy = false; }
  }
  async function saveName(e) {
    e.preventDefault();
    try { await api.setMyName(name); await refreshProfile(); toast('Vítejte!'); } catch (err) { error = err.message; }
  }
</script>

<svelte:head><title>Přihlášení · Nezávislí PRO</title></svelte:head>

<div class="narrow">
  {#if session.user && !session.profile?.display_name}
    <h1>Jak se jmenujete?</h1>
    <p class="lede">Jméno se zobrazí u vašich komentářů. Stačí třeba „Jan D.“</p>
    <form onsubmit={saveName}>
      <input class="field" bind:value={name} required minlength="2" maxlength="60" autocomplete="name" aria-label="Jméno">
      <button class="btn">Pokračovat</button>
      {#if error}<p class="error">{error}</p>{/if}
    </form>
  {:else if sent}
    <h1>Zkontrolujte e-mail</h1>
    <p class="lede">Na adresu <b>{email}</b> jsme poslali odkaz. Klepněte na něj a jste přihlášeni. Odkaz platí hodinu.</p>
    <p class="meta">Nepřišel? Podívejte se do složky Hromadné nebo Spam, případně <button class="linkbtn" onclick={() => (sent = false)}>zkuste to znovu</button>.</p>
  {:else}
    <h1>Přihlášení</h1>
    <p class="lede">Bez hesla. Zadejte e-mail a pošleme vám odkaz, kterým se přihlásíte. Poprvé tím zároveň vznikne účet.</p>
    <form onsubmit={send}>
      <input class="field" type="email" bind:value={email} required autocomplete="email" placeholder="vas@email.cz" aria-label="E-mail">
      <button class="btn" disabled={busy}>{busy ? 'Posílám…' : 'Poslat odkaz'}</button>
      {#if error}<p class="error">{error}</p>{/if}
    </form>
    <p class="meta">E-mail nikde nezveřejníme. Používáme ho jen k přihlášení. <a href="/pravidla/">Ochrana údajů</a></p>
  {/if}
</div>

<style>
  .narrow { max-width: 440px; margin: 20px auto; display: flex; flex-direction: column; gap: 12px; }
  h1 { font-size: 26px; }
  form { display: flex; flex-direction: column; gap: 10px; }
</style>
