// Přístup k datům přes Supabase. Oprávnění hlídá databáze (viz supabase/migrations),
// tady se jen skládají dotazy a překládají chyby do češtiny.
import { createClient } from '@supabase/supabase-js';
import { pinnedFirst } from './util.js';
import { voterKey } from './util.js';

export function createSupabaseApi(url, key) {
  const sb = createClient(url, key, { auth: { flowType: 'implicit', persistSession: true, detectSessionInUrl: true } });

  const fail = (error) => {
    if (!error) return;
    const m = error.message || '';
    if (/row-level security/.test(m)) throw new Error('K této akci nemáte oprávnění.');
    if (/rate limit/i.test(m)) throw new Error('Příliš mnoho pokusů. Zkuste to za chvíli znovu.');
    throw new Error(m);
  };
  const one = async (q) => { const { data, error } = await q; fail(error); return data; };

  async function people(ids) {
    const uniq = [...new Set(ids.filter(Boolean))];
    if (!uniq.length) return {};
    const rows = await one(sb.from('people').select('id,display_name,is_team,badge').in('id', uniq));
    return Object.fromEntries(rows.map((p) => [p.id, p]));
  }

  return {
    demo: false,

    // ── přihlášení
    onAuth(cb) {
      sb.auth.getSession().then(({ data }) => cb(data.session?.user ?? null));
      sb.auth.onAuthStateChange((_e, s) => cb(s?.user ?? null));
    },
    async signIn(email, next = '/') {
      const redirect = `${location.origin}/prihlaseni/?next=${encodeURIComponent(next)}`;
      fail((await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: redirect } })).error);
    },
    async signOut() { await sb.auth.signOut(); },
    async me(user) {
      // notify_* přibyly migrací 012; bez ní funguje i dřívější výběr
      let r = await sb.from('profiles').select('id,display_name,role,badge,notify_articles,notify_discussions').eq('id', user.id).maybeSingle();
      if (r.error) r = await sb.from('profiles').select('id,display_name,role,badge').eq('id', user.id).maybeSingle();
      fail(r.error);
      const p = r.data;
      return p && { ...p, email: user.email };
    },
    async setMyNotifications(articles, discussions) {
      fail((await sb.rpc('set_my_notifications', { p_articles: articles, p_discussions: discussions })).error);
    },
    async unsubscribe(token, kind) {
      const { data, error } = await sb.rpc('unsubscribe', { p_token: token, p_kind: kind }); fail(error); return data;
    },
    async setMyName(name) { fail((await sb.rpc('set_my_name', { p_name: name })).error); },
    async deleteMyAccount() { fail((await sb.rpc('delete_my_account')).error); await sb.auth.signOut(); },

    // ── příspěvky
    async listPosts({ kind, drafts = false } = {}) {
      const COLS = 'id,kind,title,perex,category,cover_path,status,published_at,created_at,updated_at,comments_enabled,closed_at,author_id';
      const query = (cols) => {
        let q = sb.from('posts').select(cols)
          .order('published_at', { ascending: false, nullsFirst: true })
          .order('created_at', { ascending: false });
        if (kind) q = q.eq('kind', kind);
        if (!drafts) q = q.eq('status', 'published').lte('published_at', new Date().toISOString());
        return q;
      };
      // pinned_at přibyl migrací 011; bez ní web funguje dál, jen bez připnutí
      let res = await query(COLS + ',pinned_at');
      if (res.error) res = await query(COLS);
      fail(res.error);
      const posts = pinnedFirst(res.data);
      const ids = posts.map((p) => p.id);
      const [authors, counts, polls] = await Promise.all([
        people(posts.map((p) => p.author_id)),
        ids.length ? one(sb.from('comment_feed').select('post_id').in('post_id', ids)) : [],
        ids.length ? one(sb.from('polls').select('post_id').in('post_id', ids)) : []
      ]);
      const n = {}; counts.forEach((c) => (n[c.post_id] = (n[c.post_id] || 0) + 1));
      const hasPoll = new Set(polls.map((p) => p.post_id));
      return posts.map((p) => ({ ...p, author: authors[p.author_id], comment_count: n[p.id] || 0, has_poll: hasPoll.has(p.id) }));
    },

    async getPost(id) {
      const p = await one(sb.from('posts').select('*').eq('id', id).maybeSingle());
      if (!p) return null;
      const author = (await people([p.author_id]))[p.author_id];
      const [poll, attachments] = await Promise.all([
        one(sb.from('polls').select('id,question,poll_options(id,label,position)').eq('post_id', id).maybeSingle()),
        one(sb.from('attachments').select('id,path,name,size_bytes,position').eq('post_id', id).order('position'))
      ]);
      return { ...p, author, attachments, poll: poll && { id: poll.id, question: poll.question, options: poll.poll_options.sort((a, b) => a.position - b.position) } };
    },

    async pollResults(pollId) {
      const [rows, mine] = await Promise.all([
        one(sb.from('poll_results').select('option_id,votes').eq('poll_id', pollId)),
        one(sb.rpc('my_vote', { p_poll: pollId, p_key: voterKey() }))
      ]);
      return { votes: Object.fromEntries(rows.map((r) => [r.option_id, r.votes])), mine: mine ?? null };
    },
    // hlasovat jde i bez přihlášení; nepřihlášeného pozná databáze podle klíče prohlížeče
    async vote(optionId) { fail((await sb.rpc('vote_any', { p_option: optionId, p_key: voterKey() })).error); },

    async savePost(d) {
      const row = {
        kind: d.kind, title: d.title.trim(), perex: d.perex.trim(), body_html: d.body_html, category: d.category,
        cover_path: d.cover_path || null, status: d.status, comments_enabled: d.comments_enabled
      };
      // publish_at: undefined = datum vydání neměnit, null = teď (nebo smazat u konceptu), ISO = naplánovat
      if (d.publish_at !== undefined) row.published_at = d.publish_at;
      if (typeof d.notify === 'boolean') row.notify = d.notify;
      let id = d.id;
      const write = async (r) => {
        if (id) return (await sb.from('posts').update(r).eq('id', id)).error;
        const { data: u } = await sb.auth.getUser();
        const res = await sb.from('posts').insert({ ...r, author_id: u.user.id }).select('id').single();
        if (!res.error) id = res.data.id;
        return res.error;
      };
      let err = await write(row);
      if (err && /notify/.test(err.message)) { delete row.notify; err = await write(row); } // před migrací 012
      fail(err);
      if (d.attachments) {
        const existing = await one(sb.from('attachments').select('id,path').eq('post_id', id));
        const keep = new Set(d.attachments.filter((a) => a.id).map((a) => a.id));
        const gone = existing.filter((a) => !keep.has(a.id));
        if (gone.length) {
          fail((await sb.from('attachments').delete().in('id', gone.map((a) => a.id))).error);
          await sb.storage.from('attachments').remove(gone.map((a) => a.path));
        }
        for (const [i, a] of d.attachments.entries()) {
          const row = { name: a.name.trim() || 'Příloha', position: i };
          if (a.id) fail((await sb.from('attachments').update(row).eq('id', a.id)).error);
          else fail((await sb.from('attachments').insert({ ...row, post_id: id, path: a.path, size_bytes: a.size_bytes })).error);
        }
      }
      // anketu lze měnit jen do zveřejnění, aby se nepřepsaly hlasy
      if (d.pollEditable) {
        fail((await sb.from('polls').delete().eq('post_id', id)).error);
        const opts = (d.poll?.options || []).map((o) => o.trim()).filter(Boolean);
        if (d.poll?.question?.trim() && opts.length >= 2) {
          const poll = await one(sb.from('polls').insert({ post_id: id, question: d.poll.question.trim() }).select('id').single());
          fail((await sb.from('poll_options').insert(opts.map((label, i) => ({ poll_id: poll.id, label, position: i })))).error);
        }
      }
      return id;
    },
    // smaže příspěvek i jeho soubory (fotku a PDF), aby nezůstaly dostupné přes přímý odkaz
    async deletePost(id) {
      const [post, atts] = await Promise.all([
        one(sb.from('posts').select('cover_path').eq('id', id).maybeSingle()),
        one(sb.from('attachments').select('path').eq('post_id', id))
      ]);
      fail((await sb.from('posts').delete().eq('id', id)).error);
      if (post?.cover_path) await sb.storage.from('covers').remove([post.cover_path]);
      if (atts.length) await sb.storage.from('attachments').remove(atts.map((a) => a.path));
    },
    async setPinned(id, pinned) { fail((await sb.rpc('set_pinned', { p_post: id, p_pinned: pinned })).error); },
    async closeDiscussion(id, summary) { fail((await sb.rpc('close_discussion', { p_post: id, p_summary: summary })).error); },

    async uploadCover(file) {
      const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '');
      const path = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.${ext}`;
      fail((await sb.storage.from('covers').upload(path, file, { cacheControl: '31536000', contentType: file.type })).error);
      return path;
    },
    async uploadAttachment(file) {
      const path = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.pdf`;
      fail((await sb.storage.from('attachments').upload(path, file, { cacheControl: '31536000', contentType: 'application/pdf' })).error);
      return { path, name: file.name.replace(/\.pdf$/i, ''), size_bytes: file.size };
    },
    attachmentUrl(path) { return sb.storage.from('attachments').getPublicUrl(path).data.publicUrl; },
    coverUrl(path) { return path ? sb.storage.from('covers').getPublicUrl(path).data.publicUrl : null; },

    // ── komentáře
    async listComments(postId) {
      return one(sb.from('comment_feed').select('*').eq('post_id', postId).order('created_at'));
    },
    async addComment(postId, body, parentId = null) {
      const { data: u } = await sb.auth.getUser();
      fail((await sb.from('comments').insert({ post_id: postId, parent_id: parentId, body: body.trim(), author_id: u.user.id })).error);
    },
    async updateComment(id, body) {
      const { data, error } = await sb.from('comments').update({ body: body.trim() }).eq('id', id).select('id'); fail(error);
      if (!data?.length) throw new Error('Komentář se nepodařilo upravit. Upravit lze jen vlastní komentář.');
    },
    async deleteComment(id) {
      const { data, error } = await sb.from('comments').delete().eq('id', id).select('id'); fail(error);
      if (!data?.length) throw new Error('Komentář se nepodařilo smazat. Možná nemáte oprávnění.');
    },
    async hideComment(id, reason) { fail((await sb.rpc('hide_comment', { p_id: id, p_reason: reason })).error); },
    async unhideComment(id) { fail((await sb.rpc('unhide_comment', { p_id: id })).error); },

    // ── hlídač slibů
    async listPromises() {
      const [chapters, promises, log] = await Promise.all([
        one(sb.from('chapters').select('*').order('position')),
        one(sb.from('promises').select('*').order('position')),
        one(sb.from('promise_log').select('*').order('created_at', { ascending: false }))
      ]);
      const authors = await people(log.map((l) => l.author_id));
      return chapters.map((c) => ({
        ...c,
        promises: promises.filter((p) => p.chapter_id === c.id).map((p) => ({
          ...p, log: log.filter((l) => l.promise_id === p.id).map((l) => ({ ...l, author: authors[l.author_id] }))
        }))
      }));
    },
    async setPromiseStatus(id, status, note) {
      fail((await sb.rpc('set_promise_status', { p_promise: id, p_status: status, p_note: note })).error);
    },

    // ── stálé stránky (Územní plán): oddíly s obrázky a PDF
    async listSections(page) {
      const rows = await one(sb.from('page_sections').select('*, section_files(*)').eq('page', page).order('position'));
      return rows.map(({ section_files, ...s }) => ({ ...s, files: (section_files || []).sort((a, b) => a.position - b.position) }));
    },
    async saveSection(page, d) {
      const row = { page, title: d.title.trim(), body_html: d.body_html || '', position: d.position ?? 0 };
      let id = d.id;
      if (id) fail((await sb.from('page_sections').update(row).eq('id', id)).error);
      else id = (await one(sb.from('page_sections').insert(row).select('id').single())).id;
      const existing = await one(sb.from('section_files').select('id,path,thumb_path').eq('section_id', id));
      const keep = new Set(d.files.filter((f) => f.id).map((f) => f.id));
      const gone = existing.filter((f) => !keep.has(f.id));
      if (gone.length) {
        fail((await sb.from('section_files').delete().in('id', gone.map((f) => f.id))).error);
        await sb.storage.from('pages').remove(gone.flatMap((f) => [f.path, f.thumb_path].filter(Boolean)));
      }
      for (const [i, f] of d.files.entries()) {
        const meta = { name: f.name.trim() || (f.kind === 'pdf' ? 'Dokument' : 'Obrázek'), position: i };
        if (f.id) fail((await sb.from('section_files').update(meta).eq('id', f.id)).error);
        else fail((await sb.from('section_files').insert({ ...meta, section_id: id, kind: f.kind, path: f.path, thumb_path: f.thumb_path || null,
          size_bytes: f.size_bytes, width: f.width || null, height: f.height || null })).error);
      }
      return id;
    },
    async deleteSection(id) {
      const files = await one(sb.from('section_files').select('path,thumb_path').eq('section_id', id));
      fail((await sb.from('page_sections').delete().eq('id', id)).error);
      if (files.length) await sb.storage.from('pages').remove(files.flatMap((f) => [f.path, f.thumb_path].filter(Boolean)));
    },
    async reorderSections(ids) {
      for (const [i, id] of ids.entries()) fail((await sb.from('page_sections').update({ position: i }).eq('id', id)).error);
    },
    async uploadPageFile(file, prepared) {
      const base = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}`;
      const up = async (path, body, type) => fail((await sb.storage.from('pages').upload(path, body, { cacheControl: '31536000', contentType: type })).error);
      if (!prepared) {
        await up(`${base}.pdf`, file, 'application/pdf');
        return { kind: 'pdf', path: `${base}.pdf`, name: file.name.replace(/\.pdf$/i, ''), size_bytes: file.size };
      }
      const ext = prepared.type === 'image/png' ? 'png' : prepared.type === 'image/webp' ? 'webp' : 'jpg';
      await up(`${base}.${ext}`, prepared.main.blob, prepared.type);
      await up(`${base}-nahled.jpg`, prepared.thumb.blob, 'image/jpeg');
      return { kind: 'image', path: `${base}.${ext}`, thumb_path: `${base}-nahled.jpg`, name: file.name.replace(/\.\w+$/, ''),
        size_bytes: prepared.main.blob.size, width: prepared.main.width, height: prepared.main.height };
    },
    pageFileUrl(path) { return path ? sb.storage.from('pages').getPublicUrl(path).data.publicUrl : null; },

    // ── počítadlo (zápis smí každý, čtení jen správce)
    async trackView(path, postId = null) {
      try { await sb.rpc('track_view', { p_path: path, p_post: postId }); } catch { /* statistika nesmí rozbít web */ }
    },
    async statsDaily(days) { return one(sb.rpc('stats_daily', { p_days: days })); },
    async statsPages(days) { return one(sb.rpc('stats_pages', { p_days: days })); },

    // ── správa lidí (jen správce)
    async listProfiles() { return one(sb.rpc('admin_people')); },
    async updateProfile(id, patch) { fail((await sb.from('profiles').update(patch).eq('id', id)).error); }
  };
}
