// Ukázkový režim: běží bez databáze, s vymyšleným obsahem v paměti prohlížeče.
// Spouští se automaticky, když chybí PUBLIC_SUPABASE_URL. Hodí se k ukázce kolegům a k vývoji.
import { DEMO_CHAPTERS } from './demo-program.js';
import { pinnedFirst } from './util.js';

const wait = (v) => new Promise((r) => setTimeout(() => r(structuredClone(v)), 120));
const now = () => new Date().toISOString();
const daysAgo = (d) => new Date(Date.now() - d * 864e5).toISOString();

export function createDemoApi() {
  let seq = 1000;
  const people = {
    jan: { id: 'jan', display_name: 'Jan Dolejší', role: 'admin', badge: null, email: 'jan@example.cz' },
    martin: { id: 'martin', display_name: 'Martin Maleček', role: 'author', badge: null, email: 'martin@example.cz' },
    marie: { id: 'marie', display_name: 'Marie Šímová', role: 'author', badge: null, email: 'marie@example.cz' },
    petra: { id: 'petra', display_name: 'Petra K.', role: 'reader', badge: null, email: 'petra@example.cz' },
    tomas: { id: 'tomas', display_name: 'Tomáš V.', role: 'reader', badge: null, email: 'tomas@example.cz' },
    host: { id: 'host', display_name: 'Host ukázky', role: 'reader', badge: null, email: 'host@example.cz' }
  };
  const pub = (id) => { const p = people[id]; return p && { id: p.id, display_name: p.display_name, is_team: p.role !== 'reader', badge: p.badge }; };

  const posts = [
    { id: 1, kind: 'article', category: 'Zastupitelstvo', author_id: 'martin', status: 'published', published_at: daysAgo(1),
      title: 'Ukázka: Co se rozhodlo na zastupitelstvu',
      perex: 'Krátké shrnutí každého zasedání: o čem se hlasovalo, jak to dopadlo a jak hlasovali naši zastupitelé.',
      body_html: '<p>Takhle bude vypadat pravidelná zpráva po zasedání. Tři až pět bodů, u každého jedna věta o tom, co se rozhodlo, a jedna o tom, proč jsme hlasovali tak, jak jsme hlasovali.</p><h3>Bod 1: rozpočtové opatření</h3><p>Ukázkový text.</p><h3>Bod 2: veřejná zakázka</h3><p>Ukázkový text. Kolik, komu a proč.</p>',
      comments_enabled: true, closed_at: null, closing_summary: null, cover_path: null },
    { id: 2, kind: 'question', category: 'Doprava', author_id: 'jan', status: 'published', published_at: daysAgo(3),
      title: 'Ukázka: Kde se vám v obci nejezdí bezpečně?',
      perex: 'Než začneme měřit, chceme vědět, kde to vnímáte vy. Napište ulici nebo místo a proč.',
      body_html: '<p>Sbíráme místa pro první měření rychlosti a sčítání dopravy. Po měření zveřejníme výsledky.</p>',
      comments_enabled: true, closed_at: null, closing_summary: null, cover_path: null },
    { id: 3, kind: 'question', category: 'Veřejný prostor', author_id: 'marie', status: 'published', published_at: daysAgo(15),
      title: 'Ukázka: Kde chybí lavička nebo stín?', perex: 'Uzavřená diskuse se shrnutím, co z ní vzešlo.',
      body_html: '<p>Diskuse byla otevřená dva týdny.</p>', comments_enabled: true, closed_at: daysAgo(1),
      closing_summary: 'Sešlo se 12 tipů. Tři nejčastější místa jsme předali obci jako podnět a o odpovědi vás budeme informovat.', cover_path: null },
    { id: 4, kind: 'article', category: 'Rozpočet', author_id: 'jan', status: 'draft', published_at: null,
      title: 'Ukázka konceptu: rozpočet na rok 2027', perex: 'Rozpracovaný článek vidí jen autoři.', body_html: '<p>…</p>',
      comments_enabled: true, closed_at: null, closing_summary: null, cover_path: null }
  ];
  posts.forEach((p) => { p.created_at = p.updated_at = p.published_at || now(); });
  const polls = [{ id: 1, post_id: 2, question: 'Co vás trápí nejvíc?', options: [
    { id: 1, label: 'Rychlá jízda', position: 0 }, { id: 2, label: 'Tranzit přes náves', position: 1 },
    { id: 3, label: 'Chybějící chodník', position: 2 }, { id: 4, label: 'Parkování', position: 3 }] }];
  const votes = { 1: 23, 2: 14, 3: 19, 4: 8 }; const myVotes = {};
  const comments = [
    { id: 11, post_id: 1, parent_id: null, author_id: 'petra', body: 'Díky za shrnutí. Bude u zpráv i odkaz na videozáznam?', created_at: daysAgo(0.9) },
    { id: 12, post_id: 1, parent_id: 11, author_id: 'jan', body: 'Ano, jakmile obec záznamy začne zveřejňovat, dáme odkaz ke každému bodu.', created_at: daysAgo(0.8) },
    { id: 13, post_id: 1, parent_id: null, author_id: 'tomas', body: '(urážlivý komentář)', created_at: daysAgo(0.7), hidden_reason: 'urážka' },
    { id: 21, post_id: 2, parent_id: null, author_id: 'tomas', body: 'Průtah Šindlovými Dvory ráno kolem sedmé, auta tam jedou přes šedesát.', created_at: daysAgo(2) },
    { id: 22, post_id: 2, parent_id: null, author_id: 'petra', body: 'Cesta do školy od zastávky. Chybí přechod.', created_at: daysAgo(1.5) },
    { id: 31, post_id: 3, parent_id: null, author_id: 'petra', body: 'U rybníka v Litvínovicích, cestou na procházku.', created_at: daysAgo(10) }
  ];
  const chapters = structuredClone(DEMO_CHAPTERS);
  const covers = {}; const files = {};
  // ukázkový výkres: jednoduchá „mapa“ jako SVG
  const demoImg = (path) => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 840"><rect width="1200" height="840" fill="#F3EFE2"/>` +
    `<path d="M0 520 C200 470 380 600 600 540 S1000 420 1200 470 V840 H0Z" fill="#CFE3C4"/>` +
    `<path d="M140 120h300v200H140z" fill="#E9A8A0"/><path d="M520 160h260v180H520z" fill="#F2C987"/><path d="M820 90h240v260H820z" fill="#E9A8A0"/>` +
    `<path d="M0 400 H1200" stroke="#888" stroke-width="14"/><path d="M660 0 V840" stroke="#888" stroke-width="10"/>` +
    `<ellipse cx="300" cy="650" rx="170" ry="80" fill="#9CC7E6"/>` +
    `<text x="40" y="800" font-family="Arial" font-size="38" fill="#444">${path === 'demo-up2' ? 'Ukázka: koordinační výkres' : 'Ukázka: hlavní výkres'}</text></svg>`);
  const sections = [
    { id: 501, page: 'uzemni-plan', position: 0, title: 'Ukázka: Platný územní plán', updated_at: daysAgo(2),
      body_html: '<p>Ukázkový oddíl. Tady bude krátce, co územní plán obsahuje, kdy nabyl účinnosti a kde je oficiální verze na webu obce.</p>',
      files: [
        { id: 601, kind: 'image', path: 'demo-up1', thumb_path: 'demo-up1', name: 'Hlavní výkres', size_bytes: 2400000, width: 1200, height: 840, position: 0 },
        { id: 602, kind: 'image', path: 'demo-up2', thumb_path: 'demo-up2', name: 'Koordinační výkres', size_bytes: 2100000, width: 1200, height: 840, position: 1 },
        { id: 603, kind: 'pdf', path: 'demo-pdf', name: 'Textová část územního plánu', size_bytes: 1830000, position: 2 }] },
    { id: 502, page: 'uzemni-plan', position: 1, title: 'Ukázka: Změna č. 1 (v přípravě)', updated_at: daysAgo(1),
      body_html: '<p>Co se mění, proč a do kdy lze podat připomínky.</p>', files: [] }
  ];
  const attachments = [{ id: 1, post_id: 1, path: 'demo-zapis', name: 'Ukázka: zápis ze zasedání zastupitelstva', size_bytes: 482000, position: 0 }];

  // přepínač „kdo jsem“ jen pro ukázku
  let current = null; const listeners = [];
  const emit = () => listeners.forEach((cb) => cb(current ? { id: current, email: people[current].email } : null));
  const me = () => (current ? people[current] : null);
  const isAuthor = () => ['author', 'admin'].includes(me()?.role);
  const need = (cond, msg) => { if (!cond) throw new Error(msg); };

  return {
    demo: true,
    demoUsers: [{ id: null, label: 'Nepřihlášený' }, { id: 'host', label: 'Čtenář' }, { id: 'martin', label: 'Autor' }, { id: 'jan', label: 'Správce' }],
    demoAs(id) { current = id; emit(); },

    onAuth(cb) { listeners.push(cb); setTimeout(() => cb(current ? { id: current } : null)); },
    async signIn() { current = 'host'; emit(); },
    async signOut() { current = null; emit(); },
    async me() { return wait(me()); },
    async setMyName(name) { need(me(), 'Nejste přihlášeni.'); me().display_name = name.trim(); emit(); },
    async deleteMyAccount() { need(!isAuthor(), 'Účet autora může smazat jen správce.'); current = null; emit(); },

    async listPosts({ kind, drafts = false } = {}) {
      const live = (p) => p.status === 'published' && p.published_at && p.published_at <= now();
      const list = posts.filter((p) => (!kind || p.kind === kind) && (live(p) || (drafts && isAuthor())))
        .sort((a, b) => (b.published_at || '9').localeCompare(a.published_at || '9'));
      return wait(pinnedFirst(list).map((p) => ({ ...p, author: pub(p.author_id), comment_count: comments.filter((c) => c.post_id === p.id).length, has_poll: polls.some((x) => x.post_id === p.id) })));
    },
    async getPost(id) {
      const p = posts.find((x) => x.id === +id && ((x.status === 'published' && x.published_at <= now()) || isAuthor()));
      if (!p) return wait(null);
      const poll = polls.find((x) => x.post_id === p.id);
      return wait({ ...p, author: pub(p.author_id), attachments: attachments.filter((a) => a.post_id === p.id).sort((a, b) => a.position - b.position), poll: poll && { id: poll.id, question: poll.question, options: poll.options } });
    },
    async pollResults(pollId) {
      const poll = polls.find((x) => x.id === pollId);
      return wait({ votes: Object.fromEntries(poll.options.map((o) => [o.id, votes[o.id] || 0])), mine: myVotes[`${current || 'anon'}:${pollId}`] ?? null });
    },
    async vote(optionId) {
      const poll = polls.find((x) => x.options.some((o) => o.id === optionId));
      const key = `${current || 'anon'}:${poll.id}`;
      if (myVotes[key]) votes[myVotes[key]]--;
      myVotes[key] = optionId; votes[optionId] = (votes[optionId] || 0) + 1;
    },
    async savePost(d) {
      need(isAuthor(), 'K této akci nemáte oprávnění.');
      let p = posts.find((x) => x.id === d.id);
      if (!p) { p = { id: ++seq, author_id: current, created_at: now(), closed_at: null, closing_summary: null }; posts.push(p); }
      Object.assign(p, { kind: d.kind, title: d.title.trim(), perex: d.perex.trim(), body_html: d.body_html, category: d.category,
        cover_path: d.cover_path || null, status: d.status, comments_enabled: d.comments_enabled, updated_at: now() });
      if (d.publish_at !== undefined) p.published_at = d.publish_at;
      if (p.status === 'draft') p.published_at = null;
      if (p.status === 'published' && !p.published_at) p.published_at = now();
      if (d.attachments) {
        for (let i = attachments.length - 1; i >= 0; i--) if (attachments[i].post_id === p.id) attachments.splice(i, 1);
        d.attachments.forEach((a, i) => attachments.push({ id: a.id || ++seq, post_id: p.id, path: a.path, name: a.name.trim() || 'Příloha', size_bytes: a.size_bytes, position: i }));
      }
      if (d.pollEditable) {
        const i = polls.findIndex((x) => x.post_id === p.id); if (i >= 0) polls.splice(i, 1);
        const opts = (d.poll?.options || []).map((o) => o.trim()).filter(Boolean);
        if (d.poll?.question?.trim() && opts.length >= 2) polls.push({ id: ++seq, post_id: p.id, question: d.poll.question.trim(), options: opts.map((label, position) => ({ id: ++seq, label, position })) });
      }
      return p.id;
    },
    async deletePost(id) { need(me()?.role === 'admin', 'Mazat může jen správce.'); posts.splice(posts.findIndex((x) => x.id === id), 1); },
    async setPinned(id, pinned) { need(isAuthor(), 'Připínat mohou jen autoři.'); posts.find((x) => x.id === id).pinned_at = pinned ? now() : null; },
    async closeDiscussion(id, summary) {
      need(isAuthor(), 'Jen autoři mohou uzavřít diskusi.'); need(summary.trim().length >= 10, 'Napište shrnutí, co z diskuse vzešlo.');
      Object.assign(posts.find((x) => x.id === id), { closed_at: now(), closing_summary: summary.trim() });
    },
    async uploadCover(file) {
      const url = await new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(file); });
      const key = `demo-${++seq}`; covers[key] = url; return key;
    },
    async uploadAttachment(file) {
      const key = `demo-${++seq}`; files[key] = URL.createObjectURL(file);
      return { path: key, name: file.name.replace(/\.pdf$/i, ''), size_bytes: file.size };
    },
    attachmentUrl(path) { return files[path] || '#'; },
    coverUrl(path) { return path ? covers[path] || null : null; },

    async listComments(postId) {
      return wait(comments.filter((c) => c.post_id === postId).map((c) => {
        const a = people[c.author_id];
        return { ...c, hidden_reason: c.hidden_reason || null, body: c.hidden_reason && !isAuthor() ? null : c.body,
          author_name: a.display_name, author_is_team: a.role !== 'reader', author_badge: a.badge };
      }));
    },
    async addComment(postId, body, parentId = null) {
      need(current, 'Pro komentování se přihlaste.'); need(me().display_name, 'Než začnete komentovat, vyplňte své jméno.');
      const p = posts.find((x) => x.id === postId); need(!p.closed_at, 'Diskuse je uzavřená.');
      const parent = comments.find((c) => c.id === parentId);
      comments.push({ id: ++seq, post_id: postId, parent_id: parent ? parent.parent_id || parent.id : null, author_id: current, body: body.trim(), created_at: now() });
    },
    async updateComment(id, body) {
      const c = comments.find((x) => x.id === id);
      need(c && c.author_id === current, 'Komentář se nepodařilo upravit. Upravit lze jen vlastní komentář.');
      need(!c.hidden_reason, 'Skrytý komentář nejde upravit.');
      c.body = body.trim(); c.edited_at = now();
    },
    async deleteComment(id) {
      const c = comments.find((x) => x.id === id);
      need(c && (c.author_id === current || me()?.role === 'admin'), 'Komentář se nepodařilo smazat. Možná nemáte oprávnění.');
      for (let i = comments.length - 1; i >= 0; i--) if (comments[i].id === id || comments[i].parent_id === id) comments.splice(i, 1);
    },
    async hideComment(id, reason) { need(isAuthor(), 'Jen autoři mohou moderovat.'); comments.find((c) => c.id === id).hidden_reason = reason; },
    async unhideComment(id) { need(isAuthor(), 'Jen autoři mohou moderovat.'); comments.find((c) => c.id === id).hidden_reason = null; },

    async listPromises() { return wait(chapters.map((c) => ({ ...c, promises: c.promises.map((p) => ({ ...p, log: p.log.map((l) => ({ ...l, author: pub(l.author_id) })) })) }))); },
    async setPromiseStatus(id, status, note) {
      need(isAuthor(), 'Jen autoři mohou měnit stav slibu.'); need(status === 0 || note.trim().length >= 5, 'Napište, co se stalo. Bez vysvětlení se stav nemění.');
      const p = chapters.flatMap((c) => c.promises).find((x) => x.id === id);
      p.status = status; p.log.unshift({ id: ++seq, status, note: note.trim() || 'Stav vrácen na „nezahájeno“.', author_id: current, created_at: now() });
    },

    async listSections(page) { return wait(sections.filter((x) => x.page === page).sort((a, b) => a.position - b.position)); },
    async saveSection(page, d) {
      need(isAuthor(), 'K této akci nemáte oprávnění.');
      let s = sections.find((x) => x.id === d.id);
      if (!s) { s = { id: ++seq, page }; sections.push(s); }
      Object.assign(s, { title: d.title.trim(), body_html: d.body_html || '', position: d.position ?? s.position ?? sections.length, updated_at: now(),
        files: d.files.map((f, i) => ({ ...f, id: f.id || ++seq, position: i, name: f.name.trim() || 'Soubor' })) });
      return s.id;
    },
    async deleteSection(id) { need(isAuthor(), 'K této akci nemáte oprávnění.'); sections.splice(sections.findIndex((x) => x.id === id), 1); },
    async reorderSections(ids) { ids.forEach((id, i) => (sections.find((x) => x.id === id).position = i)); },
    async uploadPageFile(file, prepared) {
      if (!prepared) { const key = `demo-${++seq}`; files[key] = URL.createObjectURL(file); return { kind: 'pdf', path: key, name: file.name.replace(/\.pdf$/i, ''), size_bytes: file.size }; }
      const key = `demo-${++seq}`, tkey = `demo-${++seq}`;
      files[key] = URL.createObjectURL(prepared.main.blob); files[tkey] = URL.createObjectURL(prepared.thumb.blob);
      return { kind: 'image', path: key, thumb_path: tkey, name: file.name.replace(/\.\w+$/, ''), size_bytes: prepared.main.blob.size, width: prepared.main.width, height: prepared.main.height };
    },
    pageFileUrl(path) { return files[path] || demoImg(path); },
    async trackView() {},
    async statsDaily(days) {
      need(me()?.role === 'admin', 'Jen pro správce.');
      return wait(Array.from({ length: days }, (_, i) => {
        const d = new Date(Date.now() - (days - 1 - i) * 864e5);
        const base = 40 + 25 * Math.sin(i / 3) + (d.getDay() === 0 || d.getDay() === 6 ? -15 : 10);
        return { day: d.toISOString().slice(0, 10), views: Math.max(3, Math.round(base + (i * 37 % 23))) };
      }));
    },
    async statsPages() {
      need(me()?.role === 'admin', 'Jen pro správce.');
      return wait([
        { path: '/', post_id: null, title: null, views: 512 },
        { path: '/clanek/2', post_id: 2, title: posts.find((p) => p.id === 2)?.title, views: 233 },
        { path: '/sliby/', post_id: null, title: null, views: 187 },
        { path: '/clanek/1', post_id: 1, title: posts.find((p) => p.id === 1)?.title, views: 141 },
        { path: '/diskuse/', post_id: null, title: null, views: 96 },
        { path: '/clanek/3', post_id: 3, title: posts.find((p) => p.id === 3)?.title, views: 58 },
        { path: '/pravidla/', post_id: null, title: null, views: 12 }
      ]);
    },
    async listProfiles() { need(me()?.role === 'admin', 'Jen pro správce.'); return wait(Object.values(people)); },
    async updateProfile(id, patch) { need(me()?.role === 'admin', 'Jen pro správce.'); Object.assign(people[id], patch); }
  };
}
