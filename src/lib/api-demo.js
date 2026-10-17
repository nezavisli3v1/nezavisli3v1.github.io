// Ukázkový režim: běží bez databáze, s vymyšleným obsahem v paměti prohlížeče.
// Spouští se automaticky, když chybí PUBLIC_SUPABASE_URL. Hodí se k ukázce kolegům a k vývoji.
import { DEMO_CHAPTERS } from './demo-program.js';

const wait = (v) => new Promise((r) => setTimeout(() => r(structuredClone(v)), 120));
const now = () => new Date().toISOString();
const daysAgo = (d) => new Date(Date.now() - d * 864e5).toISOString();

export function createDemoApi() {
  let seq = 1000;
  const people = {
    jan: { id: 'jan', display_name: 'Jan Dolejší', role: 'admin', badge: 'zastupitel', email: 'jan@example.cz' },
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
  const covers = {};

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
      const list = posts.filter((p) => (!kind || p.kind === kind) && (p.status === 'published' || (drafts && isAuthor())))
        .sort((a, b) => (b.published_at || '9').localeCompare(a.published_at || '9'));
      return wait(list.map((p) => ({ ...p, author: pub(p.author_id), comment_count: comments.filter((c) => c.post_id === p.id).length, has_poll: polls.some((x) => x.post_id === p.id) })));
    },
    async getPost(id) {
      const p = posts.find((x) => x.id === +id && (x.status === 'published' || isAuthor()));
      if (!p) return wait(null);
      const poll = polls.find((x) => x.post_id === p.id);
      return wait({ ...p, author: pub(p.author_id), poll: poll && { id: poll.id, question: poll.question, options: poll.options } });
    },
    async pollResults(pollId) {
      const poll = polls.find((x) => x.id === pollId);
      return wait({ votes: Object.fromEntries(poll.options.map((o) => [o.id, votes[o.id] || 0])), mine: myVotes[`${current}:${pollId}`] ?? null });
    },
    async vote(optionId) {
      need(current, 'Pro hlasování se přihlaste.');
      const poll = polls.find((x) => x.options.some((o) => o.id === optionId));
      const key = `${current}:${poll.id}`;
      if (myVotes[key]) votes[myVotes[key]]--;
      myVotes[key] = optionId; votes[optionId] = (votes[optionId] || 0) + 1;
    },
    async savePost(d) {
      need(isAuthor(), 'K této akci nemáte oprávnění.');
      let p = posts.find((x) => x.id === d.id);
      if (!p) { p = { id: ++seq, author_id: current, created_at: now(), closed_at: null, closing_summary: null }; posts.push(p); }
      Object.assign(p, { kind: d.kind, title: d.title.trim(), perex: d.perex.trim(), body_html: d.body_html, category: d.category,
        cover_path: d.cover_path || null, status: d.status, comments_enabled: d.comments_enabled, updated_at: now() });
      if (p.status === 'published' && !p.published_at) p.published_at = now();
      if (d.pollEditable) {
        const i = polls.findIndex((x) => x.post_id === p.id); if (i >= 0) polls.splice(i, 1);
        const opts = (d.poll?.options || []).map((o) => o.trim()).filter(Boolean);
        if (d.poll?.question?.trim() && opts.length >= 2) polls.push({ id: ++seq, post_id: p.id, question: d.poll.question.trim(), options: opts.map((label, position) => ({ id: ++seq, label, position })) });
      }
      return p.id;
    },
    async deletePost(id) { need(me()?.role === 'admin', 'Mazat může jen správce.'); posts.splice(posts.findIndex((x) => x.id === id), 1); },
    async closeDiscussion(id, summary) {
      need(isAuthor(), 'Jen autoři mohou uzavřít diskusi.'); need(summary.trim().length >= 10, 'Napište shrnutí, co z diskuse vzešlo.');
      Object.assign(posts.find((x) => x.id === id), { closed_at: now(), closing_summary: summary.trim() });
    },
    async uploadCover(file) {
      const url = await new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(file); });
      const key = `demo-${++seq}`; covers[key] = url; return key;
    },
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
    async hideComment(id, reason) { need(isAuthor(), 'Jen autoři mohou moderovat.'); comments.find((c) => c.id === id).hidden_reason = reason; },
    async unhideComment(id) { need(isAuthor(), 'Jen autoři mohou moderovat.'); comments.find((c) => c.id === id).hidden_reason = null; },

    async listPromises() { return wait(chapters.map((c) => ({ ...c, promises: c.promises.map((p) => ({ ...p, log: p.log.map((l) => ({ ...l, author: pub(l.author_id) })) })) }))); },
    async setPromiseStatus(id, status, note) {
      need(isAuthor(), 'Jen autoři mohou měnit stav slibu.'); need(status === 0 || note.trim().length >= 5, 'Napište, co se stalo. Bez vysvětlení se stav nemění.');
      const p = chapters.flatMap((c) => c.promises).find((x) => x.id === id);
      p.status = status; p.log.unshift({ id: ++seq, status, note: note.trim() || 'Stav vrácen na „nezahájeno“.', author_id: current, created_at: now() });
    },

    async listProfiles() { need(me()?.role === 'admin', 'Jen pro správce.'); return wait(Object.values(people)); },
    async updateProfile(id, patch) { need(me()?.role === 'admin', 'Jen pro správce.'); Object.assign(people[id], patch); }
  };
}
