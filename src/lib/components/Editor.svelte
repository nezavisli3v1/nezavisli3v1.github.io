<script>
  import { onMount, onDestroy } from 'svelte';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { Placeholder } from '@tiptap/extensions';

  // Jednoduchý editor pro laiky: jen to, co článek opravdu potřebuje.
  let { html = $bindable(''), placeholder = 'Začněte psát…' } = $props();
  let el, editor = $state(null), tick = $state(0), linkOpen = $state(false), linkUrl = $state('');

  onMount(() => {
    editor = new Editor({
      element: el,
      content: html,
      extensions: [
        StarterKit.configure({
          heading: { levels: [3] }, code: false, codeBlock: false, strike: false, horizontalRule: false,
          link: { openOnClick: false, autolink: true, defaultProtocol: 'https' }
        }),
        Placeholder.configure({ placeholder })
      ],
      editorProps: { attributes: { class: 'field prose', 'aria-label': 'Text článku', role: 'textbox', 'aria-multiline': 'true' } },
      onUpdate: ({ editor }) => { html = editor.isEmpty ? '' : editor.getHTML(); },
      onTransaction: () => tick++
    });
  });
  onDestroy(() => editor?.destroy());

  const is = (name, attrs) => (tick, editor?.isActive(name, attrs));
  const run = (fn) => fn(editor.chain().focus()).run();

  function openLink() {
    if (editor.state.selection.empty && !is('link')) { linkOpen = 'empty'; return; }
    linkUrl = editor.getAttributes('link').href || ''; linkOpen = true;
  }
  function applyLink(e) {
    e.preventDefault();
    const url = linkUrl.trim();
    if (!url) run((c) => c.extendMarkRange('link').unsetLink());
    else run((c) => c.extendMarkRange('link').setLink({ href: /^https?:\/\//.test(url) ? url : 'https://' + url }));
    linkOpen = false;
  }
</script>

<!-- mousedown nesmí vzít editoru kurzor, jinak by se psaní a Enter po klepnutí na tlačítko ztrácely -->
<div class="tool" role="toolbar" aria-label="Formátování" tabindex="-1" onmousedown={(e) => e.preventDefault()}>
  <button type="button" class:on={is('bold')} onclick={() => run((c) => c.toggleBold())}><b>Tučně</b></button>
  <button type="button" class:on={is('heading', { level: 3 })} onclick={() => run((c) => c.toggleHeading({ level: 3 }))}>Mezititulek</button>
  <button type="button" class:on={is('bulletList')} onclick={() => run((c) => c.toggleBulletList())}>• Odrážky</button>
  <button type="button" class:on={is('blockquote')} onclick={() => run((c) => c.toggleBlockquote())}>Citace</button>
  <button type="button" class:on={is('link')} onclick={openLink}>Odkaz</button>
  <button type="button" onclick={() => run((c) => c.undo())} aria-label="Vrátit zpět">↶ Zpět</button>
</div>
{#if linkOpen === 'empty'}
  <p class="hint">Nejdřív označte slova, ze kterých má být odkaz. <button type="button" class="linkbtn" onclick={() => (linkOpen = false)}>Rozumím</button></p>
{:else if linkOpen}
  <form class="row linkrow" onsubmit={applyLink}>
    <input class="field" bind:value={linkUrl} placeholder="Adresa, např. litvinovice.cz/zapisy" aria-label="Adresa odkazu" style="flex:1;min-width:200px">
    <button class="btn">Vložit</button>
    <button type="button" class="btn ghost" onclick={() => (linkOpen = false)}>Zrušit</button>
  </form>
{/if}
<div bind:this={el}></div>

<style>
  .tool { display: flex; gap: 6px; margin-bottom: 6px; flex-wrap: wrap; }
  .tool button { border: 1px solid var(--line); background: var(--bg); border-radius: 6px; padding: 5px 10px; font-size: 13.5px; }
  .tool button.on { background: var(--navy); color: #fff; border-color: var(--navy); }
  .hint { font-size: 13px; color: var(--warn); margin: 0 0 6px; }
  .linkrow { margin-bottom: 6px; }
  :global(.prose) { min-height: 220px; line-height: 1.65; }
  :global(.prose:focus) { outline: none; border-color: var(--link); }
  :global(.prose p) { margin: 0 0 10px; }
  :global(.prose h3) { font-family: var(--f-display); font-size: 18px; margin: 14px 0 6px; }
  :global(.prose blockquote) { border-left: 3px solid var(--accent); margin: 10px 0; padding-left: 12px; color: var(--muted); }
  :global(.prose p.is-editor-empty:first-child::before) { content: attr(data-placeholder); color: var(--muted); float: left; height: 0; pointer-events: none; }
</style>
