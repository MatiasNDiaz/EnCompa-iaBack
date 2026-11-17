#!/usr/bin/env node
/**
 * Test de seguridad de integración contra la API HTTP de Supabase LOCAL
 * (REST + Auth + Storage), tal como la usará el frontend con la clave publishable.
 *
 * Uso: npm run test:security   (requiere `npm run db:start`)
 *
 * - Crea 2 usuarios temporales (admin y no-admin) con contraseñas aleatorias.
 * - Ejecuta los intentos de escritura y lectura de cada rol.
 * - Borra usuarios y archivos de prueba al terminar.
 * - SOLO corre contra 127.0.0.1/localhost: nunca contra un proyecto remoto.
 */
import { execSync } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const backRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// --- Configuración local (las claves de demo las imprime el CLI local) -------
const status = JSON.parse(
  execSync("npx supabase status -o json", { cwd: backRoot, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }),
);
const API = status.API_URL;
const PUBLISHABLE = status.PUBLISHABLE_KEY;
const SECRET = status.SECRET_KEY;

if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(API)) {
  console.error(`Abortado: ${API} no es un entorno local.`);
  process.exit(1);
}

// --- Utilidades --------------------------------------------------------------
const results = [];
const check = (name, pass, detail = "") => {
  results.push({ name, pass });
  console.log(`${pass ? "  ✓" : "  ✗"} ${name}${pass ? "" : `  → ${detail}`}`);
};

const headers = (token, extra = {}) => ({
  apikey: PUBLISHABLE,
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
  ...extra,
});

const adminHeaders = { apikey: SECRET, "Content-Type": "application/json" };

async function createUser(email, password) {
  const res = await fetch(`${API}/auth/v1/admin/users`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  if (!res.ok) throw new Error(`No se pudo crear ${email}: ${res.status} ${await res.text()}`);
  return (await res.json()).id;
}

async function deleteUser(id) {
  await fetch(`${API}/auth/v1/admin/users/${id}`, { method: "DELETE", headers: adminHeaders });
}

async function signIn(email, password) {
  const res = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: headers(null, { "Content-Type": "application/json" }),
    body: JSON.stringify({ email, password }),
  });
  return { ok: res.ok, token: res.ok ? (await res.json()).access_token : null };
}

const rest = (path, { token, method = "GET", body } = {}) =>
  fetch(`${API}/rest/v1/${path}`, {
    method,
    headers: headers(token, { "Content-Type": "application/json", Prefer: "return=representation" }),
    body: body ? JSON.stringify(body) : undefined,
  });

const upload = (path, { token, type = "image/webp" } = {}) =>
  fetch(`${API}/storage/v1/object/site-media/${path}`, {
    method: "POST",
    headers: headers(token, { "Content-Type": type }),
    body: new Blob([randomBytes(64)], { type }),
  });

const removeObject = (path, token) =>
  fetch(`${API}/storage/v1/object/site-media/${path}`, { method: "DELETE", headers: headers(token) });

const publicExists = async (path) =>
  (await fetch(`${API}/storage/v1/object/public/site-media/${path}`)).status === 200;

// --- Escenario ---------------------------------------------------------------
const run = randomUUID().slice(0, 8);
const pwd = () => `${randomBytes(12).toString("base64url")}Aa1`;
const admin = { email: `admin-${run}@test.local`, password: pwd() };
const user = { email: `user-${run}@test.local`, password: pwd() };
const createdUsers = [];
const file = `products/test-${run}.webp`;

try {
  admin.id = await createUser(admin.email, admin.password);
  user.id = await createUser(user.email, user.password);
  createdUsers.push(admin.id, user.id);

  // El perfil admin se crea con la secret key (entorno confiable), nunca desde la API pública.
  const prof = await fetch(`${API}/rest/v1/profiles`, {
    method: "POST",
    headers: adminHeaders,
    body: JSON.stringify({ id: admin.id, full_name: "Admin de prueba", role: "admin" }),
  });
  if (!prof.ok) throw new Error(`No se pudo crear el perfil admin: ${prof.status} ${await prof.text()}`);

  const adminToken = (await signIn(admin.email, admin.password)).token;
  const userToken = (await signIn(user.email, user.password)).token;

  console.log("\nAuth");
  const signup = await fetch(`${API}/auth/v1/signup`, {
    method: "POST",
    headers: headers(null, { "Content-Type": "application/json" }),
    body: JSON.stringify({ email: `intruso-${run}@test.local`, password: pwd() }),
  });
  check("registro público deshabilitado", !signup.ok, `status ${signup.status}`);
  check("login con contraseña incorrecta falla", !(await signIn(admin.email, "incorrecta")).ok);
  check("login del admin funciona", Boolean(adminToken));

  console.log("\nVisitante (anon)");
  const pub = await rest("products?select=slug");
  check("lee la carta", pub.ok && (await pub.json()).length === 68, `status ${pub.status}`);
  const anonInsert = await rest("categories", { method: "POST", body: { name: "X", slug: `x-${run}` } });
  check("NO crea categorías", !anonInsert.ok, `status ${anonInsert.status}`);
  const anonPatch = await rest("products?slug=eq.espresso", { method: "PATCH", body: { price: 1 } });
  check("NO modifica precios", !anonPatch.ok, `status ${anonPatch.status}`);
  const anonProfile = await rest("profiles", { method: "POST", body: { id: user.id, role: "admin" } });
  check("NO crea perfiles admin", !anonProfile.ok, `status ${anonProfile.status}`);
  check("NO sube archivos", !(await upload(`products/anon-${run}.webp`)).ok);
  const moments = await rest("categories_with_moments?slug=eq.menu-del-dia&select=effective_moments");
  const [menuDelDia] = moments.ok ? await moments.json() : [];
  check("lee momentos heredados (Menú del día → mediodía)",
    JSON.stringify(menuDelDia?.effective_moments) === '["midday"]', `status ${moments.status}`);
  const anonMoments = await rest("categories?slug=eq.cocteleria", { method: "PATCH", body: { moments: ["morning"] } });
  check("NO modifica momentos", !anonMoments.ok, `status ${anonMoments.status}`);
  const anonView = await rest("categories_with_moments?slug=eq.cocteleria", { method: "PATCH", body: { moments: ["morning"] } });
  check("NO escribe momentos a través de la vista", !anonView.ok, `status ${anonView.status}`);

  console.log("\nUsuario autenticado sin rol admin");
  const uInsert = await rest("categories", { token: userToken, method: "POST", body: { name: "X", slug: `x-${run}` } });
  check("NO crea categorías", !uInsert.ok, `status ${uInsert.status}`);
  const uPatch = await rest("products?slug=eq.espresso", { token: userToken, method: "PATCH", body: { price: 1 } });
  check("NO modifica precios (0 filas)", uPatch.ok && (await uPatch.json()).length === 0, `status ${uPatch.status}`);
  const uDelete = await rest("products?slug=eq.espresso", { token: userToken, method: "DELETE" });
  check("NO borra productos (0 filas)", uDelete.ok && (await uDelete.json()).length === 0, `status ${uDelete.status}`);
  const uSelf = await rest("profiles", { token: userToken, method: "POST", body: { id: user.id, role: "admin" } });
  check("NO puede autoasignarse el rol admin", !uSelf.ok, `status ${uSelf.status}`);
  const uMoments = await rest("categories?slug=eq.cocteleria", { token: userToken, method: "PATCH", body: { moments: ["morning"] } });
  check("NO modifica momentos (0 filas)", uMoments.ok && (await uMoments.json()).length === 0, `status ${uMoments.status}`);
  check("NO sube archivos", !(await upload(`products/user-${run}.webp`, { token: userToken })).ok);

  console.log("\nAdministrador");
  // Reescribe el MISMO precio que ya tenía: prueba el permiso sin alterar los datos del seed.
  const [{ price: originalPrice }] = await (await rest("products?slug=eq.espresso&select=price")).json();
  const aPatch = await rest("products?slug=eq.espresso", { token: adminToken, method: "PATCH", body: { price: originalPrice } });
  check("modifica productos", aPatch.ok && (await aPatch.json()).length === 1, `status ${aPatch.status}`);
  const aUp = await upload(file, { token: adminToken });
  check("sube una imagen a products/", aUp.ok, `status ${aUp.status} ${aUp.ok ? "" : await aUp.text()}`);
  check("la imagen es pública por URL", await publicExists(file));
  check("NO sube fuera de las carpetas permitidas", !(await upload(`otros/x-${run}.webp`, { token: adminToken })).ok);
  check("NO sube tipos MIME no permitidos (text/html)",
    !(await upload(`products/x-${run}.html`, { token: adminToken, type: "text/html" })).ok);
  check("NO sube SVG (riesgo de XSS)",
    !(await upload(`branding/x-${run}.svg`, { token: adminToken, type: "image/svg+xml" })).ok);

  console.log("\nBorrado en Storage");
  await removeObject(file, userToken);
  check("el no-admin NO puede borrar el archivo", await publicExists(file));
  await removeObject(file);
  check("anon NO puede borrar el archivo", await publicExists(file));
  const aDel = await removeObject(file, adminToken);
  check("el admin borra el archivo", aDel.ok && !(await publicExists(file)), `status ${aDel.status}`);
} catch (error) {
  check("ejecución del escenario", false, error.message);
} finally {
  await removeObject(file, null).catch(() => {});
  for (const id of createdUsers) await deleteUser(id);
}

const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} verificaciones correctas`);
process.exit(failed ? 1 : 0);
