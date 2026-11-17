#!/usr/bin/env node
/**
 * Crea (o promueve) el ADMINISTRADOR del CMS: usuario en Supabase Auth + fila en
 * `profiles` con role = 'admin'.
 *
 * Uso:  npm run admin:create
 *
 * Datos (nunca por argumentos de línea de comandos, que quedan en el historial):
 *   ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_FULL_NAME   → o se piden por consola
 *   SUPABASE_URL, SUPABASE_SECRET_KEY              → por defecto, Supabase LOCAL
 *
 * Contra un proyecto REMOTO (SUPABASE_URL distinto de localhost) exige escribir el
 * host exacto para confirmar. No usar contra remoto sin autorización.
 */
import { execSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const backRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// --- Entrada por consola (con eco oculto para la contraseña) -----------------
function ask(question, { hidden = false } = {}) {
  return new Promise((resolvePromise) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      rl._writeToOutput = (text) => {
        if (text.includes(question)) rl.output.write(text);
        else rl.output.write("*".repeat(text.length));
      };
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write("\n");
      resolvePromise(answer.trim());
    });
  });
}

function localConfig() {
  const status = JSON.parse(
    execSync("npx supabase status -o json", { cwd: backRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }),
  );
  return { url: status.API_URL, secret: status.SECRET_KEY };
}

const fail = (message) => {
  console.error(`\n✗ ${message}`);
  process.exit(1);
};

// --- Configuración -------------------------------------------------------------
let url = process.env.SUPABASE_URL;
let secret = process.env.SUPABASE_SECRET_KEY;
if (!url) {
  try {
    ({ url, secret } = localConfig());
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

const email = (process.env.ADMIN_EMAIL || (await ask("Email del administrador: "))).toLowerCase();
const fullName = process.env.ADMIN_FULL_NAME || (await ask("Nombre completo (opcional): "));
const password = process.env.ADMIN_PASSWORD || (await ask("Contraseña: ", { hidden: true }));

if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail("Email inválido.");
if (password.length < 12 || !/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/\d/.test(password)) {
  fail("La contraseña debe tener al menos 12 caracteres, con mayúsculas, minúsculas y dígitos.");
}

// --- API de administración (secret key: solo en este entorno confiable) --------
const headers = { apikey: secret, "Content-Type": "application/json" };

async function findUserByEmail(target) {
  for (let page = 1; page <= 50; page++) {
    const res = await fetch(`${url}/auth/v1/admin/users?page=${page}&per_page=100`, { headers });
    if (!res.ok) fail(`No se pudo listar usuarios: ${res.status}`);
    const { users } = await res.json();
    const match = users.find((u) => u.email?.toLowerCase() === target);
    if (match || users.length < 100) return match ?? null;
  }
  return null;
}

let user = await findUserByEmail(email);
if (user) {
  console.log("El usuario ya existe: se promueve a administrador (no se cambia su contraseña).");
} else {
  const res = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    headers,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  if (!res.ok) fail(`No se pudo crear el usuario: ${res.status} ${await res.text()}`);
  user = await res.json();
  console.log("Usuario creado en Auth.");
}

const profile = await fetch(`${url}/rest/v1/profiles?on_conflict=id`, {
  method: "POST",
  headers: { ...headers, Prefer: "resolution=merge-duplicates,return=minimal" },
  body: JSON.stringify({ id: user.id, full_name: fullName || null, role: "admin" }),
});
if (!profile.ok) fail(`Usuario creado, pero falló el perfil: ${profile.status} ${await profile.text()}`);

console.log(`✓ Administrador listo: ${email}`);
