-- =============================================================================
-- Panel · carta (pgTAP) · `npm run db:test`
-- Banners en la base, "sin stock por hoy", productos ocultos, reordenar secciones
-- y carpetas nuevas de Storage (categories/, specials/).
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(40);

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

-- Sin stock HOY / marcado AYER (hoy ya volvió) / oculto (is_available = false).
update public.products set out_of_stock_on = private.today_ar()     where slug = 'americano';
update public.products set out_of_stock_on = private.today_ar() - 1 where slug = 'espresso';
update public.products set is_available = false, out_of_stock_on = null where slug = 'cortado';

-- =============================================================================
-- 1. BANNERS (estructura y datos iniciales)
-- =============================================================================
select has_column('public', 'categories', 'image_is_illustrative', 'existe categories.image_is_illustrative');
select col_not_null('public', 'categories', 'image_is_illustrative', 'image_is_illustrative es NOT NULL');
select col_default_is('public', 'categories', 'image_is_illustrative', 'false',
  'image_is_illustrative es false por defecto (una foto nueva es del local)');
select has_column('public', 'categories_with_moments', 'image_is_illustrative',
  'la vista de la carta expone image_is_illustrative');
select ok(
  (select reloptions from pg_class where oid = 'public.categories_with_moments'::regclass)
    @> array['security_invoker=true'],
  'la vista sigue siendo security_invoker tras recrearla');
select lives_ok($$ update public.categories set image_path = 'categories/banner-test.webp' where slug = 'postres' $$,
  'banner: acepta una ruta en categories/');
select throws_ok($$ update public.categories set image_path = 'products/banner-test.webp' where slug = 'postres' $$,
  '23514', null, 'banner: rechaza una ruta fuera de categories/');
select throws_ok($$ update public.categories set image_path = 'categories/../x.webp' where slug = 'postres' $$,
  '23514', null, 'banner: rechaza rutas con ../');
select is(
  (select count(*)::int from public.categories
    where parent_id is null and description is not null and btrim(description) <> ''),
  8, 'las 8 secciones raíz tienen el texto del banner');

-- =============================================================================
-- 2. SIN STOCK POR HOY (como postgres)
-- =============================================================================
select has_column('public', 'products', 'out_of_stock_on', 'existe products.out_of_stock_on');
select col_type_is('public', 'products', 'out_of_stock_on', 'date', 'out_of_stock_on es date');
select is(private.today_ar(), (now() at time zone 'America/Argentina/Cordoba')::date,
  'today_ar() es la fecha de hoy en Córdoba');
select is((select public.out_of_stock_today(p) from public.products p where slug = 'americano'), true,
  'marcado HOY → sin stock hoy');
select is((select public.out_of_stock_today(p) from public.products p where slug = 'espresso'), false,
  'marcado AYER → hoy vuelve solo (al día siguiente deja de estar sin stock)');
select is((select public.out_of_stock_today(p) from public.products p where slug = 'doppio'), false,
  'sin marcar → disponible');

-- =============================================================================
-- 3. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is((select count(*)::int from public.products where slug = 'americano'), 1,
  'anon: VE el producto sin stock (se muestra atenuado)');
select is((select out_of_stock_on from public.products where slug = 'americano'), private.today_ar(),
  'anon: lee la fecha de sin stock');
select is((select public.out_of_stock_today(p) from public.products p where slug = 'americano'), true,
  'anon: puede usar el campo calculado out_of_stock_today');
select is((select count(*)::int from public.products where slug = 'cortado'), 0,
  'anon: NO ve el producto oculto');
-- (El valor depende de si corrió `npm run media:banners`: se compara vista vs. tabla.)
select is((select image_is_illustrative from public.categories_with_moments where slug = 'cafeteria'),
  (select image_is_illustrative from public.categories where slug = 'cafeteria'),
  'anon: lee image_is_illustrative desde la vista');
select throws_ok($$ update public.products set out_of_stock_on = null where slug = 'americano' $$,
  '42501', null, 'anon: NO cambia el stock');
select throws_ok($$ select public.reorder_categories(array[(select id from public.categories where slug = 'postres')]) $$,
  '42501', null, 'anon: NO puede reordenar (sin EXECUTE)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'categories/anon.webp') $$,
  '42501', null, 'anon: NO sube banners');

-- =============================================================================
-- 4. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

with u as (update public.products set out_of_stock_on = null where slug = 'americano' returning 1)
select is(count(*)::int, 0, 'no-admin: NO cambia el stock (0 filas)') from u;
with u as (update public.categories set image_is_illustrative = true returning 1)
select is(count(*)::int, 0, 'no-admin: NO cambia banners (0 filas)') from u;
select throws_ok($$ select public.reorder_categories(array[(select id from public.categories where slug = 'postres')]) $$,
  '42501', null, 'no-admin: NO puede reordenar');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'categories/user.webp') $$,
  '42501', null, 'no-admin: NO sube banners');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'specials/user.webp') $$,
  '42501', null, 'no-admin: NO sube fotos del plato del día');

-- =============================================================================
-- 5. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

select is((select count(*)::int from public.products where slug = 'cortado'), 1,
  'admin: ve el producto oculto');
with u as (update public.products set out_of_stock_on = null where slug = 'americano' returning 1)
select is(count(*)::int, 1, 'admin: "Disponible otra vez" (limpia la fecha)') from u;
select is((select public.out_of_stock_today(p) from public.products p where slug = 'americano'), false,
  'admin: tras reactivarlo ya no está sin stock');

-- Reordenar: invertir dos secciones raíz.
select lives_ok(
  $$ select public.reorder_categories(array[
       (select id from public.categories where slug = 'cocteleria'),
       (select id from public.categories where slug = 'cafeteria')]) $$,
  'admin: reordena secciones hermanas');
select is(
  (select array_agg(slug::text order by sort_order) from public.categories where slug in ('cafeteria', 'cocteleria')),
  array['cocteleria', 'cafeteria'], 'admin: el nuevo orden queda guardado');
select throws_ok(
  $$ select public.reorder_categories(array[
       (select id from public.categories where slug = 'cafeteria'),
       (select id from public.categories where slug = 'menu-del-dia')]) $$,
  '22023', null, 'reordenar: rechaza mezclar secciones de distinto nivel');
select throws_ok(
  $$ select public.reorder_categories(array[
       (select id from public.categories where slug = 'cafeteria'),
       (select id from public.categories where slug = 'cafeteria')]) $$,
  '22023', null, 'reordenar: rechaza ids repetidos');
select throws_ok(
  $$ select public.reorder_categories(array['00000000-0000-4000-ffff-000000000000'::uuid]) $$,
  '22023', null, 'reordenar: rechaza una sección inexistente');

select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'categories/admin.webp') $$,
  'admin: sube banners a categories/');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'specials/admin.webp') $$,
  'admin: sube fotos a specials/');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'products/admin2.webp') $$,
  'admin: products/ sigue permitida');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'otros/admin.webp') $$,
  '42501', null, 'admin: sigue sin poder subir fuera de las carpetas permitidas');

select * from finish();
rollback;
