-- =============================================================================
-- En Compañía · 05 · Imagen por categoría
-- La carta presenta cada categoría como un banner fotográfico (referencia de
-- diseño aprobada). La imagen es opcional: sin foto, la web muestra un placeholder.
-- Se guarda en la carpeta `products/` del bucket (p. ej. products/categories/<uuid>.webp),
-- así no hace falta ampliar las carpetas permitidas por las políticas de Storage.
-- =============================================================================

alter table public.categories
  add column image_path text
  check (private.is_image_path(image_path, 'products'));

comment on column public.categories.image_path is
  'Foto del banner de la categoría en la carta. NULL = placeholder.';
