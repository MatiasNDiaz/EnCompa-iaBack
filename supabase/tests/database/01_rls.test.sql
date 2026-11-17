-- =============================================================================
-- Tests de seguridad (pgTAP) · `npm run db:test`
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- Escenarios: visitante (anon), usuario autenticado SIN rol admin, admin.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(47);

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

-- Categoría inactiva con un producto disponible; subcategoría activa de un padre inactivo.
insert into public.categories (id, name, slug, is_active) values
  ('00000000-0000-4000-c000-000000000001', 'Test inactiva', 'test-inactiva', false);
insert into public.categories (id, parent_id, name, slug, is_active) values
  ('00000000-0000-4000-c000-000000000002', '00000000-0000-4000-c000-000000000001', 'Test hija', 'test-hija', true);
insert into public.products (category_id, name, slug) values
  ('00000000-0000-4000-c000-000000000002', 'Producto de categoría oculta', 'test-oculto');
update public.products set is_available = false where slug = 'latte';
insert into public.gallery_items (media_type, title, media_path, category, is_published) values
  ('image', 'Borrador', 'gallery/test-borrador.webp', 'espacio', false);

-- =============================================================================
-- 1. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select ok((select count(*) from public.categories) > 0, 'anon: lee categorías activas');
select is((select count(*)::int from public.categories where slug = 'test-inactiva'), 0,
  'anon: NO ve categorías inactivas');
select is((select count(*)::int from public.categories where slug = 'test-hija'), 0,
  'anon: NO ve subcategorías de un padre inactivo');
select is((select count(*)::int from public.products where slug = 'test-oculto'), 0,
  'anon: NO ve productos de categorías ocultas');
select is((select count(*)::int from public.products where slug = 'latte'), 0,
  'anon: NO ve productos no disponibles');
select is((select count(*)::int from public.products), 67,
  'anon: ve los 67 productos disponibles del seed');
select is((select count(*)::int from public.gallery_items), 0, 'anon: NO ve ítems de galería sin publicar');
select is((select count(*)::int from public.site_content), 13, 'anon: lee el contenido institucional');
select is((select count(*)::int from public.site_settings), 1, 'anon: lee site_settings');
select throws_ok($$ select count(*) from public.profiles $$,
  '42501', null, 'anon: NO tiene acceso a perfiles (sin privilegio SELECT)');

select throws_ok($$ insert into public.categories (name, slug) values ('X', 'x') $$,
  '42501', null, 'anon: NO crea categorías');
select throws_ok($$ update public.products set price = 1 $$,
  '42501', null, 'anon: NO modifica productos');
select throws_ok($$ delete from public.products $$,
  '42501', null, 'anon: NO borra productos');
select throws_ok($$ update public.site_settings set address = 'x' $$,
  '42501', null, 'anon: NO modifica site_settings');
select throws_ok($$ insert into public.profiles (id, role) values ('00000000-0000-4000-a000-0000000000b2', 'admin') $$,
  '42501', null, 'anon: NO crea perfiles');
select throws_ok($$ select private.is_admin() $$,
  '42501', null, 'anon: NO puede ejecutar private.is_admin()');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'products/anon.webp') $$,
  '42501', null, 'anon: NO sube archivos a site-media');

-- =============================================================================
-- 2. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

select is((select private.is_admin()), false, 'no-admin: is_admin() es falso');
select is((select count(*)::int from public.categories where slug = 'test-inactiva'), 0,
  'no-admin: NO ve categorías inactivas');
select throws_ok($$ insert into public.categories (name, slug) values ('X', 'x') $$,
  '42501', null, 'no-admin: NO crea categorías (RLS)');
with u as (update public.products set price = 1 returning 1)
select is(count(*)::int, 0, 'no-admin: NO modifica productos (0 filas afectadas)') from u;
with d as (delete from public.products returning 1)
select is(count(*)::int, 0, 'no-admin: NO borra productos (0 filas afectadas)') from d;
with u as (update public.site_settings set address = 'x' returning 1)
select is(count(*)::int, 0, 'no-admin: NO modifica site_settings') from u;
with u as (update public.site_content set title = 'x' returning 1)
select is(count(*)::int, 0, 'no-admin: NO modifica site_content') from u;
select throws_ok($$ insert into public.profiles (id, role) values ('00000000-0000-4000-a000-0000000000b2', 'admin') $$,
  '42501', null, 'no-admin: NO puede autoasignarse el rol admin');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'products/user.webp') $$,
  '42501', null, 'no-admin: NO sube archivos a site-media');

-- =============================================================================
-- 3. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

select is((select private.is_admin()), true, 'admin: is_admin() es verdadero');
select is((select count(*)::int from public.categories where slug = 'test-inactiva'), 1,
  'admin: ve categorías inactivas');
select is((select count(*)::int from public.gallery_items), 1, 'admin: ve ítems sin publicar');
select is((select count(*)::int from public.profiles), 1, 'admin: ve solo su propio perfil');

select lives_ok($$ insert into public.categories (name, slug) values ('Nueva', 'nueva') $$,
  'admin: crea categorías');
with u as (update public.products set price = 3500 where slug = 'espresso' returning 1)
select is(count(*)::int, 1, 'admin: cambia precios') from u;
select lives_ok($$ update public.site_settings set address = 'Dirección de prueba' $$,
  'admin: modifica site_settings');
select lives_ok($$ delete from public.gallery_items where title = 'Borrador' $$,
  'admin: borra ítems de galería');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'products/admin.webp') $$,
  'admin: sube archivos a una carpeta permitida');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'otros/admin.webp') $$,
  '42501', null, 'admin: NO sube fuera de las carpetas permitidas');

-- Restricciones de datos (aplican incluso al admin)
select throws_ok($$ update public.products set price = -1 where slug = 'espresso' $$,
  '23514', null, 'restricción: precio negativo rechazado');
select throws_ok($$ insert into public.categories (name, slug) values ('Mal', 'Slug Inválido') $$,
  '23514', null, 'restricción: slug con formato inválido rechazado');
select throws_ok($$ insert into public.categories (name, slug) values ('Dup', 'cafeteria') $$,
  '23505', null, 'restricción: slug duplicado rechazado');
select throws_ok($$ delete from public.categories where slug = 'cafes-clasicos' $$,
  '23503', null, 'restricción: NO se borra una categoría con productos (RESTRICT)');
select throws_ok($$ delete from public.categories where slug = 'cafeteria' $$,
  '23503', null, 'restricción: NO se borra una categoría con subcategorías (RESTRICT)');
select throws_ok(
  $$ insert into public.categories (parent_id, name, slug)
     select id, 'Nieta', 'nieta' from public.categories where slug = 'cafes-clasicos' $$,
  '23514', null, 'restricción: un solo nivel de subcategorías');
select throws_ok($$ update public.products set image_path = '../../etc/passwd' where slug = 'espresso' $$,
  '23514', null, 'restricción: path de imagen inválido rechazado');
select throws_ok($$ update public.site_content set items = '[]'::jsonb where section = 'mission' $$,
  '23514', null, 'restricción: items solo en la sección values');
select throws_ok($$ insert into public.gallery_items (media_type, title, media_path, category) values ('image', 'X', 'gallery/x.mp4', 'espacio') $$,
  '23514', null, 'restricción: una imagen no puede apuntar a un archivo de video');
select throws_ok($$ insert into public.site_settings (business_name) values ('Otra') $$,
  '42501', null, 'site_settings: no se puede crear una segunda fila');

-- Trigger updated_at
reset role;
select ok(
  (select updated_at > created_at or updated_at = now() from public.products where slug = 'espresso'),
  'trigger: updated_at se actualiza al modificar');

select * from finish();
rollback;
