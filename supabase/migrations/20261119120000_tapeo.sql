-- =============================================================================
-- En Compañía · 20 · "Tapeo" en lugar de "Tapas"
--
-- La palabra de la marca es TAPEO (descriptor "Café · Tapeo · Cocktails").
-- - Categoría: "Tapas & para compartir" → "Tapeo & para compartir"; slug
--   tapas-y-para-compartir → tapeo-y-para-compartir (la web redirige el slug viejo).
--   La foto del banner no cambia: image_path guarda su propia ruta.
-- - Textos de la web: descriptor del hero, bloque "Nuestra propuesta" y tarjeta
--   "Bar y tapeo" (reemplazo aprobado por el cliente).
-- Solo cambia lo que todavía tiene el texto original: si el admin ya lo editó, no se toca.
-- Las claves internas (site_content.section = 'offer_tapas' y la categoría 'tapas' de
-- la galería) no se ven en la web y quedan igual.
-- =============================================================================

update public.categories
set name = 'Tapeo & para compartir'
where name = 'Tapas & para compartir';

update public.categories
set slug = 'tapeo-y-para-compartir'
where slug = 'tapas-y-para-compartir'
  and not exists (select 1 from public.categories where slug = 'tapeo-y-para-compartir');

update public.site_content
set subtitle = 'Café · Tapeo · Cocktails'
where section = 'home_hero' and subtitle = 'Café · Tapas · Cocktails';

update public.site_content
set title = 'Tapeo'
where section = 'offer_tapas' and title = 'Tapas';

update public.site_content
set items = replace(
  items::text,
  'vinos y tapas creativas para acompañar',
  'vinos y un tapeo creativo para acompañar'
)::jsonb
where section = 'moments' and items::text like '%vinos y tapas creativas para acompañar%';
