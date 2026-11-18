-- =============================================================================
-- En Compañía · 14 · Reordenar secciones de la carta en una sola transacción
--
-- `public.reorder_categories(ids)`: asigna sort_order 0, 1, 2… según el orden del
-- arreglo. Todas las secciones deben ser hermanas (mismo padre, o todas raíz).
--
-- SECURITY INVOKER: corre con los permisos de quien llama, así que la RLS de
-- `categories` sigue siendo la barrera (solo el admin puede actualizar). Además
-- verifica el rol al inicio para dar un error claro. Solo `authenticated` puede
-- ejecutarla (anon no tiene EXECUTE).
-- =============================================================================

create function public.reorder_categories(ids uuid[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  parents int;
  found int;
begin
  if not (select private.is_admin()) then
    raise exception 'Solo el administrador puede reordenar la carta.' using errcode = '42501';
  end if;

  if ids is null or cardinality(ids) = 0 then
    return;
  end if;

  if cardinality(ids) <> (select count(distinct x) from unnest(ids) as t(x)) then
    raise exception 'La lista tiene secciones repetidas.' using errcode = '22023';
  end if;

  select count(*), count(distinct coalesce(parent_id, '00000000-0000-0000-0000-000000000000'))
    into found, parents
  from public.categories
  where id = any (ids);

  if found <> cardinality(ids) then
    raise exception 'Alguna sección no existe.' using errcode = '22023';
  end if;
  if parents > 1 then
    raise exception 'Solo se pueden ordenar secciones del mismo nivel.' using errcode = '22023';
  end if;

  update public.categories c
  set sort_order = t.position - 1
  from unnest(ids) with ordinality as t(id, position)
  where c.id = t.id;
end;
$$;

comment on function public.reorder_categories(uuid[]) is
  'Reordena secciones hermanas de la carta (sort_order = posición en el arreglo). Solo admin.';

revoke all on function public.reorder_categories(uuid[]) from public, anon, authenticated;
grant execute on function public.reorder_categories(uuid[]) to authenticated;
