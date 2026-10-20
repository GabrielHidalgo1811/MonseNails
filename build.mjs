// Genera la carpeta dist/ lista para publicar.
// Lee las llaves de Supabase desde .env (local) o desde las variables de entorno
// del hosting (Netlify / Vercel) y las escribe en dist/config.js.
// Uso: node build.mjs
import { readFileSync, writeFileSync, mkdirSync, cpSync, rmSync, existsSync } from "node:fs";

const env = { ...process.env };
if (existsSync(".env")) {
  for (const line of readFileSync(".env", "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

const url = env.NEXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL || "";
const key = env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || env.NEXT_PUBLIC_SUPABASE_ANON_KEY || env.SUPABASE_KEY || "";
if (/^sb_secret_/.test(key) || /service_role/.test(key)) {
  console.error("✗ Esa es la llave secreta. Usa la publishable (sb_publishable_…) o la anon.");
  process.exit(1);
}

rmSync("dist", { recursive: true, force: true });
mkdirSync("dist", { recursive: true });
cpSync("index.html", "dist/index.html");
cpSync("fotos", "dist/fotos", { recursive: true });
writeFileSync("dist/config.js", `window.MONSE_CONFIG = ${JSON.stringify({ SUPABASE_URL: url, SUPABASE_KEY: key })};\n`);

console.log(url && key ? `✓ dist/ lista, conectada a ${url}` : "⚠ dist/ lista en MODO DEMO (faltan las llaves en .env)");
