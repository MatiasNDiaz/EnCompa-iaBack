-- =============================================================================
-- En Compañía · 07 · Ingredientes por producto
-- La tarjeta de producto (referencia del cliente) muestra un bloque "Ingredientes".
-- Opcional: NULL = el bloque no se muestra. Se carga desde el CMS (nada inventado).
-- =============================================================================

alter table public.products
  add column ingredients text check (char_length(ingredients) <= 500);

comment on column public.products.ingredients is
  'Ingredientes en texto libre (p. ej. "Pan artesanal, jamón cocido, queso, manteca."). NULL = no se muestra.';
