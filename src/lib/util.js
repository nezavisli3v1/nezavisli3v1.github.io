import DOMPurify from 'dompurify';

export const CATEGORIES = ['Zastupitelstvo', 'Doprava', 'Rozpočet', 'Rozvoj obce', 'Veřejný prostor', 'Sport a volný čas', 'Senioři', 'Životní prostředí', 'Školství'];
export const STATUS = ['Nezahájeno', 'Rozpracováno', 'Splněno', 'Nepodařilo se'];
export const HIDE_REASONS = ['urážka', 'osobní údaje', 'spam', 'mimo téma'];

const fmt = new Intl.DateTimeFormat('cs-CZ', { day: 'numeric', month: 'numeric', year: 'numeric' });
export function date(iso) {
  if (!iso) return '';
  const d = new Date(iso), diff = (Date.now() - d) / 1000;
  if (diff < 60) return 'právě teď';
  if (diff < 3600) return `před ${Math.floor(diff / 60)} min`;
  if (diff < 86400 && new Date().getDate() === d.getDate()) return `dnes ${d.toLocaleTimeString('cs-CZ', { hour: 'numeric', minute: '2-digit' })}`;
  return fmt.format(d);
}

// Náhodný klíč prohlížeče pro hlasování bez přihlášení (jeden prohlížeč = jeden hlas v anketě).
let memKey = null;
export function voterKey() {
  try {
    let k = localStorage.getItem('nezavisli3v1-hlasovani');
    if (!k) { k = crypto.randomUUID(); localStorage.setItem('nezavisli3v1-hlasovani', k); }
    return k;
  } catch { return (memKey ??= crypto.randomUUID()); }
}

export function plural(n, one, few, many) { return `${n} ${n === 1 ? one : n >= 2 && n <= 4 ? few : many}`; }

export function clean(html) {
  return DOMPurify.sanitize(html || '', {
    ALLOWED_TAGS: ['p', 'h3', 'strong', 'b', 'em', 'i', 'u', 'a', 'ul', 'ol', 'li', 'br', 'blockquote'],
    ALLOWED_ATTR: ['href', 'target', 'rel']
  });
}

if (typeof window !== 'undefined') {
  DOMPurify.addHook('afterSanitizeAttributes', (node) => {
    if (node.tagName === 'A') { node.setAttribute('target', '_blank'); node.setAttribute('rel', 'noopener noreferrer'); }
  });
}

export const textLength = (html) => (html || '').replace(/<[^>]+>/g, '').trim().length;

export function fileSize(b) {
  if (b < 1024 * 1024) return `${Math.max(1, Math.round(b / 1024))} kB`;
  return `${(b / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
}
export const MAX_ATTACHMENT = 10 * 1024 * 1024;

// naplánovaný = zveřejněný s datem vydání v budoucnosti
export const isScheduled = (p) => p?.status === 'published' && !!p.published_at && new Date(p.published_at) > new Date();
export const isLive = (p) => p?.status === 'published' && !!p.published_at && new Date(p.published_at) <= new Date();
const fmtWhen = new Intl.DateTimeFormat('cs-CZ', { weekday: 'short', day: 'numeric', month: 'numeric', hour: 'numeric', minute: '2-digit' });
export const when = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : fmtWhen.format(d); };
// hodnota pro <input type="datetime-local"> v místním čase
export function localInput(d) {
  const z = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`;
}
