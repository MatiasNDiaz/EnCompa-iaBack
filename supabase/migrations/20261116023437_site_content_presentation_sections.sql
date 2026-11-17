-- =============================================================================
-- En Compañía · 06 · Nuevas secciones de contenido institucional
-- Textos de la presentación del cliente (CLAUDE.md §1.1–§1.3), editables desde el CMS:
--   moments       · "Un mismo lugar, diferentes momentos" (mañana / mediodía / tarde-noche)
--   name_meaning  · "¿Qué significa En Compañía?" (Encuentro / Cercanía / Calidad sin distancia)
--   experience    · "La experiencia" (Bienvenido / A gusto / Con ganas de volver)
-- Las tres usan la lista `items` ({title, description}), como `values`.
-- =============================================================================

alter table public.site_content drop constraint site_content_section_check;
alter table public.site_content add constraint site_content_section_check check (section in (
  'home_hero', 'offer_coffee', 'offer_tapas', 'offer_cocktails',
  'history', 'essence', 'mission', 'vision', 'values', 'differentiation',
  'moments', 'name_meaning', 'experience'
));

alter table public.site_content drop constraint site_content_items_check;
alter table public.site_content add constraint site_content_items_check check (
  items is null
  or (section in ('values', 'moments', 'name_meaning', 'experience') and jsonb_typeof(items) = 'array')
);
