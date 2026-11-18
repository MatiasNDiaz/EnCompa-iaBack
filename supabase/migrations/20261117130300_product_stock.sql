-- =============================================================================
-- En Compañía · 13 · "Sin stock por hoy"
--
-- Dos campos con significados distintos:
--   · is_available = false   → producto OCULTO (p. ej. de temporada). La RLS no lo
--                              entrega al público. Lo vuelve a mostrar el admin.
--   · out_of_stock_on = hoy  → se sigue viendo en la carta, atenuado y con "Sin stock
--                              hoy". Vuelve SOLO al día siguiente (o antes, si el admin
--                              lo marca "Disponible otra vez" → NULL).
-- "Hoy" es la fecha en America/Argentina/Cordoba, no la del servidor.
--
-- La RLS pública no cambia: ya filtra solo por is_available, así que los productos
-- sin stock se leen (para mostrarlos atenuados) y los ocultos no.
-- =============================================================================

alter table public.products add column out_of_stock_on date;

comment on column public.products.out_of_stock_on is
  'Fecha (hora de Córdoba) en que se marcó "Sin stock hoy". Solo cuenta si es HOY: al día siguiente vuelve solo.';

-- Fecha de hoy en el bar.
create function private.today_ar()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Argentina/Cordoba')::date;
$$;

comment on function private.today_ar() is 'Fecha de hoy en la hora de Córdoba (America/Argentina/Cordoba).';

-- Campo calculado de PostgREST: `select=*,out_of_stock_today` sobre products.
-- SECURITY INVOKER (por defecto): solo calcula sobre la fila que el rol ya puede leer.
create function public.out_of_stock_today(product public.products)
returns boolean
language sql
stable
set search_path = ''
as $$
  select product.out_of_stock_on is not null
     and product.out_of_stock_on = private.today_ar();
$$;

comment on function public.out_of_stock_today(public.products) is
  'true si el producto está marcado "Sin stock hoy" (fecha de hoy en Córdoba).';

revoke all on function private.today_ar() from public, anon, authenticated;
grant execute on function private.today_ar() to anon, authenticated, service_role;

revoke all on function public.out_of_stock_today(public.products) from public, anon, authenticated;
grant execute on function public.out_of_stock_today(public.products) to anon, authenticated, service_role;
