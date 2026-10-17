import { api } from './api.js';

export const session = $state({ ready: false, user: null, profile: null });
export const toastState = $state({ text: '', id: 0 });

let started = false;
export function startSession() {
  if (started) return; started = true;
  api.onAuth(async (user) => {
    session.user = user;
    try { session.profile = user ? await api.me(user) : null; } catch { session.profile = null; }
    session.ready = true;
  });
}
export async function refreshProfile() {
  if (session.user) session.profile = await api.me(session.user);
}
export const isAuthor = () => ['author', 'admin'].includes(session.profile?.role);
export const isAdmin = () => session.profile?.role === 'admin';

export function toast(text) {
  toastState.text = text; const id = ++toastState.id;
  setTimeout(() => { if (toastState.id === id) toastState.text = ''; }, 3200);
}
