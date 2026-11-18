-- =============================================================================
-- En Compañía · 18 · Datos: contacto y redes del local (enviados por el cliente)
--
-- Idempotente y conservador: completa SOLO los campos vacíos, así nunca pisa lo que
-- se cargue después desde el panel. Los links se guardan limpios (sin parámetros de
-- seguimiento) y TikTok apunta al perfil, no a un video.
-- =============================================================================

update public.site_settings set
  address                    = coalesce(address, 'Sarmiento 57, La Cumbre, Córdoba, Argentina'),
  whatsapp                   = coalesce(whatsapp, '5493548588555'),
  phone                      = coalesce(phone, '+54 9 3548 58-8555'),
  email                      = coalesce(email, 'info@en-compania.com'),
  instagram_url              = coalesce(instagram_url, 'https://www.instagram.com/en_compania_lc/'),
  facebook_url               = coalesce(facebook_url, 'https://web.facebook.com/profile.php?id=61595840804512'),
  tiktok_url                 = coalesce(tiktok_url, 'https://www.tiktok.com/@en_compania_lc'),
  google_maps_directions_url = coalesce(
    google_maps_directions_url,
    'https://www.google.com/maps/dir/?api=1&destination=Sarmiento%2057%2C%20La%20Cumbre%2C%20C%C3%B3rdoba%2C%20Argentina'
  )
where singleton;
