// Přístup k datům přes Supabase. Oprávnění hlídá databáze (viz supabase/migrations),
// tady se jen skládají dotazy a překládají chyby do češtiny.
import { createClient } from '@supabase/supabase-js';

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
      const p = await one(sb.from('profiles').select('id,display_name,role,badge').eq('id', user.id).maybeSingle());
      return p && { ...p, email: user.email };
    },
    async setMyName(name) { fail((await sb.rpc('set_my_name', { p_name: name })).error); },
    async deleteMyAccount() { fail((await sb.rpc('delete_my_account')).error); await sb.auth.signOut(); },

    // ── příspěvky
    async listPosts({ kind, drafts = false } = {}) {
      let q = sb.from('posts')
        .select('id,kind,title,perex,category,cover_path,status,published_at,created_at,updated_at,comments_enabled,closed_at,author_id')
        .order('published_at', { ascending: false, nullsFirst: true })
        .order('created_at', { ascending: false });
      if (kind) q = q.eq('kind', kind);
      if (!drafts) q = q.eq('status', 'published').lte('published_at', new Date().toISOString());
      const posts = await one(q);
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
        one(sb.from('poll_votes').select('option_id').eq('poll_id', pollId).maybeSingle())
      ]);
      return { votes: Object.fromEntries(rows.map((r) => [r.option_id, r.votes])), mine: mine?.option_id ?? null };
    },
    async vote(optionId) { fail((await sb.rpc('vote', { p_option: optionId })).error); },

    async savePost(d) {
      const row = {
        kind: d.kind, title: d.title.trim(), perex: d.perex.trim(), body_html: d.body_html, category: d.category,
        cover_path: d.cover_path || null, status: d.status, comments_enabled: d.comments_enabled
      };
      // publish_at: undefined = datum vydání neměnit, null = teď (nebo smazat u konceptu), ISO = naplánovat
      if (d.publish_at !== undefined) row.published_at = d.publish_at;
      let id = d.id;
      if (id) fail((await sb.from('posts').update(row).eq('id', id)).error);
      else {
        const { data: u } = await sb.auth.getUser();
        id = (await one(sb.from('posts').insert({ ...row, author_id: u.user.id }).select('id').single())).id;
      }
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
    async deletePost(id) { fail((await sb.from('posts').delete().eq('id', id)).error); },
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

    // ── správa lidí (jen správce)
    async listProfiles() { return one(sb.rpc('admin_people')); },
    async updateProfile(id, patch) { fail((await sb.from('profiles').update(patch).eq('id', id)).error); }
  };
}
