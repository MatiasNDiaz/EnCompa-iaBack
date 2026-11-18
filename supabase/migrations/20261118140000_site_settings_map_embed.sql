-- =============================================================================
-- En Compañía · 19 · Mapa de /contacto
--
-- Además del formato del botón "Compartir → Insertar un mapa" de Google Maps
-- (https://www.google.com/maps/embed?pb=...), se acepta el embed por dirección, que
-- no necesita clave de API: https://www.google.com/maps?q=<dirección>&output=embed.
-- Se carga el mapa de la dirección del local solo si todavía no hay uno.
-- =============================================================================

alter table public.site_settings drop constraint site_settings_google_maps_embed_url_check;
alter table public.site_settings
  add constraint site_settings_google_maps_embed_url_check
  check (
    google_maps_embed_url ~ '^https://www\.google\.com/maps/embed'
    or google_maps_embed_url ~ '^https://www\.google\.com/maps\?[^#]*output=embed'
  );

update public.site_settings
set google_maps_embed_url = coalesce(
  google_maps_embed_url,
  'https://www.google.com/maps?q=Sarmiento%2057%2C%20La%20Cumbre%2C%20C%C3%B3rdoba%2C%20Argentina&z=16&output=embed'
)
where singleton;
