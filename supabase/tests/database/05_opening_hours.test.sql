-- =============================================================================
-- Horarios (pgTAP) · `npm run db:test`
-- Horario semanal (site_settings.opening_hours) con validación estricta, horario
-- genérico inicial, días especiales (opening_exceptions) y su RLS: la web ve solo de
-- hoy en adelante; solo el admin escribe y limpia los pasados.
-- Corre dentro de una transacción con ROLLBACK: no deja datos.
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(45);

-- Semana de 9:00 a 23:00 con los días que se pisen en `overrides` ({ "friday": [...] }).
create function pg_temp.week(overrides jsonb default '{}')
returns jsonb
language sql
as $$
  select jsonb_agg(
    jsonb_build_object(
      'day', d,
      'ranges', coalesce(overrides -> d, '[{"open": "09:00", "close": "23:00"}]'::jsonb)
    )
    order by o
  )
  from unnest(array['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'])
    with ordinality as t(d, o);
$$;

-- -----------------------------------------------------------------------------
-- Fixtures (como postgres)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'admin@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-a000-0000000000b2', 'user@test.local',  'authenticated', 'authenticated');
insert into public.profiles (id, full_name, role) values
  ('00000000-0000-4000-a000-0000000000a1', 'Admin de prueba', 'admin');

delete from public.opening_exceptions;
insert into public.opening_exceptions (date, type, ranges, note) values
  (private.today_ar() - 1, 'custom', '[{"open": "10:00", "close": "18:00"}]', 'Ayer'),
  (private.today_ar(),     'closed', null,                                     'Cerrado por lluvia'),
  (private.today_ar() + 1, 'custom', '[{"open": "19:00", "close": "02:00"}]', 'Noche de chicas');

-- =============================================================================
-- 1. ESTRUCTURA Y HORARIO GENÉRICO
-- =============================================================================
select has_table('public', 'opening_exceptions', 'existe public.opening_exceptions');
select col_is_unique('public', 'opening_exceptions', 'date', 'una sola excepción por fecha');
select ok((select relrowsecurity from pg_class where oid = 'public.opening_exceptions'::regclass),
  'RLS activa en opening_exceptions');
select has_function('public', 'purge_past_opening_exceptions', 'existe la limpieza de días pasados');
select ok(private.is_valid_opening_hours((select opening_hours from public.site_settings)),
  'el horario cargado es válido');

-- =============================================================================
-- 2. HORARIO SEMANAL (validación)
-- =============================================================================
select ok(private.is_valid_opening_hours(pg_temp.week()), 'válido: todos los días de 9 a 23');
select ok(private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "09:00", "close": "15:00"}, {"open": "19:00", "close": "01:00"}]}')),
  'válido: dos franjas, la segunda cierra después de medianoche');
select ok(private.is_valid_opening_hours(pg_temp.week('{"monday": []}')),
  'válido: un día sin franjas (cerrado)');
select ok(private.is_valid_opening_hours(pg_temp.week(
  '{"sunday": [{"open": "20:00", "close": "02:00"}]}')),
  'válido: el domingo cierra a las 2 y el lunes abre a las 9');
select ok(not private.is_valid_opening_hours(pg_temp.week() - 6), 'inválido: faltan días');
select ok(not private.is_valid_opening_hours(
  jsonb_set(pg_temp.week(), '{6,day}', '"monday"')), 'inválido: un día repetido');
select ok(not private.is_valid_opening_hours(
  jsonb_set(pg_temp.week(), '{0,day}', '"lunes"')), 'inválido: un día desconocido');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "08:00", "close": "10:00"}, {"open": "11:00", "close": "13:00"}, {"open": "19:00", "close": "23:00"}]}')),
  'inválido: más de 2 franjas');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "09:00", "close": "15:00"}, {"open": "14:00", "close": "20:00"}]}')),
  'inválido: franjas superpuestas');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "19:00", "close": "23:00"}, {"open": "09:00", "close": "15:00"}]}')),
  'inválido: franjas fuera de orden');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "20:00", "close": "02:00"}, {"open": "03:00", "close": "05:00"}]}')),
  'inválido: la franja que cruza la medianoche no es la última');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "09:00", "close": "09:00"}]}')), 'inválido: abre y cierra a la misma hora');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "9:00", "close": "23:00"}]}')), 'inválido: hora sin formato HH:MM');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"friday": [{"open": "09:00", "close": "23:00", "extra": true}]}')), 'inválido: claves de más');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"monday": [{"open": "19:00", "close": "03:00"}], "tuesday": [{"open": "02:00", "close": "10:00"}]}')),
  'inválido: el lunes a la noche pisa la mañana del martes');
select ok(not private.is_valid_opening_hours(pg_temp.week(
  '{"sunday": [{"open": "20:00", "close": "10:00"}]}')),
  'inválido: el domingo a la noche pisa la mañana del lunes');
select throws_ok($$ update public.site_settings set opening_hours = '[{"day": "monday"}]' $$,
  '23514', null, 'la base rechaza un horario inválido (CHECK)');
select lives_ok($$ update public.site_settings set opening_hours = pg_temp.week('{"monday": []}') $$,
  'la base acepta un horario válido');

-- =============================================================================
-- 3. DÍAS ESPECIALES (reglas de datos, como postgres)
-- =============================================================================
select throws_ok($$ insert into public.opening_exceptions (date, type, ranges)
  values (current_date + 30, 'closed', '[{"open": "09:00", "close": "12:00"}]') $$,
  '23514', null, 'cerrado: no lleva franjas');
select throws_ok($$ insert into public.opening_exceptions (date, type) values (current_date + 30, 'custom') $$,
  '23514', null, 'horario distinto: lleva franjas');
select throws_ok($$ insert into public.opening_exceptions (date, type, ranges)
  values (current_date + 30, 'custom', '[]') $$,
  '23514', null, 'horario distinto: al menos una franja');
select throws_ok($$ insert into public.opening_exceptions (date, type) values (current_date + 30, 'otro') $$,
  '23514', null, 'tipo: solo closed o custom');
select throws_ok($$ insert into public.opening_exceptions (date, type, note)
  values (current_date + 30, 'closed', repeat('a', 121)) $$,
  '23514', null, 'nota: máximo 120 caracteres');
select throws_ok($$ insert into public.opening_exceptions (date, type)
  values (private.today_ar(), 'closed') $$,
  '23505', null, 'no puede haber dos excepciones para la misma fecha');

-- =============================================================================
-- 4. VISITANTE (anon)
-- =============================================================================
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is((select array_agg(note order by date) from public.opening_exceptions),
  array['Cerrado por lluvia', 'Noche de chicas'], 'anon: ve solo de hoy en adelante');
select ok((select opening_hours from public.site_settings) is not null, 'anon: lee el horario semanal');
select throws_ok($$ insert into public.opening_exceptions (date, type) values (current_date + 40, 'closed') $$,
  '42501', null, 'anon: NO crea días especiales');
select throws_ok($$ select public.purge_past_opening_exceptions() $$,
  '42501', null, 'anon: NO limpia días pasados');

-- =============================================================================
-- 5. USUARIO AUTENTICADO SIN ROL ADMIN
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000b2","role":"authenticated"}', true);

select is((select count(*)::int from public.opening_exceptions), 2, 'no-admin: ve solo de hoy en adelante');
select throws_ok($$ insert into public.opening_exceptions (date, type) values (current_date + 40, 'closed') $$,
  '42501', null, 'no-admin: NO crea días especiales');
with u as (update public.opening_exceptions set note = 'x' returning 1)
select is(count(*)::int, 0, 'no-admin: NO edita (0 filas)') from u;
select is(public.purge_past_opening_exceptions(), 0, 'no-admin: la limpieza no borra nada');

-- =============================================================================
-- 6. ADMINISTRADOR
-- =============================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-a000-0000000000a1","role":"authenticated"}', true);

select is((select count(*)::int from public.opening_exceptions), 3, 'admin: ve también los pasados');
select lives_ok($$ insert into public.opening_exceptions (date, type, ranges, note)
  values (private.today_ar() + 3, 'custom', '[{"open": "09:00", "close": "13:00"}]', 'Feriado') $$,
  'admin: agrega un día con horario distinto');
with u as (update public.opening_exceptions set note = 'Abierto hasta tarde'
  where date = private.today_ar() + 1 returning 1)
select is(count(*)::int, 1, 'admin: edita la nota') from u;
select is((select updated_at from public.opening_exceptions where date = private.today_ar() + 1),
  now(), 'admin: updated_at se actualiza (trigger)');
select is(public.purge_past_opening_exceptions(), 1, 'admin: limpia el día pasado');
select is((select count(*)::int from public.opening_exceptions where date < private.today_ar()), 0,
  'admin: ya no quedan días pasados');
with d as (delete from public.opening_exceptions where note = 'Feriado' returning 1)
select is(count(*)::int, 1, 'admin: elimina un día especial') from d;
select lives_ok($$ update public.site_settings
  set opening_hours = pg_temp.week('{"sunday": []}') where singleton $$,
  'admin: cambia el horario semanal');

select * from finish();
rollback;
