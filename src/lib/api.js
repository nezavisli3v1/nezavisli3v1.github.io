import { env } from '$env/dynamic/public';
import { createSupabaseApi } from './api-supabase.js';
import { createDemoApi } from './api-demo.js';

// Bez nastavené databáze běží aplikace v ukázkovém režimu.
export const api = env.PUBLIC_SUPABASE_URL && env.PUBLIC_SUPABASE_ANON_KEY
  ? createSupabaseApi(env.PUBLIC_SUPABASE_URL, env.PUBLIC_SUPABASE_ANON_KEY)
  : createDemoApi();
