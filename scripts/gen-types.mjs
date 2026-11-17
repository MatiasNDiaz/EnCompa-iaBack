#!/usr/bin/env node
/**
 * Genera los tipos TypeScript del esquema de Supabase LOCAL y los escribe en el frontend.
 * Es el único punto de contacto entre EnCompa-iaBack y EnCompa-iaFront.
 *
 * Uso: npm run types:gen   (requiere `npm run db:start`)
 */
import { execSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const backRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const target = resolve(backRoot, "../EnCompa-iaFront/src/types/database.types.ts");

let types;
try {
  // Comando fijo, sin datos externos interpolados.
  types = execSync("npx supabase gen types typescript --local", {
    cwd: backRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
} catch {
  console.error("No se pudieron generar los tipos. ¿Está corriendo Supabase local? (npm run db:start)");
  process.exit(1);
}

const header = "// Archivo generado por EnCompa-iaBack/scripts/gen-types.mjs. NO editar a mano.\n\n";
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, header + types);
console.log(`Tipos escritos en ${target}`);
