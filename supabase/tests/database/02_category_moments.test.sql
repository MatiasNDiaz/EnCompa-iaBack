-- =============================================================================
-- Momentos del día por categoría (pgTAP) · `npm run db:test`
-- Herencia padre → subcategoría, filtro por momento y seguridad de escritura.
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

-- Padre con momentos; una hija SIN momentos (hereda) y otra CON momentos propios.
insert into public.categories (id, name, slug, moments) values
  ('00000000-0000-4000-d000-000000000001', 'Test padre', 'test-padre', '{evening}');
insert into public.categories (id, parent_id, name, slug, moments) values
  ('00000000-0000-4000-d000-000000000002', '00000000-0000-4000-d000-000000000001', 'Test hereda', 'test-hereda', '{}'),
  ('00000000-0000-4000-d000-000000000003', '00000000-0000-4000-d000-000000000001', 'Test propia', 'test-propia', '{morning}');
-- Categoría inactiva con momentos: no debe filtrarse a anon por la vista.
insert into public.categories (id, name, slug, is_active, moments) values
  ('00000000-0000-4000-d000-000000000004', 'Test inactiva', 'test-mom-inactiva', false, '{morning}');
-- Sin indicar moments: toma el default.
insert into public.categories (name, slug) values ('Test sin momentos', 'test-sin-momentos');

-- =============================================================================
-- 1. ESTRUCTURA
-- =============================================================================
select has_type('public', 'day_moment', 'existe el enum day_moment');
select enum_has_labels('public', 'day_moment', array['morning', 'midday', 'evening'],
  'day_moment tiene morning, midday y evening (en ese orden)');
select col_type_is('public', 'categories', 'moments', 'public', 'day_moment[]',
  'categories.moments es day_moment[]');
select col_not_null('public', 'categories', 'moments', 'categories.moments es NOT NULL');
select col_has_default('public', 'categories', 'moments', 'categories.moments tiene default');
select is((select moments from public.categories where slug = 'test-sin-momentos'),
  '{}'::public.day_moment[], 'el default de moments es vacío');
select has_view('public', 'categories_with_moments', 'existe la vista categories_with_moments');
select ok(
  (select reloptions from pg_class where oid = 'public.categories_with_moments'::regclass)
    @> array['security_invoker=true'],
  'la vista es security_invoker (respeta la RLS de categories)');

-- =============================================================================
-- 2. HERENCIA Y FILTRO (como postgres)
-- =============================================================================
select is((select effective_moments from public.categories_with_moments where slug = 'test-hereda'),
  '{evening}'::public.day_moment[], 'subcategoría sin momentos HEREDA los del padre');
select is((select effective_moments from public.categories_with_moments where slug = 'test-propia'),
  '{morning}'::public.day_moment[], 'subcategoría con momentos propios NO hereda');
select is((select effective_moments from public.categories_with_moments where slug = 'test-padre'),
  '{evening}'::public.day_moment[], 'categoría raíz: momentos efectivos = propios');
select is((select effective_moments from public.categories_with_moments where slug = 'menu-del-dia'),
  '{midday}'::public.day_moment[], 'seed: Menú del día hereda mediodía de Almuerzos');

select ok(exists(select 1 from public.categories_with_moments
                 where slug = 'desayunos-y-brunch' and 'morning' = any(effective_moments)),
  'filtro mañana: incluye Desayunos & Brunch');
select ok(not exists(select 1 from public.categories_with_moments
                     where slug = 'cocteleria' and 'morning' = any(effective_moments)),
  'filtro mañana: NO incluye Cocktails');
select ok(not exists(select 1 from public.categories_with_moments
                     where slug = 'sours' and 'morning' = any(effective_moments)),
  'filtro mañana: NO incluye subcategorías de Cocktails (herencia)');
select is(
  (select array_agg(slug::text order by slug) from public.categories_with_moments
   where parent_id is null and 'evening' = any(effective_moments)
     and slug in ('cocteleria', 'tapeo-y-para-compartir', 'desayunos-y-brunch', 'almuerzos')),
  array['cocteleria', 'tapeo-y-para-compartir'],
  'filtro tarde/noche: Cocktails y Tapeo, sin Desayunos ni Almuerzos');

-- =============================================================================
-- 3. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is(
  (select count(*)::int from public.categories_with_moments),
  (select count(*)::int from public.categories),
  'anon: la vista devuelve las mismas filas que categories (misma RLS)');
select is((select count(*)::int from public.categories_with_moments where slug = 'test-mom-inactiva'), 0,
  'anon: la vista NO expone categorías inactivas');
select throws_ok($$ update public.categories set moments = '{morning}' $$,
  '42501', null, 'anon: NO modifica moments');
-- Dos defensas: la vista no es actualizable (tiene un join) y además no tiene GRANT de escritura.
select throws_ok($$ update public.categories_with_moments set moments = '{morning}' $$,
  '55000', null, 'anon: NO escribe a través de la vista (no actualizable)');
select ok(not has_table_privilege('anon', 'public.categories_with_moments', 'INSERT, UPDATE, DELETE'),
  'anon: sin privilegios de escritura sobre la vista');

-- =============================================================================
-- 4. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

with u as (update public.categories set moments = '{morning}' where slug = 'cocteleria' returning 1)
select is(count(*)::int, 0, 'no-admin: NO modifica moments (0 filas afectadas)') from u;
select throws_ok($$ update public.categories_with_moments set moments = '{morning}' $$,
  '55000', null, 'no-admin: NO escribe a través de la vista (no actualizable)');
select ok(not has_table_privilege('authenticated', 'public.categories_with_moments', 'INSERT, UPDATE, DELETE'),
  'authenticated: sin privilegios de escritura sobre la vista');

-- =============================================================================
-- 5. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

with u as (update public.categories set moments = '{morning,evening}' where slug = 'test-padre' returning 1)
select is(count(*)::int, 1, 'admin: modifica moments') from u;
select is((select effective_moments from public.categories_with_moments where slug = 'test-hereda'),
  '{morning,evening}'::public.day_moment[], 'admin: la herencia refleja el cambio del padre');

reset role;
select * from finish();
rollback;
