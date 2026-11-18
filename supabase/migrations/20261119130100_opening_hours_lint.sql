-- =============================================================================
-- En Compañía · 22 · Horarios: ajuste de lint
--
-- private.is_valid_opening_hours usaba una variable llamada `position`, que tapa a la
-- función del mismo nombre (aviso de `supabase db lint`). Misma lógica, variable
-- renombrada a `day_index`. No cambia ningún resultado.
-- =============================================================================

create or replace function private.is_valid_opening_hours(hours jsonb)
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
  day_index integer;
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

    day_index := array_position(week, item ->> 'day');
    if day_index is null or first_open[day_index] is not null or spill_until[day_index] is not null then
      return false; -- día desconocido o repetido
    end if;
    if not private.is_valid_opening_ranges(item -> 'ranges', 0) then
      return false;
    end if;

    -- Marca el día como visto (-1 = cerrado) y guarda lo necesario para el cruce.
    first_open[day_index] := coalesce(
      private.opening_time_minutes(item -> 'ranges' -> 0 ->> 'open'), -1
    );
    spill_until[day_index] := -1;
    if jsonb_array_length(item -> 'ranges') > 0 then
      last_range := item -> 'ranges' -> (jsonb_array_length(item -> 'ranges') - 1);
      open_at := private.opening_time_minutes(last_range ->> 'open');
      close_at := private.opening_time_minutes(last_range ->> 'close');
      if close_at < open_at then
        spill_until[day_index] := close_at;
      end if;
    end if;
  end loop;

  for current_day in 1..7 loop
    next_day := current_day % 7 + 1;
    if spill_until[current_day] >= 0
       and first_open[next_day] >= 0
       and first_open[next_day] < spill_until[current_day] then
      return false;
    end if;
  end loop;

  return true;
end;
$$;
