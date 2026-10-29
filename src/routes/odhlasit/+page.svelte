<script>
  import { page } from '$app/state';
  import { api } from '$lib/api.js';

  const KIND = { articles: 'nových článků', discussions: 'nových diskusí', all: 'novinek' };
  const token = $derived(page.url.searchParams.get('t'));
  const kind = $derived(KIND[page.url.searchParams.get('k')] ? page.url.searchParams.get('k') : 'all');
  let state = $state('pending'), msg = $state('');

  $effect(() => {
    if (!/^[0-9a-f-]{36}$/i.test(token || '')) { state = 'bad'; return; }
    api.unsubscribe(token, kind).then((who) => (state = who === '' ? 'bad' : 'ok')).catch((e) => { state = 'err'; msg = e.message; });
  });
</script>

<svelte:head><title>Odhlášení odběru · Nezávislí PRO</title></svelte:head>

<div class="narrow">
  {#if state === 'pending'}<p class="empty">Odhlašuji…</p>
  {:else if state === 'ok'}
    <h1>Odběr je zrušený</h1>
    <p class="lede">E-maily o {KIND[kind]} vám už chodit nebudou. Kdybyste si to rozmysleli, odběr znovu zapnete v sekci <a href="/ucet/">Můj účet</a>.</p>
  {:else if state === 'bad'}
    <h1>Odkaz nefunguje</h1>
    <p class="lede">Odkaz pro odhlášení je neplatný nebo neúplný. Odběr můžete vypnout po přihlášení v sekci <a href="/ucet/">Můj účet</a>.</p>
  {:else}
    <h1>Něco se nepovedlo</h1>
    <p class="lede">{msg} Zkuste to prosím znovu, nebo odběr vypněte v sekci <a href="/ucet/">Můj účet</a>.</p>
  {/if}
  <p><a class="btn ghost" href="/">Na úvodní stránku</a></p>
</div>

<style>
  .narrow { max-width: 480px; margin: 30px auto; display: flex; flex-direction: column; gap: 12px; }
  h1 { font-size: 26px; }
</style>
