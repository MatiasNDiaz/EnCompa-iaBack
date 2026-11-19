-- =============================================================================
-- Novedades (pgTAP) · `npm run db:test`
-- Estructura, reglas de medios (imagen sin portada; video con portada), límites de
-- texto, slug único, published_at (primera publicación), RLS (anon solo publicadas;
-- solo el admin escribe) y Storage news/.
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(43);

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

delete from public.news_posts;
insert into public.news_posts (title, slug, description, media_type, media_path, is_published, published_at) values
  ('Noche de chicas', 'noche-de-chicas', 'Tragos y tapeo.', 'image', 'news/noche.webp', true, '2026-01-10 20:00+00'),
  ('Borrador', 'borrador', 'Todavía no.', 'image', 'news/borrador.webp', false, null);

-- =============================================================================
-- 1. ESTRUCTURA
-- =============================================================================
select has_table('public', 'news_posts', 'existe public.news_posts');
select col_is_unique('public', 'news_posts', 'slug', 'el slug es único');
select col_not_null('public', 'news_posts', 'description', 'la descripción es obligatoria');
select col_not_null('public', 'news_posts', 'media_path', 'el archivo es obligatorio');
select col_default_is('public', 'news_posts', 'is_published', 'false', 'is_published es false por defecto');
select ok((select relrowsecurity from pg_class where oid = 'public.news_posts'::regclass),
  'RLS activa en news_posts');

-- =============================================================================
-- 2. REGLAS DE DATOS (como postgres)
-- =============================================================================
select lives_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path, poster_path)
  values ('Video', 'video', 'Con portada.', 'video', 'news/clip.mp4', 'news/clip-portada.webp') $$,
  'video con portada: válido');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Video', 'video-2', 'Sin portada.', 'video', 'news/clip.mp4') $$,
  '23514', null, 'video: la portada es obligatoria');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path, poster_path)
  values ('Imagen', 'imagen-2', 'Con portada.', 'image', 'news/a.webp', 'news/b.webp') $$,
  '23514', null, 'imagen: no lleva portada');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Imagen', 'imagen-3', 'Texto.', 'image', 'news/clip.mp4') $$,
  '23514', null, 'imagen: el archivo tiene que ser una imagen');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Imagen', 'imagen-4', 'Texto.', 'image', 'products/a.webp') $$,
  '23514', null, 'el archivo tiene que estar en news/');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path, poster_path)
  values ('Video', 'video-3', 'Texto.', 'video', 'news/clip.mp4', 'gallery/p.webp') $$,
  '23514', null, 'la portada también tiene que estar en news/');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('   ', 'vacio', 'Texto.', 'image', 'news/a.webp') $$,
  '23514', null, 'el título no puede estar vacío');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values (repeat('a', 121), 'largo', 'Texto.', 'image', 'news/a.webp') $$,
  '23514', null, 'título: máximo 120 caracteres');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Largo', 'largo-2', repeat('a', 1501), 'image', 'news/a.webp') $$,
  '23514', null, 'descripción: máximo 1500 caracteres');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Sin texto', 'sin-texto', '  ', 'image', 'news/a.webp') $$,
  '23514', null, 'la descripción no puede estar vacía');
select throws_ok($$ insert into public.news_posts (title, slug, description, closing_message, media_type, media_path)
  values ('Final', 'final', 'Texto.', repeat('a', 201), 'image', 'news/a.webp') $$,
  '23514', null, 'mensaje final: máximo 200 caracteres');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Slug', 'Hola Mundo', 'Texto.', 'image', 'news/a.webp') $$,
  '23514', null, 'el slug solo admite minúsculas, números y guiones');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Otra', 'noche-de-chicas', 'Texto.', 'image', 'news/a.webp') $$,
  '23505', null, 'no puede haber dos novedades con el mismo slug');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('Tipo', 'tipo', 'Texto.', 'audio', 'news/a.webp') $$,
  '23514', null, 'tipo: solo imagen o video');
select col_default_is('public', 'news_posts', 'card_layout', 'split'::text,
  'diseño de la tarjeta: "Dividida" por defecto');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path, card_layout)
  values ('Diseño', 'diseno', 'Texto.', 'image', 'news/a.webp', 'mosaico') $$,
  '23514', null, 'diseño de la tarjeta: solo split, stacked o curved');
select lives_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path, card_layout)
  values ('Curva', 'curva', 'Texto.', 'image', 'news/a.webp', 'curved') $$,
  'diseño de la tarjeta: curved es válido');
delete from public.news_posts where slug = 'curva';

-- published_at: se completa al publicar y se conserva al ocultar y volver a publicar.
update public.news_posts set is_published = true where slug = 'borrador';
select is((select published_at from public.news_posts where slug = 'borrador'), now(),
  'al publicar se completa published_at');
update public.news_posts set is_published = false where slug = 'noche-de-chicas';
update public.news_posts set is_published = true where slug = 'noche-de-chicas';
select is((select published_at from public.news_posts where slug = 'noche-de-chicas'),
  '2026-01-10 20:00+00'::timestamptz, 'ocultar y volver a publicar no cambia published_at');
update public.news_posts set is_published = false where slug = 'borrador';

-- =============================================================================
-- 3. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is((select array_agg(slug::text order by slug) from public.news_posts), array['noche-de-chicas'],
  'anon: ve SOLO las publicadas');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('x', 'anon', 'x', 'image', 'news/a.webp') $$,
  '42501', null, 'anon: NO crea novedades');
select throws_ok($$ update public.news_posts set title = 'x' $$,
  '42501', null, 'anon: NO edita');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'news/anon.webp') $$,
  '42501', null, 'anon: NO sube archivos a news/');

-- =============================================================================
-- 4. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

select is((select count(*)::int from public.news_posts), 1, 'no-admin: ve solo las publicadas');
select throws_ok($$ insert into public.news_posts (title, slug, description, media_type, media_path)
  values ('x', 'user', 'x', 'image', 'news/a.webp') $$,
  '42501', null, 'no-admin: NO crea novedades');
with u as (update public.news_posts set title = 'x' returning 1)
select is(count(*)::int, 0, 'no-admin: NO edita (0 filas)') from u;
with d as (delete from public.news_posts returning 1)
select is(count(*)::int, 0, 'no-admin: NO borra (0 filas)') from d;
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'news/user.webp') $$,
  '42501', null, 'no-admin: NO sube archivos a news/');

-- =============================================================================
-- 5. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

select is((select count(*)::int from public.news_posts), 3, 'admin: ve todas (también los borradores)');
select lives_ok($$ insert into public.news_posts (title, slug, description, closing_message, media_type, media_path, event_date, is_published)
  values ('Promo', 'promo', 'Dos por uno.', '¡Te esperamos!', 'image', 'news/promo.webp', current_date + 7, true) $$,
  'admin: crea y publica una novedad');
select ok((select published_at is not null from public.news_posts where slug = 'promo'),
  'admin: la publicada tiene published_at');
with u as (update public.news_posts set is_published = false where slug = 'promo' returning 1)
select is(count(*)::int, 1, 'admin: oculta una novedad') from u;
select is((select updated_at from public.news_posts where slug = 'promo'), now(),
  'admin: updated_at se actualiza (trigger)');
with d as (delete from public.news_posts where slug = 'promo' returning 1)
select is(count(*)::int, 1, 'admin: elimina una novedad') from d;
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'news/admin.webp') $$,
  'admin: sube imágenes a news/');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'news/admin.mp4') $$,
  'admin: sube videos a news/');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('site-media', 'novedades/x.webp') $$,
  '42501', null, 'admin: NO sube fuera de las carpetas permitidas');

select * from finish();
rollback;
