#!/usr/bin/env node
/**
 * Genera supabase/contenido-inicial.sql: el contenido para cargar UNA VEZ en un Supabase
 * NUEVO (producción). Las migraciones crean la estructura, pero la carta y los textos
 * oficiales viven en el seed, que no se aplica en un proyecto remoto.
 *
 * Se arma desde supabase/seed.sql (así no se desincroniza) y deja AFUERA lo que es solo
 * para desarrollo:
 *   · los BORRADORES de descripciones e ingredientes de los productos (texto genérico
 *     escrito para previsualizar; el cliente carga los reales desde el panel), y
 *   · los PRECIOS FICTICIOS.
 *
 * Incluye: secciones, subsecciones y productos de la carta (sin precio ni descripción),
 * los subtítulos de cada sección, los textos institucionales oficiales y las
 * capacitaciones. Los datos de contacto, el horario genérico y los 3 platos del día ya
 * los crean las migraciones; los banners se suben con `npm run media:banners`.
 *
 * Uso: npm run content:build   (solo genera el archivo; NO lo aplica a ninguna base)
 */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const seedPath = resolve(root, "supabase/seed.sql");
const outPath = resolve(root, "supabase/contenido-inicial.sql");
const lines = readFileSync(seedPath, "utf8").replace(/\r\n/g, "\n").split("\n");

/** Índice de la línea que contiene `marker` (exactamente una). */
function lineOf(marker) {
  const found = lines.flatMap((line, i) => (line.includes(marker) ? [i] : []));
  if (found.length !== 1) {
    throw new Error(`Marca "${marker}" encontrada ${found.length} veces en seed.sql (se esperaba 1).`);
  }
  return found[0];
}

// El separador (`-- ---` o `-- ===`) está en la línea anterior a cada título.
const start = lineOf("-- Categorías raíz (orden de la carta)") - 1;
const drafts = lineOf("-- BORRADOR de textos de la carta") - 1;
const subtitles = lineOf("-- Subtítulos de cada sección de la carta");
const prices = lineOf("-- PRECIOS FICTICIOS DE DESARROLLO") - 1;

const official = lines.slice(start, drafts).join("\n").trimEnd();
const categorySubtitles = lines.slice(subtitles, prices).join("\n").trimEnd();

for (const [name, block] of [["oficial", official], ["subtítulos", categorySubtitles]]) {
  if (/set price|BORRADOR|PRECIOS FICTICIOS/i.test(block)) {
    throw new Error(`El bloque ${name} incluye datos de desarrollo: revisar las marcas del seed.`);
  }
}

const sql = `-- =============================================================================
-- En Compañía · CONTENIDO INICIAL para un proyecto NUEVO (producción)
-- GENERADO por scripts/build-initial-content.mjs desde supabase/seed.sql: no editar a
-- mano (\`npm run content:build\` lo regenera).
--
-- Incluye: carta (secciones, subsecciones y productos SIN precio ni descripción),
-- subtítulos de las secciones, textos institucionales oficiales y capacitaciones.
-- NO incluye: precios ficticios ni borradores de descripciones/ingredientes (los reales
-- se cargan desde el panel).
--
-- Cómo aplicarlo (UNA vez, en el proyecto nuevo, después de \`supabase db push\`):
--   · Supabase → SQL Editor: pegar este archivo y ejecutar (corre como una transacción), o
--   · psql "<cadena de conexión>" --single-transaction -v ON_ERROR_STOP=1 -f supabase/contenido-inicial.sql
-- Después: \`npm run media:banners\` contra ese proyecto (fotos de los banners).
--
-- Seguridad: si la base ya tiene carta o textos, se detiene sin tocar nada.
-- =============================================================================

do $$
begin
  if exists (select 1 from public.categories) or exists (select 1 from public.site_content) then
    raise exception 'La base ya tiene contenido (carta o textos): este script es solo para un proyecto NUEVO.';
  end if;
end
$$;

${official}

${categorySubtitles}
`;

writeFileSync(outPath, sql);
console.log(`✓ ${outPath.replace(root + "\\", "").replace(root + "/", "")} (${sql.split("\n").length} líneas)`);
