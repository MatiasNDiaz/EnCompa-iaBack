# Seguridad — modelo y decisiones

Principio: **la seguridad vive en la base de datos.** El frontend puede ocultar botones, pero
aunque alguien use la API directamente con la clave publishable, PostgreSQL rechaza lo que no
corresponde.

## Roles

| Rol | Quién | Puede |
|---|---|---|
| `anon` | Visitante (clave publishable, sin sesión) | Leer contenido público |
| `authenticated` sin perfil | Usuario con sesión pero sin fila en `profiles` | Lo mismo que `anon` + leer su perfil (no tiene) |
| `authenticated` + `profiles.role = 'admin'` | Administrador | CRUD completo de contenido y Storage |
| `service_role` / secret key | Scripts desde un entorno confiable | Todo (salta RLS). **Nunca en el frontend.** |

## Defensa en capas

1. **Privilegios (`GRANT`/`REVOKE`)**: `anon` solo tiene `SELECT` (ni eso en `profiles`). Aunque
   una política estuviera mal escrita, una escritura de `anon` falla con `42501`.
   `site_settings` no admite `INSERT`/`DELETE` desde la API; `profiles` no admite escrituras.
2. **RLS** en las 9 tablas expuestas:
   - Lectura pública: categorías activas (y con padre activo), productos disponibles de categorías
     visibles, ítems/imágenes/capacitaciones publicadas, fotos de capacitaciones publicadas,
     `site_content` y `site_settings`.
   - Escritura: solo si `private.is_admin()`.
3. **Restricciones** (`CHECK`, FK, dominio `slug`, validadores de paths): datos inválidos se
   rechazan incluso para el admin.
4. **Storage**: políticas propias sobre `storage.objects` (ver `STORAGE.md`).
5. **Next.js** (Fase 3): el layout de `/admin` y cada Server Action verifican sesión y rol en el
   servidor con `getClaims()`/`getUser()`. Es una capa más, no la única.

## Funciones de autorización

| Función | Tipo | Para qué |
|---|---|---|
| `private.is_admin()` | `SECURITY DEFINER`, `STABLE`, `search_path = ''` | ¿El `auth.uid()` actual tiene perfil `admin`? |
| `private.is_category_visible(uuid)` | ídem | ¿Categoría activa y con padre activo? |

- **Sin recursión de RLS**: al ser `SECURITY DEFINER` leen `profiles`/`categories` sin disparar
  sus políticas. Una política de `categories` que consultara `categories` directamente entraría
  en recursión infinita.
- **`search_path = ''`** y nombres calificados: inmunes a secuestro de `search_path`.
- **Esquema `private` en lugar de `public`** (el prompt pedía `public.is_admin()`): `private` no
  está expuesto por la Data API, así que las funciones no se pueden invocar como RPC
  (`/rest/v1/rpc/...`) y no se exponen funciones `SECURITY DEFINER` en un esquema público.
- **`EXECUTE` mínimo**: `is_admin()` solo para `authenticated` (anon no lo necesita);
  `is_category_visible()` para `anon` y `authenticated`.
- Las políticas usan `(select private.is_admin())`, que se evalúa **una vez por consulta**, no por fila.

## Autenticación

- Email + contraseña. **Registro público deshabilitado** (`enable_signup = false`).
- Contraseñas: mínimo 12 caracteres, con mayúsculas, minúsculas y dígitos.
- Rotación de refresh tokens activada.
- En el proyecto remoto estas opciones se configuran en el Dashboard (Authentication →
  Providers/Policies) o con `supabase config push`, **previa autorización**.

### Creación del administrador (procedimiento seguro)

El administrador nunca se crea desde la web ni queda en el repositorio. Un usuario sin perfil
`admin` no tiene permisos aunque inicie sesión.

**Con el script (recomendado):** `npm run admin:create` (`scripts/create-admin.mjs`).

- Crea el usuario en Auth (email confirmado) y su fila en `profiles` con `role = 'admin'`. Si el
  usuario ya existe, solo lo promueve (no cambia su contraseña). Es idempotente.
- Datos: `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_FULL_NAME` por variables de entorno o, si faltan,
  **se piden por consola** (la contraseña sin eco). Nunca por argumentos de línea de comandos
  (quedarían en el historial de la terminal).
- Valida la misma política de contraseñas que Auth (≥ 12, mayúsculas, minúsculas y dígitos).
- **Por defecto apunta a Supabase local** (toma URL y secret key de `supabase status`).
- **Remoto:** `SUPABASE_URL` y `SUPABASE_SECRET_KEY` por variable de entorno, y el script exige
  escribir el host exacto del proyecto para confirmar. **No ejecutar contra remoto sin autorización.**

```bash
npm run admin:create          # local: pide email, nombre y contraseña
```

**Manual** (alternativa): Studio/Dashboard → Authentication → *Add user* (marcar *Auto Confirm*)
y luego, en el SQL Editor:
```sql
insert into public.profiles (id, full_name, role)
select id, 'Nombre del administrador', 'admin' from auth.users where email = '<email>';
```

## Secretos

- Frontend: solo `NEXT_PUBLIC_SUPABASE_URL` y la clave **publishable**.
- La **secret key** (`sb_secret_…`, antes `service_role`) no se usa en el frontend. Solo la usan
  scripts locales de mantenimiento/test.
- `.env`, `.env.local`, `.env.test.local` ignorados por Git; solo se versionan los `.env.example`.

## Verificación

| Test | Comando | Qué demuestra |
|---|---|---|
| pgTAP (47 aserciones) | `npm run db:test` | RLS por rol a nivel SQL, restricciones de datos, Storage (subida/carpetas) |
| Integración HTTP (22 verificaciones) | `npm run test:security` | Lo mismo a través de la API real (REST, Auth, Storage), con usuarios temporales; incluye borrado en Storage, MIME no permitidos, registro deshabilitado y autoasignación de rol |

`test:security` aborta si la URL no es `127.0.0.1`/`localhost`: **nunca corre contra producción.**
