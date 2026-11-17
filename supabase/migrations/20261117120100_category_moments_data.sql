-- =============================================================================
-- En Compañía · Momentos iniciales de cada categoría raíz (migración de DATOS)
--
-- Idempotente: solo completa categorías que todavía no tienen momentos (moments = '{}'),
-- así nunca pisa lo que se edite desde el panel. Si las categorías no existen todavía
-- (p. ej. `db reset` local, donde el seed corre DESPUÉS), no toca ninguna fila: el seed
-- carga los mismos valores.
--
-- Fuente: presentación del equipo. "A CONFIRMAR" = supuesto, no figura en ningún documento
-- (ver docs/DATABASE.md):
--   cafeteria   → mañana, mediodía, tarde/noche   (A CONFIRMAR: café todo el día)
--   pasteleria  → mañana, tarde/noche              (A CONFIRMAR: merienda)
--   postres     → mediodía, tarde/noche            (A CONFIRMAR)
-- Las subcategorías quedan en '{}' y heredan de su padre.
-- =============================================================================

update public.categories as c
set moments = v.moments
from (values
  ('cafeteria',              array['morning', 'midday', 'evening']::public.day_moment[]),
  ('sandwiches',             array['morning', 'midday']::public.day_moment[]),
  ('desayunos-y-brunch',     array['morning']::public.day_moment[]),
  ('pasteleria',             array['morning', 'evening']::public.day_moment[]),
  ('almuerzos',              array['midday']::public.day_moment[]),
  ('tapas-y-para-compartir', array['evening']::public.day_moment[]),
  ('postres',                array['midday', 'evening']::public.day_moment[]),
  ('cocteleria',             array['evening']::public.day_moment[])
) as v (slug, moments)
where c.slug = v.slug
  and c.parent_id is null
  and c.moments = '{}';
