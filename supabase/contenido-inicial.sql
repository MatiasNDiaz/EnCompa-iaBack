-- =============================================================================
-- En Compañía · CONTENIDO INICIAL para un proyecto NUEVO (producción)
-- GENERADO por scripts/build-initial-content.mjs desde supabase/seed.sql: no editar a
-- mano (`npm run content:build` lo regenera).
--
-- Incluye: carta (secciones, subsecciones y productos SIN precio ni descripción),
-- subtítulos de las secciones, textos institucionales oficiales y capacitaciones.
-- NO incluye: precios ficticios ni borradores de descripciones/ingredientes (los reales
-- se cargan desde el panel).
--
-- Cómo aplicarlo (UNA vez, en el proyecto nuevo, después de `supabase db push`):
--   · Supabase → SQL Editor: pegar este archivo y ejecutar (corre como una transacción), o
--   · psql "<cadena de conexión>" --single-transaction -v ON_ERROR_STOP=1 -f supabase/contenido-inicial.sql
-- Después: `npm run media:banners` contra ese proyecto (fotos de los banners).
--
-- Seguridad: si la base ya tiene carta o textos, se detiene sin tocar nada.
-- =============================================================================

do $$
begin
  if exists (select 1 from public.categories) or exists (select 1 from public.site_content) then
    raise exception 'La base ya tiene contenido (carta o textos): este script es solo para un proyecto NUEVO.';
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- Categorías raíz (orden de la carta)
-- -----------------------------------------------------------------------------
-- moments: momentos del día (mañana / mediodía / tarde-noche). Mismos valores que la
-- migración 20261117120100_category_moments_data. Cafetería, Pastelería y Postres están
-- A CONFIRMAR (docs/DATABASE.md). Las subcategorías heredan de su padre.
insert into public.categories (name, slug, sort_order, moments) values
  ('Cafetería',              'cafeteria',              1, '{morning,midday,evening}'),
  ('Sandwiches',             'sandwiches',             2, '{morning,midday}'),
  ('Desayunos & Brunch',     'desayunos-y-brunch',     3, '{morning}'),
  ('Pastelería',             'pasteleria',             4, '{morning,evening}'),
  ('Almuerzos',              'almuerzos',              5, '{midday}'),
  ('Tapeo & para compartir', 'tapeo-y-para-compartir', 6, '{evening}'),
  ('Postres',                'postres',                7, '{midday,evening}'),
  ('Cocktails',              'cocteleria',             8, '{evening}');

-- -----------------------------------------------------------------------------
-- Subcategorías
-- -----------------------------------------------------------------------------
insert into public.categories (parent_id, name, slug, sort_order)
select parent.id, sub.name, sub.slug, sub.sort_order
from (values
  ('cafeteria',  'Cafés clásicos',      'cafes-clasicos',      1),
  ('cafeteria',  'Cafés especiales',    'cafes-especiales',    2),
  ('cafeteria',  'Cafés fríos',         'cafes-frios',         3),
  ('cafeteria',  'Cafés filtrados',     'cafes-filtrados',     4),
  ('cafeteria',  'Otras bebidas',       'otras-bebidas',       5),
  ('almuerzos',  'Menú del día',        'menu-del-dia',        1),
  ('cocteleria', 'Highball & clásicos', 'highball-y-clasicos', 1),
  ('cocteleria', 'Spritz',              'spritz',              2),
  ('cocteleria', 'Vermut',              'vermut',              3),
  ('cocteleria', 'Clásicos',            'cocteles-clasicos',   4),
  ('cocteleria', 'Sours',               'sours',               5),
  ('cocteleria', 'Sangría',             'sangria',             6),
  ('cocteleria', 'Café de autor',       'cafe-de-autor',       7)
) as sub (parent_slug, name, slug, sort_order)
join public.categories parent on parent.slug = sub.parent_slug;

-- -----------------------------------------------------------------------------
-- Productos (price y description en NULL)
-- is_featured: productos de autor de la casa (CLAUDE.md §7).
-- "Menú del día · Opción 1/2": placeholders estructurales; se editan a diario.
-- -----------------------------------------------------------------------------
insert into public.products (category_id, name, slug, sort_order, is_featured)
select c.id, p.name, p.slug, p.sort_order, p.is_featured
from (values
  -- Cafés clásicos
  ('cafes-clasicos', 'Americano',   'americano',   1, false),
  ('cafes-clasicos', 'Espresso',    'espresso',    2, false),
  ('cafes-clasicos', 'Doppio',      'doppio',      3, false),
  ('cafes-clasicos', 'Cortado',     'cortado',     4, false),
  ('cafes-clasicos', 'Flat White',  'flat-white',  5, false),
  ('cafes-clasicos', 'Cappuccino',  'cappuccino',  6, false),
  ('cafes-clasicos', 'Latte',       'latte',       7, false),
  -- Cafés especiales
  ('cafes-especiales', 'Mocha',              'mocha',              1, false),
  ('cafes-especiales', 'En Compañía Coffee', 'en-compania-coffee', 2, true),
  ('cafes-especiales', 'Irish Coffee',       'irish-coffee',       3, false),
  -- Cafés fríos
  ('cafes-frios', 'Frappuccino', 'frappuccino', 1, false),
  ('cafes-frios', 'Cold Brew',   'cold-brew',   2, false),
  ('cafes-frios', 'Iced Coffee', 'iced-coffee', 3, false),
  ('cafes-frios', 'Iced Latte',  'iced-latte',  4, false),
  -- Cafés filtrados
  ('cafes-filtrados', 'V60',    'v60',    1, false),
  ('cafes-filtrados', 'Chemex', 'chemex', 2, false),
  ('cafes-filtrados', 'Prensa', 'prensa', 3, false),
  -- Otras bebidas
  ('otras-bebidas', 'Chocolatada', 'chocolatada', 1, false),
  ('otras-bebidas', 'Tés',         'tes',         2, false),
  ('otras-bebidas', 'Té frío',     'te-frio',     3, false),
  -- Sandwiches
  ('sandwiches', 'Jamón y queso', 'jamon-y-queso', 1, false),
  ('sandwiches', 'Pastrami',      'pastrami',      2, false),
  -- Desayunos & Brunch
  ('desayunos-y-brunch', 'French Toast',        'french-toast',        1, false),
  ('desayunos-y-brunch', 'Bowl de yogur',       'bowl-de-yogur',       2, false),
  ('desayunos-y-brunch', 'Huevos Benedictinos', 'huevos-benedictinos', 3, false),
  ('desayunos-y-brunch', 'Tostadas',            'tostadas',            4, false),
  ('desayunos-y-brunch', 'Huevos de desayuno',  'huevos-de-desayuno',  5, false),
  ('desayunos-y-brunch', 'Avocado Toast',       'avocado-toast',       6, false),
  -- Pastelería
  ('pasteleria', 'Croissant',        'croissant',        1, false),
  ('pasteleria', 'Pain au chocolat', 'pain-au-chocolat', 2, false),
  ('pasteleria', 'Tarteleta',        'tarteleta',        3, false),
  ('pasteleria', 'Torta',            'torta',            4, false),
  ('pasteleria', 'Cookie',           'cookie',           5, false),
  ('pasteleria', 'Cinnamon Roll',    'cinnamon-roll',    6, false),
  ('pasteleria', 'Budín',            'budin',            7, false),
  -- Menú del día (dos opciones rotativas)
  ('menu-del-dia', 'Menú del día · Opción 1', 'menu-del-dia-opcion-1', 1, false),
  ('menu-del-dia', 'Menú del día · Opción 2', 'menu-del-dia-opcion-2', 2, false),
  -- Tapeo & para compartir
  ('tapeo-y-para-compartir', 'Tabla de quesos',                 'tabla-de-quesos',                 1, false),
  ('tapeo-y-para-compartir', 'Tabla de fiambres',               'tabla-de-fiambres',               2, false),
  ('tapeo-y-para-compartir', 'Croque',                          'croque',                          3, false),
  ('tapeo-y-para-compartir', 'Alitas',                          'alitas',                          4, false),
  ('tapeo-y-para-compartir', 'Papas fritas con salsa holandesa', 'papas-fritas-con-salsa-holandesa', 5, false),
  ('tapeo-y-para-compartir', 'Pinchos rotativos',               'pinchos-rotativos',               6, false),
  ('tapeo-y-para-compartir', 'Falafel Bowl',                    'falafel-bowl',                    7, false),
  ('tapeo-y-para-compartir', 'Pincho de falafel',               'pincho-de-falafel',               8, false),
  -- Postres
  ('postres', 'Flan con caramelo',   'flan-con-caramelo',   1, false),
  ('postres', 'Mousse de chocolate', 'mousse-de-chocolate', 2, false),
  -- Highball & clásicos
  ('highball-y-clasicos', 'Gin Tonic', 'gin-tonic', 1, false),
  ('highball-y-clasicos', 'Fernet',    'fernet',    2, false),
  -- Spritz
  ('spritz', 'Aperol Spritz',     'aperol-spritz',     1, false),
  ('spritz', 'Limoncello Spritz', 'limoncello-spritz', 2, false),
  -- Vermut
  ('vermut', 'Vermut con soda o tónica', 'vermut-con-soda-o-tonica', 1, false),
  -- Clásicos (coctelería)
  ('cocteles-clasicos', 'Cynar',          'cynar',          1, false),
  ('cocteles-clasicos', 'Cuba Libre',     'cuba-libre',     2, false),
  ('cocteles-clasicos', 'Paloma',         'paloma',         3, false),
  ('cocteles-clasicos', 'Negroni',        'negroni',        4, false),
  ('cocteles-clasicos', 'Old Fashioned',  'old-fashioned',  5, false),
  ('cocteles-clasicos', 'Martini',        'martini',        6, false),
  ('cocteles-clasicos', 'Bloody Mary',    'bloody-mary',    7, false),
  ('cocteles-clasicos', 'Daiquiri',       'daiquiri',       8, false),
  ('cocteles-clasicos', 'Clover Club',    'clover-club',    9, false),
  -- Sours
  ('sours', 'Margarita',        'margarita',        1, false),
  ('sours', 'Whiskey Sour',     'whiskey-sour',     2, false),
  ('sours', 'Pisco Sour',       'pisco-sour',       3, false),
  ('sours', 'En Compañía Sour', 'en-compania-sour', 4, true),
  ('sours', 'Amaretto Sour',    'amaretto-sour',    5, false),
  -- Sangría
  ('sangria', 'Sangría', 'sangria', 1, false),
  -- Café de autor
  ('cafe-de-autor', 'Bruma', 'bruma', 1, true)
) as p (category_slug, name, slug, sort_order, is_featured)
join public.categories c on c.slug = p.category_slug;

-- -----------------------------------------------------------------------------
-- Contenido institucional (textos oficiales LITERALES, CLAUDE.md §4 y §5)
-- -----------------------------------------------------------------------------
insert into public.site_content (section, title, subtitle, content, quote, items) values
(
  'home_hero',
  'Donde los encuentros saben mejor.',
  'Café · Tapeo · Cocktails',
  'Hay lugares a los que siempre dan ganas de volver. Un café, algo rico para compartir y ese momento que se disfruta un poquito más. Bienvenidos a En Compañía.',
  null, null
),
(
  'offer_coffee',
  'Café',
  'El arte de preparar una buena taza',
  'Cafés clásicos, especiales, fríos y filtrados.',
  null, null
),
(
  'offer_tapas',
  'Tapeo',
  'Pequeños grandes placeres para compartir',
  'Opciones para compartir.',
  null, null
),
(
  'offer_cocktails',
  'Cocktails',
  'El momento de brindar también tiene su lugar',
  'Clásicos, aperitivos y creaciones de autor.',
  null, null
),
(
  'history',
  'Una historia que nació alrededor de una mesa',
  null,
  $txt$Hay historias que comienzan con un viaje, otras con un sueño. La de En Compañía nació de una pasión compartida: descubrir nuevos sabores, disfrutar de un buen café y encontrar en cada salida ese lugar especial al que siempre dan ganas de volver.

Somos una familia que llegó desde Suiza y encontró en La Cumbre un lugar para echar raíces. Con el tiempo, fuimos construyendo nuestra vida alrededor de pequeños grandes placeres: salir a comer, conocer propuestas gastronómicas, degustar cafés de distintos rincones del mundo y, sobre todo, compartir momentos con familia y amigos.

De esos encuentros, de tantos sabores descubiertos y de las ganas de tener un lugar propio, nació En Compañía. Un emprendimiento familiar que reúne aquello que tanto disfrutamos, sumando nuestra historia y nuestras raíces suizas a una propuesta gastronómica con identidad propia.

Así imaginamos este espacio: un lugar donde convivan distintas culturas, sabores y aromas; donde cada café invite a hacer una pausa, cada plato despierte curiosidad y cada encuentro se convierta en un lindo recuerdo.

Porque En Compañía no nació solamente para abrir las puertas de un café y bar. Nació para compartir aquello que nos apasiona y crear un lugar donde todos puedan sentirse parte.$txt$,
  'De nuestras raíces, nuestros viajes y el placer de compartir, nació un lugar para encontrarnos',
  null
),
(
  'essence',
  'Calidad en cada detalle',
  null,
  $txt$En En Compañía creemos que una gran experiencia comienza mucho antes de llegar a la mesa. Empieza con la elección de cada ingrediente, la calidad de la materia prima, el conocimiento de quienes preparan cada producto y la dedicación puesta en cada detalle.

Nuestra apuesta es ofrecer en La Cumbre una propuesta gastronómica diferente, donde la técnica, la creatividad y la excelencia se encuentren en cada preparación. Desde un café cuidadosamente elaborado hasta un cocktail clásico o una creación de autor, buscamos que cada producto tenga identidad, calidad y una presentación a la altura de lo que queremos transmitir.

Por eso, invertimos especialmente en la formación y capacitación de nuestro equipo. Creemos que el conocimiento se refleja en el resultado y que las personas son una parte esencial de la experiencia. Queremos que cada integrante conozca su oficio, perfeccione sus técnicas y pueda brindar una atención cálida, profesional y cercana.$txt$,
  null, null
),
(
  'mission',
  'Nuestra misión',
  null,
  'Crear momentos que merezcan ser recordados, ofreciendo productos de calidad, una propuesta gastronómica cuidada y un servicio cálido y profesional. Queremos que cada visita sea una experiencia para disfrutar y compartir.',
  null, null
),
(
  'vision',
  'Nuestra visión',
  null,
  'Convertirnos en un espacio de referencia en La Cumbre por la calidad de nuestra propuesta, la excelencia de nuestro servicio y una manera diferente de disfrutar la gastronomía.',
  null, null
),
(
  'values',
  'Nuestros valores',
  null, null, null,
  '[
    {"title": "CALIDAD", "description": "Elegimos cuidadosamente cada producto y cada materia prima. La calidad es nuestro punto de partida."},
    {"title": "CONOCIMIENTO Y FORMACIÓN", "description": "Aprender, perfeccionar técnicas y crecer para ofrecer siempre lo mejor."},
    {"title": "EXCELENCIA EN CADA DETALLE", "description": "Cuidamos la preparación, la presentación y el servicio, porque todo forma parte de la experiencia."},
    {"title": "CREATIVIDAD E IDENTIDAD", "description": "Una propuesta que combina sabores, técnicas y tradiciones para ofrecer algo propio y diferente."},
    {"title": "HOSPITALIDAD", "description": "Recibir bien, atender con calidez y hacer que cada persona se sienta cómoda y bienvenida."}
  ]'::jsonb
),
(
  'differentiation',
  'La diferencia está en los detalles',
  null,
  $txt$En En Compañía no buscamos solamente servir algo rico. Queremos que cada detalle haga que la experiencia valga la pena.

Nuestra propuesta se construye a partir de la calidad de la materia prima, el cuidado en cada elaboración, la técnica y la formación constante de nuestro equipo. Apostamos a una oferta diferente en La Cumbre, con cafés preparados con conocimiento, cocktails clásicos y de autor elaborados con precisión, y una presentación cuidada de principio a fin.

Creemos que la calidad también se expresa en la manera de recibir, acompañar y atender. Por eso, cada preparación y cada encuentro son una oportunidad para compartir lo que nos apasiona y ofrecer una experiencia especial, cercana y memorable.$txt$,
  'No buscamos solamente servir algo rico. Queremos que cada detalle haga que la experiencia valga la pena',
  null
);

-- -----------------------------------------------------------------------------
-- Capacitaciones (CLAUDE.md §5.7, §5.8 y tabla del Prompt 3)
-- -----------------------------------------------------------------------------
insert into public.trainings
  (title, slug, subtitle, description, organization, instructor, certificate_name, is_published, sort_order)
values
(
  'El café también es conocimiento',
  'cafe',
  null,
  $txt$Detrás de cada taza hay mucho más que una preparación: hay técnica, práctica, dedicación y pasión por hacer las cosas bien. Por eso, nuestro equipo se capacitó junto a Doppio Project y logró la certificación CSP Barista Skills – Foundation, de la Specialty Coffee Association (SCA).

Una experiencia de aprendizaje que nos permitió incorporar conocimientos, perfeccionar habilidades y seguir creciendo en el mundo del café. Porque creemos que cada detalle importa y que ofrecer una buena experiencia empieza mucho antes de que la taza llegue a tu mesa.$txt$,
  'Doppio Project',
  null,
  'CSP Barista Skills – Foundation (SCA)',
  true,
  1
),
(
  'COCTELERÍA | TÉCNICA, CREATIVIDAD Y PERSONALIDAD',
  'cocteleria',
  'Una propuesta que combina técnica, creatividad y pasión por los sabores.',
  $txt$La coctelería es un universo de posibilidades donde cada ingrediente, cada combinación y cada técnica aportan personalidad a una preparación.

Por eso, nuestro equipo recibió capacitación en coctelería clásica y creaciones de autor, elaboración de jarabes, tinturas y espumas, además de técnicas de preparación, presentación y servicio.

Un recorrido de aprendizaje que nos permitió explorar nuevas combinaciones, incorporar herramientas y dominar cada etapa, desde la elaboración hasta el momento de llevar cada bebida a la mesa.

Porque creemos que la creatividad necesita técnica, que la calidad está en los detalles y que cada encuentro merece una propuesta especial.

En Compañía. Donde los encuentros saben mejor.$txt$,
  null,
  null,
  null,
  true,
  2
);

-- -----------------------------------------------------------------------------
-- Secciones de la presentación del cliente (CLAUDE.md §1.1–§1.3), textos literales
-- -----------------------------------------------------------------------------
insert into public.site_content (section, title, subtitle, content, quote, items) values
(
  'moments',
  'Un mismo lugar, diferentes momentos',
  null,
  'La propuesta cambia durante el día, pero el nivel de atención y la identidad son siempre los mismos.',
  null,
  '[
    {"title": "Mañana · Café y pastelería", "description": "Buen café, brunch, opciones dulces y sándwiches. Servicio ágil, cálido y cuidadoso."},
    {"title": "Mediodía · Algo rico y simple", "description": "Carta acotada, sándwiches y un menú del día rotativo."},
    {"title": "Tarde / noche · Bar y tapeo", "description": "Cócteles clásicos y de autor, vinos y un tapeo creativo para acompañar."}
  ]'::jsonb
),
(
  'name_meaning',
  '¿Qué significa En Compañía?',
  null,
  'El nombre expresa el centro del proyecto: las personas y los momentos que compartimos.',
  null,
  '[
    {"title": "Encuentro", "description": "Un punto de reunión donde siempre haya espacio para conversar, disfrutar o simplemente estar."},
    {"title": "Cercanía", "description": "Que cada cliente se sienta recibido, reconocido y cómodo, sea local o visitante. Con un portafolio para que todos encuentren algo que les guste."},
    {"title": "Calidad sin distancia", "description": "Café, gastronomía, vinos y coctelería cuidados, en un ambiente accesible y sin pretensiones."}
  ]'::jsonb
),
(
  'experience',
  'La experiencia',
  null,
  'Nuestro servicio define cómo se vive En Compañía, desde la primera bienvenida hasta la despedida.',
  null,
  '[
    {"title": "Bienvenido", "description": "Un saludo genuino, atención presente y una sensación de pertenencia."},
    {"title": "A gusto", "description": "Un ambiente relajado, cómodo para venir solo, con amigos, en pareja o en familia."},
    {"title": "Con ganas de volver", "description": "Consistencia, pequeños detalles y recomendaciones que demuestren que importa cada visita."}
  ]'::jsonb
);

-- Subtítulos de cada sección de la carta (se muestran bajo el título del banner).
-- Oficiales del cliente donde existen (Cafetería, Almuerzos, Tapeo, Coctelería);
-- el resto, microcopy evocativo que no afirma hechos del negocio.
update public.categories c set description = d.description
from (values
  ('cafeteria', 'El arte de preparar una buena taza'),
  ('sandwiches', 'Para comer con las manos y sin apuro'),
  ('desayunos-y-brunch', 'Mañanas lentas, mesas llenas'),
  ('pasteleria', 'Algo dulce para acompañar el café'),
  ('almuerzos', 'Algo rico y simple'),
  ('tapeo-y-para-compartir', 'Pequeños grandes placeres para compartir'),
  ('postres', 'El final dulce de cada encuentro'),
  ('cocteleria', 'El momento de brindar también tiene su lugar')
) as d (slug, description)
where c.slug = d.slug;
