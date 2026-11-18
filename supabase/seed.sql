-- =============================================================================
-- En Compañía · Seed de DESARROLLO (solo `supabase db reset` local)
-- Fuente: CLAUDE.md (secciones 5, 6 y 7) y decisiones del Prompt 3.
--
-- Reglas:
--   · Precios y descripciones de productos en NULL (no existen todavía).
--   · Textos institucionales LITERALES (copy oficial aprobado).
--   · Instructores en NULL; coctelería sin institución ni certificado.
--   · Sin dirección, teléfono, horarios ni redes: site_settings queda con NULL.
--   · Sin imágenes: la web usa placeholders identificados como tales.
--   · Ningún usuario: el admin se crea con el procedimiento del README.
-- =============================================================================

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

-- =============================================================================
-- BORRADOR de textos de la carta (pedido del desarrollador para mostrar las tarjetas
-- completas). Describen el producto CLÁSICO (receta estándar), no la receta de la casa:
-- el cliente debe revisarlos y corregirlos desde el CMS antes de publicar.
-- Productos de autor (En Compañía Coffee, En Compañía Sour, Bruma), Menú del día y
-- Pinchos rotativos: borradores genéricos que NO afirman la receta propia (al final).
-- Pedido del desarrollador (2026-11-17): ninguna tarjeta sin descripción ni ingredientes.
-- =============================================================================
update public.products p set description = d.description, ingredients = d.ingredients
from (values
  ('americano', 'Espresso alargado con agua caliente: suave y aromático.', 'Espresso, agua caliente.'),
  ('espresso', 'Café concentrado de extracción corta, intenso y con crema.', 'Café, agua.'),
  ('doppio', 'Doble espresso, para quienes buscan más intensidad.', 'Doble shot de espresso.'),
  ('cortado', 'Espresso cortado con un toque de leche texturizada.', 'Espresso, leche.'),
  ('flat-white', 'Doble espresso con una capa fina de leche sedosa.', 'Doble espresso, leche texturizada.'),
  ('cappuccino', 'Espresso, leche vaporizada y una generosa capa de espuma.', 'Espresso, leche, espuma de leche.'),
  ('latte', 'Espresso con abundante leche cremosa.', 'Espresso, leche texturizada.'),
  ('mocha', 'Espresso, chocolate y leche cremosa.', 'Espresso, chocolate, leche.'),
  ('irish-coffee', 'Café caliente, whisky irlandés y crema batida.', 'Café, whisky irlandés, azúcar, crema.'),
  ('frappuccino', 'Café frío batido con hielo, cremoso y refrescante.', 'Café, leche, hielo.'),
  ('cold-brew', 'Café infusionado en frío durante horas: suave y de baja acidez.', 'Café, agua fría.'),
  ('iced-coffee', 'Café servido sobre hielo, ideal para los días de calor.', 'Café, hielo.'),
  ('iced-latte', 'Espresso con leche fría y hielo.', 'Espresso, leche, hielo.'),
  ('v60', 'Café filtrado en V60: limpio, aromático y delicado.', 'Café, agua.'),
  ('chemex', 'Café filtrado en Chemex, para una taza clara y equilibrada.', 'Café, agua.'),
  ('prensa', 'Café en prensa francesa, con cuerpo y textura.', 'Café, agua.'),
  ('chocolatada', 'Leche caliente con chocolate.', 'Leche, chocolate.'),
  ('tes', 'Infusión caliente para acompañar el momento.', 'Hebras de té, agua caliente.'),
  ('te-frio', 'Té frío y refrescante, servido con hielo.', 'Té, hielo.'),
  ('jamon-y-queso', 'El clásico de siempre: jamón cocido y queso.', 'Pan, jamón cocido, queso.'),
  ('pastrami', 'Sándwich de pastrami en finas láminas.', 'Pan, pastrami.'),
  ('french-toast', 'Pan dorado en huevo y leche, tibio y dulce.', 'Pan, huevo, leche.'),
  ('bowl-de-yogur', 'Yogur cremoso con granola y fruta, para empezar el día liviano.', 'Yogur natural, granola, frutas de estación, miel.'),
  ('huevos-benedictinos', 'Huevos pochados sobre pan tostado, con salsa holandesa.', 'Huevos, pan, salsa holandesa.'),
  ('tostadas', 'Pan tostado con manteca y mermelada, para acompañar el café.', 'Pan, manteca, mermelada.'),
  ('huevos-de-desayuno', 'Huevos a elección sobre pan tostado, para un desayuno completo.', 'Huevos, pan tostado, manteca.'),
  ('avocado-toast', 'Pan tostado con palta.', 'Pan, palta.'),
  ('croissant', 'Hojaldre de manteca, dorado y crocante.', 'Masa hojaldrada, manteca.'),
  ('pain-au-chocolat', 'Masa hojaldrada con barras de chocolate.', 'Masa hojaldrada, chocolate.'),
  ('tarteleta', 'Pequeña tarta de masa crocante con crema y fruta.', 'Masa sablée, crema pastelera, frutas de estación.'),
  ('torta', 'Una porción de la torta del día para acompañar el café.', 'Harina, huevos, manteca, azúcar, relleno del día.'),
  ('cookie', 'Crocante por fuera y tierna por dentro.', 'Harina, manteca, azúcar, chips de chocolate.'),
  ('cinnamon-roll', 'Rollo de masa con canela y azúcar.', 'Masa, canela, azúcar.'),
  ('budin', 'Budín húmedo, ideal con un café.', 'Harina, huevos, manteca, azúcar, limón.'),
  ('tabla-de-quesos', 'Selección de quesos para compartir.', 'Quesos seleccionados, frutos secos, panes, mermelada.'),
  ('tabla-de-fiambres', 'Selección de fiambres para compartir.', 'Fiambres seleccionados, quesos, aceitunas, panes.'),
  ('croque', 'Sándwich gratinado de jamón y queso, al estilo francés.', 'Pan, jamón, queso.'),
  ('alitas', 'Alitas de pollo para compartir.', 'Alitas de pollo.'),
  ('papas-fritas-con-salsa-holandesa', 'Papas fritas acompañadas de salsa holandesa.', 'Papas, salsa holandesa.'),
  ('falafel-bowl', 'Bowl con falafel de garbanzos.', 'Falafel de garbanzos.'),
  ('pincho-de-falafel', 'Falafel de garbanzos en pincho.', 'Falafel de garbanzos.'),
  ('flan-con-caramelo', 'Flan con caramelo, clásico de sobremesa.', 'Huevos, leche, azúcar, caramelo.'),
  ('mousse-de-chocolate', 'Mousse de chocolate, aireada y suave.', 'Chocolate, crema, huevos.'),
  ('gin-tonic', 'Gin y agua tónica sobre hielo.', 'Gin, agua tónica.'),
  ('fernet', 'Fernet con cola, el clásico argentino.', 'Fernet, cola.'),
  ('aperol-spritz', 'Aperol, espumante y soda: el aperitivo italiano.', 'Aperol, espumante, soda.'),
  ('limoncello-spritz', 'Limoncello, espumante y soda, fresco y cítrico.', 'Limoncello, espumante, soda.'),
  ('vermut-con-soda-o-tonica', 'Vermut servido con soda o tónica.', 'Vermut, soda o tónica.'),
  ('cynar', 'El aperitivo amargo italiano, con pomelo y hielo.', 'Cynar, jugo de pomelo, hielo.'),
  ('cuba-libre', 'Ron, cola y lima.', 'Ron, cola, lima.'),
  ('paloma', 'Tequila con pomelo y un toque de lima.', 'Tequila, pomelo, lima.'),
  ('negroni', 'Gin, Campari y vermut rojo en partes iguales.', 'Gin, Campari, vermut rojo.'),
  ('old-fashioned', 'Bourbon, azúcar y amargo de angostura.', 'Bourbon, azúcar, angostura.'),
  ('martini', 'Gin y vermut seco, servido bien frío.', 'Gin, vermut seco.'),
  ('bloody-mary', 'Vodka, jugo de tomate y especias.', 'Vodka, jugo de tomate, especias.'),
  ('daiquiri', 'Ron, lima y azúcar.', 'Ron, lima, azúcar.'),
  ('clover-club', 'Gin, frambuesa, limón y clara de huevo.', 'Gin, frambuesa, limón, clara de huevo.'),
  ('margarita', 'Tequila, triple sec y lima.', 'Tequila, triple sec, lima.'),
  ('whiskey-sour', 'Whisky, limón, azúcar y clara de huevo.', 'Whisky, limón, azúcar, clara de huevo.'),
  ('pisco-sour', 'Pisco, limón, azúcar y clara de huevo.', 'Pisco, limón, azúcar, clara de huevo.'),
  ('amaretto-sour', 'Amaretto, limón y azúcar.', 'Amaretto, limón, azúcar.'),
  ('sangria', 'Vino tinto con frutas, para compartir.', 'Vino tinto, frutas.'),
  -- Productos de la casa, Menú del día y Pinchos rotativos: borradores que NO afirman
  -- la receta propia (no está en ningún documento). Reemplazar desde el CMS.
  ('en-compania-coffee', 'La firma de la casa en taza: nuestro café de especialidad en una versión propia, cremosa y aromática.', 'Espresso, leche texturizada, toque de la casa.'),
  ('en-compania-sour', 'El sour de la casa: fresco, cítrico y con espuma sedosa.', 'Destilado de la casa, limón, almíbar, clara de huevo.'),
  ('bruma', 'Café de autor: espresso y espíritu en un trago suave y aromático.', 'Espresso, licor, crema.'),
  ('menu-del-dia-opcion-1', 'Plato del día, distinto en cada jornada. Consultá la propuesta de hoy.', 'Ingredientes de estación, según el plato del día.'),
  ('menu-del-dia-opcion-2', 'Segunda propuesta del día, también rotativa. Consultá la opción de hoy.', 'Ingredientes de estación, según el plato del día.'),
  ('pinchos-rotativos', 'Pinchos que cambian según el día, para picar y compartir.', 'Según la propuesta del día.')
) as d (slug, description, ingredients)
where p.slug = d.slug;

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

-- =============================================================================
-- PRECIOS FICTICIOS DE DESARROLLO (pedido del desarrollador para previsualizar la carta).
-- NO son los precios de En Compañía: este seed solo corre en local. Los precios reales
-- se cargan desde el CMS antes de publicar (CLAUDE.md §7 permite "un valor de desarrollo
-- claramente ficticio" en el seed).
-- =============================================================================
update public.products p set price = d.price
from (values
  ('americano', 3800), ('espresso', 3200), ('doppio', 4200), ('cortado', 3600),
  ('flat-white', 4900), ('cappuccino', 4600), ('latte', 4800),
  ('mocha', 5400), ('en-compania-coffee', 6200), ('irish-coffee', 7800),
  ('frappuccino', 6400), ('cold-brew', 5600), ('iced-coffee', 4900), ('iced-latte', 5600),
  ('v60', 5800), ('chemex', 6800), ('prensa', 5200),
  ('chocolatada', 4500), ('tes', 3600), ('te-frio', 4200),
  ('jamon-y-queso', 8500), ('pastrami', 12500),
  ('french-toast', 9800), ('bowl-de-yogur', 7900), ('huevos-benedictinos', 12900),
  ('tostadas', 5200), ('huevos-de-desayuno', 8900), ('avocado-toast', 10800),
  ('croissant', 3900), ('pain-au-chocolat', 4400), ('tarteleta', 5200), ('torta', 6500),
  ('cookie', 3200), ('cinnamon-roll', 4800), ('budin', 3800),
  ('menu-del-dia-opcion-1', 14500), ('menu-del-dia-opcion-2', 14500),
  ('tabla-de-quesos', 18900), ('tabla-de-fiambres', 19900), ('croque', 11500),
  ('alitas', 13900), ('papas-fritas-con-salsa-holandesa', 9500), ('pinchos-rotativos', 8900),
  ('falafel-bowl', 12800), ('pincho-de-falafel', 7500),
  ('flan-con-caramelo', 6200), ('mousse-de-chocolate', 6900),
  ('gin-tonic', 10500), ('fernet', 8500),
  ('aperol-spritz', 11500), ('limoncello-spritz', 11500),
  ('vermut-con-soda-o-tonica', 8900),
  ('cynar', 8500), ('cuba-libre', 9500), ('paloma', 11000), ('negroni', 12500),
  ('old-fashioned', 13500), ('martini', 12500), ('bloody-mary', 11500), ('daiquiri', 10500),
  ('clover-club', 12500),
  ('margarita', 11500), ('whiskey-sour', 12500), ('pisco-sour', 12500),
  ('en-compania-sour', 13500), ('amaretto-sour', 11500),
  ('sangria', 9900), ('bruma', 13500)
) as d (slug, price)
where p.slug = d.slug;
