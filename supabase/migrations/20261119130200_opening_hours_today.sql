-- =============================================================================
-- En Compañía · 23 · Horarios: una sola función para "hoy"
--
-- La migración 21 creó private.today_in_cordoba(), igual a private.today_ar()
-- (migración 13, "sin stock por hoy"). Se usa la que ya existía y se borra la nueva:
-- una sola definición de "hoy en el local".
-- =============================================================================

drop policy "opening_exceptions: lectura pública de hoy en adelante" on public.opening_exceptions;
create policy "opening_exceptions: lectura pública de hoy en adelante"
  on public.opening_exceptions for select to anon, authenticated
  using (date >= (select private.today_ar()));

create or replace function public.purge_past_opening_exceptions()
returns integer
language sql
security invoker
set search_path = ''
as $$
  with deleted as (
    delete from public.opening_exceptions
    where date < private.today_ar()
    returning 1
  )
  select count(*)::integer from deleted;
$$;

drop function private.today_in_cordoba();
