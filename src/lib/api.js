import { env } from '$env/dynamic/public';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';
import { createSupabaseApi } from './api-supabase.js';
import { createDemoApi } from './api-demo.js';

// Ukázkový režim s vymyšleným obsahem: PUBLIC_DEMO=1 (např. `PUBLIC_DEMO=1 npm run dev`).
export const api = env.PUBLIC_DEMO === '1'
  ? createDemoApi()
  : createSupabaseApi(env.PUBLIC_SUPABASE_URL || SUPABASE_URL, env.PUBLIC_SUPABASE_ANON_KEY || SUPABASE_KEY);
