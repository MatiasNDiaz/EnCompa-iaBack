-- =============================================================================
-- En Compañía · 16 · Plato del día: ingredientes en texto libre
--
-- En el panel, cargar los ingredientes de a uno (text[] con ítems de hasta 80
-- caracteres) resultó tedioso. Pasan a ser un único texto, igual que
-- products.ingredients: hasta 500 caracteres, NULL = no se muestra.
-- Los datos existentes se conservan: la lista se une con ", ".
-- =============================================================================

alter table public.daily_specials drop constraint daily_specials_ingredients_check;

alter table public.daily_specials
  alter column ingredients type text
  using nullif(btrim(array_to_string(ingredients, ', ')), '');

alter table public.daily_specials
  add constraint daily_specials_ingredients_check
  check (char_length(ingredients) <= 500);

comment on column public.daily_specials.ingredients is
  'Opcional. Ingredientes en texto libre (p. ej. "Pan de masa madre, palta, huevo."). NULL = no se muestra.';

-- Ya no se usa (validaba la lista de ítems).
drop function private.is_valid_ingredient_list(text[]);
