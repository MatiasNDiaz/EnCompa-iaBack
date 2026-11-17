-- =============================================================================
-- En Compañía · 02 · Funciones de autorización
-- Va ANTES de rls_policies porque las políticas las referencian.
--
-- Decisión: las funciones viven en el esquema `private` (no expuesto por la
-- Data API) en lugar de `public`. Así no se pueden invocar como RPC desde
-- /rest/v1/rpc/* y el linter de Supabase no las marca como "security definer
-- ejecutable por anon/authenticated en un esquema expuesto".
-- =============================================================================

-- ¿El usuario de la sesión actual es administrador?
-- SECURITY DEFINER: lee `profiles` saltando su RLS → evita recursión de políticas
-- (las políticas de otras tablas llaman a esta función, y esta no dispara RLS).
-- search_path vacío + nombres calificados: inmune a secuestro de search_path.
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'admin'
  );
$$;

-- ¿La categoría es visible para el público? Activa y, si es subcategoría,
-- con la categoría padre también activa.
-- SECURITY DEFINER: la política de `categories` necesita consultar `categories`
-- (el padre). Hacerlo dentro de la política causaría recursión infinita de RLS.
create function private.is_category_visible(category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.categories c
    left join public.categories p on p.id = c.parent_id
    where c.id = category_id
      and c.is_active
      and (c.parent_id is null or p.is_active)
  );
$$;

-- -----------------------------------------------------------------------------
-- Privilegios: mínimo necesario.
-- Las políticas se evalúan con los privilegios del rol que consulta, así que
-- necesita USAGE sobre el esquema y EXECUTE sobre las funciones que usa.
-- -----------------------------------------------------------------------------
revoke all on all functions in schema private from public, anon, authenticated;

grant usage on schema private to anon, authenticated;

-- Solo usuarios autenticados preguntan si son admin. anon no lo necesita
-- (sus políticas no lo usan).
grant execute on function private.is_admin() to authenticated;

-- Lecturas públicas de la carta.
grant execute on function private.is_category_visible(uuid) to anon, authenticated;

-- Los CHECK de paths se evalúan al escribir: admin (`authenticated`) y scripts
-- de mantenimiento desde un entorno confiable (`service_role`).
grant usage on schema private to service_role;
grant execute on function private.is_image_path(text, text) to authenticated, service_role;
grant execute on function private.is_video_path(text, text) to authenticated, service_role;
