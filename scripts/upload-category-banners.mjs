#!/usr/bin/env node
/**
 * Sube los banners iniciales de las secciones de la carta a Storage
 * (site-media/categories/<slug>.webp) y completa `categories.image_path` e
 * `image_is_illustrative`.
 *
 * Uso:  npm run media:banners      (también corre solo después de `npm run db:reset`)
 *
 * No destructivo: solo toca secciones que existan y NO tengan foto (image_path NULL),
 * así nunca pisa una foto cargada desde el panel. Si la foto ya estaba subida, se
 * reemplaza el archivo (mismo nombre) pero no se cambia ninguna fila con foto.
 *
 * Destino: Supabase LOCAL por defecto. Contra un proyecto REMOTO (SUPABASE_URL distinto
 * de localhost) exige escribir el host exacto. No usar contra remoto sin autorización.
 */
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const backRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const mediaDir = resolve(backRoot, "supabase/media/categories");
const BUCKET = "site-media";

const fail = (message) => {
  console.error(`\n✗ ${message}`);
  process.exit(1);
};

function ask(question) {
  return new Promise((done) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (answer) => {
      rl.close();
      done(answer.trim());
    });
  });
}

let url = process.env.SUPABASE_URL;
let secret = process.env.SUPABASE_SECRET_KEY;
if (!url) {
  try {
    const status = JSON.parse(
      execSync("npx supabase status -o json", { cwd: backRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }),
    );
    url = status.API_URL;
    secret = status.SECRET_KEY;
  } catch {
    fail("No hay SUPABASE_URL y Supabase local no está corriendo (npm run db:start).");
  }
}
if (!secret) fail("Falta SUPABASE_SECRET_KEY.");

const host = new URL(url).hostname;
const isLocal = ["127.0.0.1", "localhost"].includes(host);
console.log(`Destino: ${url} (${isLocal ? "LOCAL" : "REMOTO"})`);
if (!isLocal) {
  const confirmation = await ask(`⚠ Proyecto REMOTO. Para continuar escribí exactamente "${host}": `);
  if (confirmation !== host) fail("Confirmación incorrecta. No se hizo ningún cambio.");
}

const headers = { apikey: secret, Authorization: `Bearer ${secret}` };
const { banners } = JSON.parse(readFileSync(resolve(mediaDir, "manifest.json"), "utf8"));

const res = await fetch(
  `${url}/rest/v1/categories?select=id,slug,image_path&parent_id=is.null`,
  { headers },
);
if (!res.ok) fail(`No se pudieron leer las secciones: ${res.status} ${await res.text()}`);
const categories = new Map((await res.json()).map((c) => [c.slug, c]));

let uploaded = 0;
let skipped = 0;
for (const banner of banners) {
  const category = categories.get(banner.slug);
  if (!category) {
    console.log(`· ${banner.slug}: la sección no existe, se omite.`);
    skipped++;
    continue;
  }
  if (category.image_path) {
    console.log(`· ${banner.slug}: ya tiene foto (${category.image_path}), no se toca.`);
    skipped++;
    continue;
  }

  const path = `categories/${banner.slug}.webp`;
  const body = readFileSync(resolve(mediaDir, banner.file));
  const upload = await fetch(`${url}/storage/v1/object/${BUCKET}/${path}`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "image/webp", "x-upsert": "true", "cache-control": "max-age=31536000" },
    body,
  });
  if (!upload.ok) fail(`${banner.slug}: falló la subida (${upload.status} ${await upload.text()})`);

  const patch = await fetch(
    `${url}/rest/v1/categories?id=eq.${category.id}&image_path=is.null`,
    {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ image_path: path, image_is_illustrative: banner.illustrative }),
    },
  );
  if (!patch.ok) fail(`${banner.slug}: falló al guardar la ruta (${patch.status} ${await patch.text()})`);

  console.log(`✓ ${banner.slug} → ${path}${banner.illustrative ? " (ilustrativa)" : ""}`);
  uploaded++;
}

console.log(`\nListo: ${uploaded} subidas, ${skipped} omitidas.`);
