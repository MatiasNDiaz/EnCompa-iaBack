-- =============================================================================
-- Plato del día (pgTAP) · `npm run db:test`
-- Estructura, 3 filas fijas (una por momento), regla "publicar = foto + título",
-- RLS (anon solo ve publicados; el admin edita pero no crea ni borra) y Storage specials/.
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

-- Estado conocido: mañana publicado, mediodía con datos pero sin publicar, noche vacía.
update public.daily_specials set image_path = null, title = null, subtitle = null, body = null,
  price = null, ingredients = null, is_published = false;
update public.daily_specials
  set image_path = 'specials/manana.webp', title = 'Tostado de campo', is_published = true
  where moment = 'morning';
update public.daily_specials
  set image_path = 'specials/mediodia.webp', title = 'Risotto de hongos'
  where moment = 'midday';

-- =============================================================================
-- 1. ESTRUCTURA
-- =============================================================================
select has_table('public', 'daily_specials', 'existe public.daily_specials');
select col_type_is('public', 'daily_specials', 'moment', 'day_moment', 'moment usa el enum day_moment');
select col_is_unique('public', 'daily_specials', 'moment', 'moment es único (un plato por momento)');
select col_type_is('public', 'daily_specials', 'price', 'numeric(10,2)', 'price es numeric(10,2)');
select col_type_is('public', 'daily_specials', 'ingredients', 'text', 'ingredients es texto libre (migración 16)');
select col_default_is('public', 'daily_specials', 'is_published', 'false', 'is_published es false por defecto');
select is((select array_agg(moment::text order by moment) from public.daily_specials),
  array['morning', 'midday', 'evening'], 'existen las 3 filas: mañana, mediodía y tarde/noche');
select ok((select relrowsecurity from pg_class where oid = 'public.daily_specials'::regclass),
  'RLS activa en daily_specials');

-- =============================================================================
-- 2. REGLAS DE DATOS (como postgres)
-- =============================================================================
select throws_ok($$ insert into public.daily_specials (moment) values ('morning') $$,
  '23505', null, 'no puede haber dos filas para el mismo momento');
select throws_ok($$ update public.daily_specials set image_path = null where moment = 'morning' $$,
  '23514', null, 'publicado: no puede quedar sin foto');
select throws_ok($$ update public.daily_specials set title = null where moment = 'morning' $$,
  '23514', null, 'publicado: no puede quedar sin título');
select throws_ok($$ update public.daily_specials set is_published = true where moment = 'evening' $$,
  '23514', null, 'no se publica un espacio vacío (sin foto ni título)');
select throws_ok($$ update public.daily_specials set title = '   ' where moment = 'midday' $$,
  '23514', null, 'el título no puede ser solo espacios');
select throws_ok($$ update public.daily_specials set price = -1 where moment = 'midday' $$,
  '23514', null, 'el precio no puede ser negativo');
select throws_ok($$ update public.daily_specials set image_path = 'products/x.webp' where moment = 'midday' $$,
  '23514', null, 'la foto tiene que estar en specials/');
select throws_ok($$ update public.daily_specials set ingredients = repeat('a', 501) where moment = 'midday' $$,
  '23514', null, 'ingredientes: máximo 500 caracteres');
select lives_ok($$ update public.daily_specials set ingredients = 'Arroz carnaroli, hongos de la zona y parmesano.', price = 12500
  where moment = 'midday' $$, 'ingredientes (texto) y precio válidos');

-- =============================================================================
-- 3. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is((select array_agg(moment::text) from public.daily_specials), array['morning'],
  'anon: ve SOLO los publicados');
select throws_ok($$ update public.daily_specials set title = 'x' where moment = 'morning' $$,
  '42501', null, 'anon: NO edita');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'specials/anon.webp') $$,
  '42501', null, 'anon: NO sube fotos a specials/');

-- =============================================================================
-- 4. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

select is((select count(*)::int from public.daily_specials), 1, 'no-admin: ve solo los publicados');
with u as (update public.daily_specials set is_published = false returning 1)
select is(count(*)::int, 0, 'no-admin: NO edita (0 filas)') from u;

-- =============================================================================
-- 5. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

select is((select count(*)::int from public.daily_specials), 3, 'admin: ve los 3 (también sin publicar)');
with u as (update public.daily_specials set is_published = true where moment = 'midday' returning 1)
select is(count(*)::int, 1, 'admin: publica el mediodía') from u;
select is((select updated_at from public.daily_specials where moment = 'midday'), now(),
  'admin: updated_at se actualiza (trigger)');
with u as (update public.daily_specials set is_published = false where moment = 'morning' returning 1)
select is(count(*)::int, 1, 'admin: quita de la web la mañana') from u;
select throws_ok($$ insert into public.daily_specials (moment) values ('evening') $$,
  '42501', null, 'admin: NO crea filas nuevas (son fijas)');
select throws_ok($$ delete from public.daily_specials where moment = 'evening' $$,
  '42501', null, 'admin: NO borra filas');
select throws_ok($$ update public.daily_specials set moment = 'evening' where moment = 'midday' $$,
  '23505', null, 'admin: no puede duplicar un momento');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'specials/admin.webp') $$,
  'admin: sube fotos a specials/');

-- Lo que ve anon después de los cambios del admin.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is((select array_agg(moment::text) from public.daily_specials), array['midday'],
  'anon: ve el recién publicado y deja de ver el quitado');

select * from finish();
rollback;
