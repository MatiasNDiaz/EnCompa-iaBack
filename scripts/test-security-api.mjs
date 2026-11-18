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

/** Lectura con la secret key (sin RLS): el estado real, para comparar. */
const serviceGet = async (path) =>
  (await fetch(`${API}/rest/v1/${path}`, { headers: { ...adminHeaders, Authorization: `Bearer ${SECRET}` } })).json();

const publicExists = async (path) =>
  (await fetch(`${API}/storage/v1/object/public/site-media/${path}`)).status === 200;

// --- Escenario ---------------------------------------------------------------
const run = randomUUID().slice(0, 8);
const pwd = () => `${randomBytes(12).toString("base64url")}Aa1`;
const admin = { email: `admin-${run}@test.local`, password: pwd() };
const user = { email: `user-${run}@test.local`, password: pwd() };
const createdUsers = [];
const file = `products/test-${run}.webp`;
const specialFile = `specials/test-${run}.webp`;
const exceptionNote = `security-${run}`;
const newsFile = `news/test-${run}.mp4`;
const newsSlug = `security-${run}`;
const newsRow = { title: "x", slug: newsSlug, description: "x", media_type: "image", media_path: "news/x.webp" };

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
  // Lo esperado se calcula con la secret key (no depende de lo cargado desde el panel).
  const allCategories = await serviceGet("categories?select=id,parent_id,is_active");
  const allProducts = await serviceGet("products?select=category_id,is_available");
  const byId = new Map(allCategories.map((c) => [c.id, c]));
  const visible = (id) => {
    const c = byId.get(id);
    return c.is_active && (c.parent_id === null || byId.get(c.parent_id).is_active);
  };
  const expectedProducts = allProducts.filter((p) => p.is_available && visible(p.category_id)).length;
  const pub = await rest("products?select=slug");
  const pubCount = pub.ok ? (await pub.json()).length : -1;
  check("lee la carta (solo productos disponibles de secciones visibles)",
    pubCount === expectedProducts, `status ${pub.status}, ve ${pubCount}, esperado ${expectedProducts}`);
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
  const anonStock = await rest("products?slug=eq.espresso", { method: "PATCH", body: { out_of_stock_on: "2026-01-01" } });
  check("NO marca productos sin stock", !anonStock.ok, `status ${anonStock.status}`);
  const anonComputed = await rest("products?slug=eq.espresso&select=out_of_stock_today");
  check("lee el campo calculado out_of_stock_today", anonComputed.ok, `status ${anonComputed.status}`);
  const anonReorder = await rest("rpc/reorder_categories", { method: "POST", body: { ids: [] } });
  check("NO puede reordenar la carta (RPC)", !anonReorder.ok, `status ${anonReorder.status}`);
  check("NO sube banners", !(await upload(`categories/anon-${run}.webp`)).ok);

  const allSpecials = await serviceGet("daily_specials?select=moment,is_published,image_path,subtitle");
  const publishedSpecials = allSpecials.filter((s) => s.is_published).map((s) => s.moment).sort();
  const anonSpecials = await rest("daily_specials?select=moment");
  const anonSpecialMoments = anonSpecials.ok ? (await anonSpecials.json()).map((s) => s.moment).sort() : null;
  check("plato del día: ve SOLO los publicados",
    JSON.stringify(anonSpecialMoments) === JSON.stringify(publishedSpecials),
    `ve ${JSON.stringify(anonSpecialMoments)}, publicados ${JSON.stringify(publishedSpecials)}`);
  const anonSpecialPatch = await rest("daily_specials?moment=eq.morning", { method: "PATCH", body: { title: "x" } });
  check("plato del día: NO edita", !anonSpecialPatch.ok, `status ${anonSpecialPatch.status}`);
  check("plato del día: NO sube fotos", !(await upload(`specials/anon-${run}.webp`)).ok);
  const anonHours = await rest("site_settings?select=opening_hours");
  check("horarios: lee el horario semanal", anonHours.ok, `status ${anonHours.status}`);
  const anonHoursPatch = await rest("site_settings?singleton=is.true", { method: "PATCH", body: { opening_hours: null } });
  check("horarios: NO cambia el horario", !anonHoursPatch.ok, `status ${anonHoursPatch.status}`);
  const anonException = await rest("opening_exceptions", { method: "POST", body: { date: "2099-01-01", type: "closed", note: exceptionNote } });
  check("horarios: NO crea días especiales", !anonException.ok, `status ${anonException.status}`);
  const anonNews = await rest("news_posts", { method: "POST", body: newsRow });
  check("novedades: NO crea", !anonNews.ok, `status ${anonNews.status}`);
  check("novedades: NO sube archivos a news/", !(await upload(`news/anon-${run}.webp`)).ok);

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
  const uReorder = await rest("rpc/reorder_categories", { token: userToken, method: "POST", body: { ids: [] } });
  check("NO puede reordenar la carta (RPC)", !uReorder.ok, `status ${uReorder.status}`);
  check("NO sube fotos del plato del día", !(await upload(`specials/user-${run}.webp`, { token: userToken })).ok);
  const uSpecial = await rest("daily_specials?moment=not.is.null", { token: userToken, method: "PATCH", body: { is_published: false } });
  check("NO edita el plato del día (0 filas)",
    uSpecial.ok && (await uSpecial.json()).length === 0, `status ${uSpecial.status}`);
  const uException = await rest("opening_exceptions", { token: userToken, method: "POST", body: { date: "2099-01-01", type: "closed", note: exceptionNote } });
  check("NO crea días especiales", !uException.ok, `status ${uException.status}`);
  const uNews = await rest("news_posts", { token: userToken, method: "POST", body: newsRow });
  check("NO crea novedades", !uNews.ok, `status ${uNews.status}`);
  check("NO sube archivos a news/", !(await upload(`news/user-${run}.webp`, { token: userToken })).ok);
  const uHours = await rest("site_settings?singleton=is.true", { token: userToken, method: "PATCH", body: { opening_hours: null } });
  check("NO cambia el horario (0 filas)", uHours.ok && (await uHours.json()).length === 0, `status ${uHours.status}`);
  const uPurge = await rest("rpc/purge_past_opening_exceptions", { token: userToken, method: "POST", body: {} });
  check("la limpieza de días pasados no borra nada", uPurge.ok && (await uPurge.json()) === 0, `status ${uPurge.status}`);

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

  // Plato del día: 3 filas fijas. El admin las lee y edita, pero no crea ni borra.
  const aSpecials = await rest("daily_specials?select=moment", { token: adminToken });
  check("plato del día: el admin ve los 3 espacios",
    aSpecials.ok && (await aSpecials.json()).length === 3, `status ${aSpecials.status}`);
  const morning = allSpecials.find((s) => s.moment === "morning");
  const aSpecialPatch = await rest("daily_specials?moment=eq.morning", {
    token: adminToken, method: "PATCH", body: { subtitle: morning.subtitle }, // mismo valor: no altera datos
  });
  check("plato del día: el admin edita",
    aSpecialPatch.ok && (await aSpecialPatch.json()).length === 1, `status ${aSpecialPatch.status}`);
  const aSpecialInsert = await rest("daily_specials", { token: adminToken, method: "POST", body: { moment: "morning" } });
  check("plato del día: el admin NO crea filas", !aSpecialInsert.ok, `status ${aSpecialInsert.status}`);
  const aSpecialDelete = await rest("daily_specials?moment=eq.evening", { token: adminToken, method: "DELETE" });
  check("plato del día: el admin NO borra filas", !aSpecialDelete.ok, `status ${aSpecialDelete.status}`);
  const empty = allSpecials.find((s) => !s.is_published && !s.image_path);
  if (empty) {
    const aPublishEmpty = await rest(`daily_specials?moment=eq.${empty.moment}`, {
      token: adminToken, method: "PATCH", body: { is_published: true },
    });
    check("plato del día: NO se publica sin foto ni título", !aPublishEmpty.ok, `status ${aPublishEmpty.status}`);
  }
  const aSpecialUp = await upload(specialFile, { token: adminToken });
  check("sube una foto a specials/", aSpecialUp.ok, `status ${aSpecialUp.status}`);
  await removeObject(specialFile, adminToken);

  // Horarios: el admin crea, valida y borra días especiales (fecha lejana: no se ve en la web).
  const aException = await rest("opening_exceptions", {
    token: adminToken, method: "POST", body: { date: "2099-12-31", type: "closed", note: exceptionNote },
  });
  check("horarios: el admin crea un día especial", aException.ok, `status ${aException.status}`);
  const aBadException = await rest("opening_exceptions", {
    token: adminToken, method: "POST", body: { date: "2099-12-30", type: "custom", note: exceptionNote },
  });
  check("horarios: NO acepta un horario distinto sin franjas", !aBadException.ok, `status ${aBadException.status}`);
  const aBadHours = await rest("site_settings?singleton=is.true", {
    token: adminToken, method: "PATCH", body: { opening_hours: [{ day: "monday", ranges: [] }] },
  });
  check("horarios: NO acepta un horario semanal incompleto", !aBadHours.ok, `status ${aBadHours.status}`);
  const aExceptionDelete = await rest(`opening_exceptions?note=eq.${encodeURIComponent(exceptionNote)}`, {
    token: adminToken, method: "DELETE",
  });
  check("horarios: el admin borra el día especial",
    aExceptionDelete.ok && (await aExceptionDelete.json()).length === 1, `status ${aExceptionDelete.status}`);

  // Novedades: el admin sube un video a news/, crea un borrador (no se ve público) y lo borra.
  const aNewsUp = await upload(newsFile, { token: adminToken, type: "video/mp4" });
  check("novedades: el admin sube un video a news/", aNewsUp.ok, `status ${aNewsUp.status}`);
  const videoRow = { ...newsRow, media_type: "video", media_path: newsFile };
  const aNewsNoPoster = await rest("news_posts", { token: adminToken, method: "POST", body: videoRow });
  check("novedades: NO acepta un video sin portada", !aNewsNoPoster.ok, `status ${aNewsNoPoster.status}`);
  const aNews = await rest("news_posts", {
    token: adminToken, method: "POST", body: { ...videoRow, poster_path: "news/poster.webp" },
  });
  check("novedades: el admin crea un borrador", aNews.ok, `status ${aNews.status}`);
  const anonDraft = await rest(`news_posts?slug=eq.${newsSlug}&select=id`);
  check("novedades: anon NO ve el borrador",
    anonDraft.ok && (await anonDraft.json()).length === 0, `status ${anonDraft.status}`);
  const aNewsDelete = await rest(`news_posts?slug=eq.${newsSlug}`, { token: adminToken, method: "DELETE" });
  check("novedades: el admin elimina",
    aNewsDelete.ok && (await aNewsDelete.json()).length === 1, `status ${aNewsDelete.status}`);
  await removeObject(newsFile, adminToken);

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
  await fetch(`${API}/storage/v1/object/site-media/${specialFile}`, {
    method: "DELETE", headers: { ...adminHeaders, Authorization: `Bearer ${SECRET}` },
  }).catch(() => {});
  await fetch(`${API}/rest/v1/opening_exceptions?note=eq.${encodeURIComponent(exceptionNote)}`, {
    method: "DELETE", headers: { ...adminHeaders, Authorization: `Bearer ${SECRET}` },
  }).catch(() => {});
  for (const path of [`rest/v1/news_posts?slug=eq.${newsSlug}`, `storage/v1/object/site-media/${newsFile}`]) {
    await fetch(`${API}/${path}`, {
      method: "DELETE", headers: { ...adminHeaders, Authorization: `Bearer ${SECRET}` },
    }).catch(() => {});
  }
  for (const id of createdUsers) await deleteUser(id);
}

const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} verificaciones correctas`);
process.exit(failed ? 1 : 0);
