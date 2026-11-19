-- =============================================================================
-- En Compañía · 25 · Novedades: diseño de la tarjeta
--
-- El admin elige cómo se ve cada novedad en la lista de /novedades:
--   · split   — "Dividida": foto a la izquierda y texto a la derecha.
--   · stacked — "Apilada": foto arriba y texto abajo.
--   · curved  — "Curva": foto a la izquierda con el borde derecho curvo.
-- En el celular las tres ponen la foto arriba, cada una con su estilo.
-- Las novedades existentes quedan en "Dividida" (el valor por defecto).
-- =============================================================================

alter table public.news_posts
  add column card_layout text not null default 'split'
    check (card_layout in ('split', 'stacked', 'curved'));

comment on column public.news_posts.card_layout is
  'Diseño de la tarjeta en /novedades: split (foto a la izquierda), stacked (foto arriba) o curved (foto con borde curvo).';
