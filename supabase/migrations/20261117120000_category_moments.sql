-- =============================================================================
-- En Compañía · Momentos del día por categoría (mañana, mediodía, tarde/noche)
--
-- Modelo (Opción A): cada categoría declara en qué momentos se sirve.
--   · categories.moments: momentos PROPIOS. '{}' = sin asignar.
--   · Una subcategoría sin momentos propios HEREDA los de su categoría padre.
--   · Sin excepciones por producto: un producto aparece en los momentos de su categoría.
--
-- La herencia se resuelve en UN solo lugar: la vista `public.categories_with_moments`
-- (columna `effective_moments`). El front la usa para leer la carta.
--
-- Seguridad: la vista es `security_invoker`, así que aplica la RLS de `categories`
-- con los permisos de quien consulta (anon solo ve categorías visibles). Escribir
-- `moments` queda cubierto por los GRANT y políticas existentes de `categories`
-- (solo el admin). La vista solo recibe SELECT.
-- =============================================================================

create type public.day_moment as enum ('morning', 'midday', 'evening');
comment on type public.day_moment is
  'Momento del día en que se sirve una categoría. En la URL: manana, mediodia, tarde-noche.';

alter table public.categories
  add column moments public.day_moment[] not null default '{}';

comment on column public.categories.moments is
  'Momentos propios de la categoría. Vacío en una subcategoría = hereda los del padre. '
  'Vacío en una categoría raíz = sin momento asignado (solo aparece en la carta completa).';

create view public.categories_with_moments
with (security_invoker = true) as
select
  c.id,
  c.parent_id,
  c.name,
  c.slug,
  c.description,
  c.image_path,
  c.sort_order,
  c.is_active,
  c.moments,
  case
    when cardinality(c.moments) > 0 or c.parent_id is null then c.moments
    else coalesce(p.moments, '{}')
  end as effective_moments
from public.categories c
left join public.categories p on p.id = c.parent_id;

comment on view public.categories_with_moments is
  'Categorías con sus momentos efectivos (herencia del padre resuelta). security_invoker: respeta la RLS de categories.';
comment on column public.categories_with_moments.effective_moments is
  'Momentos propios o, si la subcategoría no tiene, los de su categoría padre.';

revoke all on table public.categories_with_moments from anon, authenticated;
grant select on table public.categories_with_moments to anon, authenticated;
