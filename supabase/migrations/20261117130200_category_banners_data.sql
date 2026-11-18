-- =============================================================================
-- En Compañía · 12 · DATOS: texto inicial de los banners de la carta
--
-- Idempotente y no destructiva: solo completa secciones raíz que existan y cuyo texto
-- esté vacío, así nunca pisa lo editado desde el panel. (En un proyecto sin carta
-- cargada no hace nada.)
--
-- Cafetería, Almuerzos, Tapas y Cocktails: textos oficiales del cliente. El resto:
-- microcopy evocativo que no afirma hechos del negocio, editable desde el panel.
-- =============================================================================

update public.categories c
set description = v.description
from (values
  ('cafeteria',              'El arte de preparar una buena taza'),
  ('sandwiches',             'Para comer con las manos y sin apuro'),
  ('desayunos-y-brunch',     'Mañanas lentas, mesas llenas'),
  ('pasteleria',             'Algo dulce para acompañar el café'),
  ('almuerzos',              'Algo rico y simple'),
  ('tapas-y-para-compartir', 'Pequeños grandes placeres para compartir'),
  ('postres',                'El final dulce de cada encuentro'),
  ('cocteleria',             'El momento de brindar también tiene su lugar')
) as v (slug, description)
where c.slug = v.slug
  and c.parent_id is null
  and (c.description is null or btrim(c.description) = '');
