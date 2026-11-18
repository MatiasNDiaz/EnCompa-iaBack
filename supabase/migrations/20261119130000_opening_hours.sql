-- =============================================================================
-- En Compañía · 21 · Horarios editables desde el panel
--
-- 1. Horario semanal: se reutiliza site_settings.opening_hours (jsonb), ahora con
--    validación estricta en la base (antes solo se exigía que fuera un arreglo):
--      [{ "day": "monday", "ranges": [{ "open": "09:00", "close": "15:00" }, …] }, …]
--    · Los 7 días, sin repetir. Día sin franjas = cerrado.
--    · Hasta 2 franjas por día, en orden y sin superponerse.
--    · Una franja con cierre menor que la apertura termina al día siguiente
--      (ej. 19:00 → 01:00). Solo puede ser la última del día y no puede pisar la
--      primera franja del día siguiente.
-- 2. Días especiales (opening_exceptions): una fecha cerrada o con horario distinto,
--    con una nota opcional que se ve en la web. Reemplaza al horario semanal ese día.
--    La web ve solo los de hoy en adelante (hora de Córdoba); el admin ve todos.
-- 3. Horario genérico inicial (todos los días de 9:00 a 23:00), solo si no hay uno.
--
-- Zona horaria del local: America/Argentina/Cordoba.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Funciones de validación (un CHECK no admite subconsultas)
-- -----------------------------------------------------------------------------

-- "HH:MM" → minutos desde la medianoche; NULL si el formato no es válido.
create function private.opening_time_minutes(value text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when value ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      then split_part(value, ':', 1)::integer * 60 + split_part(value, ':', 2)::integer
  end;
$$;

-- Franjas de un día: entre min_count y 2, cada una { open, close } (solo esas claves),
-- en orden, sin superponerse; la que cruza la medianoche va última.
create function private.is_valid_opening_ranges(ranges jsonb, min_count integer default 0)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  item jsonb;
  open_at integer;
  close_at integer;
  previous_end integer;
  crossed_midnight boolean := false;
begin
  if ranges is null or jsonb_typeof(ranges) <> 'array' then
    return false;
  end if;
  if jsonb_array_length(ranges) not between min_count and 2 then
    return false;
  end if;

  for item in select value from jsonb_array_elements(ranges) loop
    if jsonb_typeof(item) <> 'object'
       or (select array_agg(k order by k) from jsonb_object_keys(item) as k)
            is distinct from array['close', 'open']
       or jsonb_typeof(item -> 'open') <> 'string'
       or jsonb_typeof(item -> 'close') <> 'string' then
      return false;
    end if;

    open_at := private.opening_time_minutes(item ->> 'open');
    close_at := private.opening_time_minutes(item ->> 'close');
    if open_at is null or close_at is null or open_at = close_at or crossed_midnight then
      return false;
    end if;

    if close_at < open_at then
      close_at := close_at + 1440;
      crossed_midnight := true;
    end if;

    if previous_end is not null and open_at < previous_end then
      return false;
    end if;
    previous_end := close_at;
  end loop;

  return true;
end;
$$;

-- Horario semanal completo: los 7 días una sola vez, cada uno con franjas válidas, y la
-- franja que cruza la medianoche no pisa la primera del día siguiente.
create function private.is_valid_opening_hours(hours jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  week constant text[] := array[
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ];
  item jsonb;
  position integer;
  first_open integer[] := array_fill(null::integer, array[7]);
  spill_until integer[] := array_fill(null::integer, array[7]);
  last_range jsonb;
  open_at integer;
  close_at integer;
  next_day integer;
begin
  if hours is null or jsonb_typeof(hours) <> 'array' or jsonb_array_length(hours) <> 7 then
    return false;
  end if;

  for item in select value from jsonb_array_elements(hours) loop
    if jsonb_typeof(item) <> 'object'
       or (select array_agg(k order by k) from jsonb_object_keys(item) as k)
            is distinct from array['day', 'ranges']
       or jsonb_typeof(item -> 'day') <> 'string' then
      return false;
    end if;

    position := array_position(week, item ->> 'day');
    if position is null or first_open[position] is not null or spill_until[position] is not null then
      return false; -- día desconocido o repetido
    end if;
    if not private.is_valid_opening_ranges(item -> 'ranges', 0) then
      return false;
    end if;

    -- Marca el día como visto (-1 = cerrado) y guarda lo necesario para el cruce.
    first_open[position] := coalesce(
      private.opening_time_minutes(item -> 'ranges' -> 0 ->> 'open'), -1
    );
    spill_until[position] := -1;
    if jsonb_array_length(item -> 'ranges') > 0 then
      last_range := item -> 'ranges' -> (jsonb_array_length(item -> 'ranges') - 1);
      open_at := private.opening_time_minutes(last_range ->> 'open');
      close_at := private.opening_time_minutes(last_range ->> 'close');
      if close_at < open_at then
        spill_until[position] := close_at;
      end if;
    end if;
  end loop;

  for position in 1..7 loop
    next_day := position % 7 + 1;
    if spill_until[position] >= 0
       and first_open[next_day] >= 0
       and first_open[next_day] < spill_until[position] then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

-- Fecha de hoy en el local (para "de hoy en adelante").
create function private.today_in_cordoba()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Argentina/Cordoba')::date;
$$;

comment on function private.is_valid_opening_ranges(jsonb, integer) is
  'Franjas de un día: hasta 2 { open, close } HH:MM, en orden y sin superponerse; la que cruza la medianoche va última.';
comment on function private.is_valid_opening_hours(jsonb) is
  'Horario semanal: los 7 días una vez, franjas válidas y sin pisar el día siguiente.';
comment on function private.today_in_cordoba() is 'Fecha actual en America/Argentina/Cordoba.';

revoke all on function private.opening_time_minutes(text) from public, anon, authenticated;
revoke all on function private.is_valid_opening_ranges(jsonb, integer) from public, anon, authenticated;
revoke all on function private.is_valid_opening_hours(jsonb) from public, anon, authenticated;
revoke all on function private.today_in_cordoba() from public, anon, authenticated;
grant execute on function private.opening_time_minutes(text) to authenticated, service_role;
grant execute on function private.is_valid_opening_ranges(jsonb, integer) to authenticated, service_role;
grant execute on function private.is_valid_opening_hours(jsonb) to authenticated, service_role;
-- La usa la política de lectura pública de opening_exceptions.
grant execute on function private.today_in_cordoba() to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1 y 3. Horario semanal: genérico inicial + validación estricta
-- -----------------------------------------------------------------------------
update public.site_settings
set opening_hours = (
  select jsonb_agg(
    jsonb_build_object(
      'day', day,
      'ranges', jsonb_build_array(jsonb_build_object('open', '09:00', 'close', '23:00'))
    )
    order by ordinal
  )
  from unnest(array[
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ]) with ordinality as week(day, ordinal)
)
where singleton and opening_hours is null;

alter table public.site_settings drop constraint site_settings_opening_hours_check;
alter table public.site_settings
  add constraint site_settings_opening_hours_check
  check (opening_hours is null or private.is_valid_opening_hours(opening_hours));

comment on column public.site_settings.opening_hours is
  'Horario semanal: [{ day, ranges: [{ open, close }] }] × 7. Sin franjas = cerrado. Cierre < apertura = termina al día siguiente.';

-- -----------------------------------------------------------------------------
-- 2. Días especiales
-- -----------------------------------------------------------------------------
create table public.opening_exceptions (
  id         uuid primary key default gen_random_uuid(),
  date       date not null unique,
  type       text not null check (type in ('closed', 'custom')),
  ranges     jsonb,
  note       text check (char_length(btrim(note)) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint opening_exceptions_ranges check (
    case type
      when 'closed' then ranges is null
      else private.is_valid_opening_ranges(ranges, 1)
    end
  )
);

comment on table public.opening_exceptions is
  'Días especiales: cerrado o con horario distinto. Reemplaza al horario semanal ese día.';
comment on column public.opening_exceptions.note is
  'Opcional. Se ve en la web (ej. "Cerrado por lluvia").';

create trigger opening_exceptions_set_updated_at
  before update on public.opening_exceptions
  for each row execute function private.set_updated_at();

revoke all on table public.opening_exceptions from anon, authenticated;
grant select on table public.opening_exceptions to anon, authenticated;
grant insert, update, delete on table public.opening_exceptions to authenticated;

alter table public.opening_exceptions enable row level security;

create policy "opening_exceptions: lectura pública de hoy en adelante"
  on public.opening_exceptions for select to anon, authenticated
  using (date >= (select private.today_in_cordoba()));

create policy "opening_exceptions: admin lee todo"
  on public.opening_exceptions for select to authenticated
  using ((select private.is_admin()));

create policy "opening_exceptions: admin crea"
  on public.opening_exceptions for insert to authenticated
  with check ((select private.is_admin()));

create policy "opening_exceptions: admin edita"
  on public.opening_exceptions for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "opening_exceptions: admin borra"
  on public.opening_exceptions for delete to authenticated
  using ((select private.is_admin()));

-- Limpieza manual de los días especiales que ya pasaron (desde el panel). SECURITY
-- INVOKER: la RLS decide; quien no es admin borra 0 filas.
create function public.purge_past_opening_exceptions()
returns integer
language sql
security invoker
set search_path = ''
as $$
  with deleted as (
    delete from public.opening_exceptions
    where date < private.today_in_cordoba()
    returning 1
  )
  select count(*)::integer from deleted;
$$;

comment on function public.purge_past_opening_exceptions() is
  'Borra los días especiales anteriores a hoy (hora de Córdoba). Solo surte efecto para el admin (RLS).';

revoke all on function public.purge_past_opening_exceptions() from public, anon;
grant execute on function public.purge_past_opening_exceptions() to authenticated;
