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

const pick = (...names) => names.map((n) => (env[n] || "").trim()).find(Boolean) || "";
const url = pick("NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL", "VITE_SUPABASE_URL");
const key = pick("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY", "SUPABASE_KEY", "VITE_SUPABASE_ANON_KEY");
if (/^sb_secret_/.test(key) || /service_role/.test(key)) {
  console.error("✗ Esa es la llave secreta. Usa la publishable (sb_publishable_…) o la anon.");
  process.exit(1);
}

rmSync("dist", { recursive: true, force: true });
mkdirSync("dist", { recursive: true });
cpSync("index.html", "dist/index.html");
cpSync("fotos", "dist/fotos", { recursive: true });
writeFileSync("dist/config.js", `window.MONSE_CONFIG = ${JSON.stringify({ SUPABASE_URL: url, SUPABASE_KEY: key })};\n`);

if (url && key) {
  console.log(`✓ dist/ lista, conectada a ${url}`);
} else {
  // Ayuda para el log del hosting: muestra solo los NOMBRES de variables, nunca sus valores
  const vistas = Object.keys(env).filter((k) => k.includes("SUPABASE"));
  console.log("⚠ dist/ lista en MODO DEMO: faltan las llaves de Supabase.");
  console.log(`  URL: ${url ? "ok" : "falta NEXT_PUBLIC_SUPABASE_URL"} · Llave: ${key ? "ok" : "falta NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"}`);
  console.log(`  Variables con SUPABASE que ve este build: ${vistas.length ? vistas.join(", ") : "ninguna"}`);
  if (env.VERCEL) console.log(`  En Vercel: Settings → Environment Variables, marca el entorno "${env.VERCEL_ENV || "?"}" y vuelve a hacer deploy.`);
}
