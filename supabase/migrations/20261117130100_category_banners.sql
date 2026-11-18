-- =============================================================================
-- En Compañía · 11 · Banners de las secciones de la carta, en la base
--
-- El banner de una sección = `categories.image_path` (foto) + `categories.description`
-- (texto breve). Hasta ahora la foto por defecto salía del CÓDIGO (una foto estática
-- por slug). Desde esta migración la fuente de verdad es la base:
--
--   · image_path pasa a la carpeta propia `categories/` del bucket (antes `products/`;
--     no había ninguna ruta guardada, así que no se pierde nada).
--   · image_is_illustrative: true si la foto es de banco (no es del local). La web la
--     rotula "Imagen ilustrativa". Al subir una foto propia desde el panel vuelve a false.
--
-- Las 8 fotos actuales se suben a Storage con `npm run media:banners`
-- (scripts/upload-category-banners.mjs): una migración SQL no puede subir archivos.
-- =============================================================================

alter table public.categories drop constraint categories_image_path_check;
alter table public.categories
  add constraint categories_image_path_check
  check (private.is_image_path(image_path, 'categories'));

alter table public.categories
  add column image_is_illustrative boolean not null default false;

comment on column public.categories.image_path is
  'Foto del banner de la sección en la carta (site-media/categories/...). NULL = textura de marca.';
comment on column public.categories.description is
  'Texto breve del banner (bajo el título).';
comment on column public.categories.image_is_illustrative is
  'La foto del banner es ilustrativa (de banco, no del local): la web la rotula.';

-- La vista suma la columna nueva AL FINAL (create or replace no permite reordenar).
create or replace view public.categories_with_moments
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
  end as effective_moments,
  c.image_is_illustrative
from public.categories c
left join public.categories p on p.id = c.parent_id;
