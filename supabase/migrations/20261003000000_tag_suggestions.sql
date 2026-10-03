-- Tag suggestions from place names.
-- Many source records arrive as plain "restaurant" with the cuisine only in the name
-- ("Pho New Saigon"). This proposes a tag from keywords in the name. A proposal is a
-- pending change_event: nothing is tagged until a person accepts it.
SET search_path = public, extensions;

CREATE TABLE public.tag_keywords (
  id          smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pattern     text NOT NULL,        -- regex alternatives, matched as whole words, case-insensitive
  category_id uuid NOT NULL REFERENCES public.categories(id),
  is_active   boolean NOT NULL DEFAULT true,
  UNIQUE (pattern, category_id)
);
ALTER TABLE public.tag_keywords ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.tag_keywords FROM anon, authenticated;
GRANT ALL ON public.tag_keywords TO service_role;

WITH v(pattern, path) AS (VALUES
  ('pizza|pizzeria',                          'restaurants.italian.pizza'),
  ('pasta',                                   'restaurants.italian.pasta'),
  ('italian|trattoria|osteria|ristorante',    'restaurants.italian'),
  ('sushi',                                   'restaurants.asian.japanese.sushi'),
  ('ramen',                                   'restaurants.asian.japanese.ramen'),
  ('japanese|hibachi|teriyaki',               'restaurants.asian.japanese'),
  ('pho|vietnam|vietnamese|banh mi',          'restaurants.asian.vietnamese'),
  ('thai',                                    'restaurants.asian.thai'),
  ('chinese|china|szechuan|sichuan|hunan|wok|dumplings?|dim sum', 'restaurants.asian.chinese'),
  ('korean',                                  'restaurants.asian.korean'),
  ('filipino',                                'restaurants.asian.filipino'),
  ('afghan',                                  'restaurants.asian.afghan'),
  ('pakistani',                               'restaurants.asian.pakistani'),
  ('indian|india|curry|tandoori?|biryani',    'restaurants.indian'),
  ('taqueria|tacos?',                         'restaurants.mexican.tacos'),
  ('tex[- ]?mex',                             'restaurants.mexican.tex_mex'),
  ('mexican|burritos?|cantina',               'restaurants.mexican'),
  ('pupuseria|pupusas?|salvadore[ñn]o|salvadoran', 'restaurants.latin_american.salvadoran'),
  ('peruvian|peru',                           'restaurants.latin_american.peruvian'),
  ('brazilian',                               'restaurants.latin_american.brazilian'),
  ('caribbean|jamaican|jerk',                 'restaurants.latin_american.caribbean'),
  ('ethiopian|injera',                        'restaurants.african.ethiopian'),
  ('african',                                 'restaurants.african'),
  ('greek|gyros?',                            'restaurants.mediterranean.greek'),
  ('mediterranean',                           'restaurants.mediterranean'),
  ('lebanese',                                'restaurants.middle_eastern.lebanese'),
  ('persian',                                 'restaurants.middle_eastern.persian'),
  ('turkish',                                 'restaurants.middle_eastern.turkish'),
  ('falafel|shawarma',                        'restaurants.middle_eastern'),
  ('french',                                  'restaurants.french'),
  ('spanish|tapas',                           'restaurants.spanish'),
  ('hawaiian|poke',                           'restaurants.hawaiian'),
  ('burgers?',                                'restaurants.american.burgers'),
  ('diner',                                   'restaurants.american.diner'),
  ('bar (&|and) grill',                       'restaurants.american.bar_and_grill'),
  ('cajun|creole',                            'restaurants.american.cajun_creole'),
  ('southern|soul food',                      'restaurants.american.southern'),
  ('bbq|barbecue|barbeque|smokehouse',        'restaurants.barbecue'),
  ('wings|chicken|pollo',                     'restaurants.chicken'),
  ('steakhouse|steak house',                  'restaurants.steakhouse'),
  ('seafood|crabs?|oysters?|lobster',         'restaurants.seafood'),
  ('sandwich(es)?|subs|hoagies?',             'restaurants.sandwiches'),
  ('salads?',                                 'restaurants.salad'),
  ('brunch|breakfast|pancakes?|waffles?',     'restaurants.breakfast_brunch'),
  ('vegan|vegetarian',                        'restaurants.vegetarian_vegan'),
  ('food truck',                              'restaurants.food_truck'),
  ('deli|delicatessen',                       'markets.deli'),
  ('bakery|panaderia|pasteleria',             'markets.bakery'),
  ('bagels?',                                 'markets.bakery.bagels'),
  ('ice cream|gelato|creamery|frozen yogurt', 'markets.desserts.ice_cream'),
  ('donuts?|doughnuts?',                      'markets.desserts.donuts'),
  ('candy|chocolates?|chocolatier',           'markets.desserts.candy_chocolate'),
  ('butcher|carniceria',                      'markets.butcher'),
  ('liquors?|spirits',                        'markets.wine_liquor'),
  ('bubble tea|boba',                         'coffee.bubble_tea'),
  ('juice|smoothies?',                        'coffee.juice_smoothies'),
  ('pub|tavern',                              'drinks.bar.pub'),
  ('sports bar',                              'drinks.bar.sports_bar'),
  ('wine bar',                                'drinks.bar.wine_bar'),
  ('hookah',                                  'drinks.bar.hookah_bar'),
  ('lounge',                                  'drinks.bar.lounge'),
  ('cocktails?',                              'drinks.bar.cocktail_bar'),
  ('brewery|brewing|brewhouse',               'drinks.brewery'),
  ('distillery',                              'drinks.distillery'),
  ('winery|vineyards?',                       'drinks.winery'))
INSERT INTO public.tag_keywords (pattern, category_id)
SELECT v.pattern, c.id FROM v JOIN public.categories c ON c.path = v.path::ltree;

DO $$ BEGIN
  IF (SELECT count(*) FROM public.tag_keywords) <> 65 THEN
    RAISE EXCEPTION 'tag_keywords seed: expected 65 rows, a category path is missing';
  END IF;
END $$;

-- Propose tags for live places that have no tag yet. Skips a proposal that was already
-- made for the same place and tag, whatever was decided, so a rejection stays rejected.
CREATE FUNCTION public.suggest_tags_from_names(p_proposed_by text)
  RETURNS integer
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_n integer;
BEGIN
  INSERT INTO change_events (event_type, entity_id, field, new_value, evidence)
  SELECT 'attribute_change', e.id, 'categories',
         jsonb_build_object('add_category', c.path::text),
         jsonb_build_object('method', 'name keyword', 'keyword', k.pattern, 'name', e.name,
                            'tag', c.name, 'proposed_by', p_proposed_by)
  FROM entities e
  JOIN tag_keywords k ON k.is_active AND e.name ~* ('\m(' || k.pattern || ')\M')
  JOIN categories c ON c.id = k.category_id
  WHERE e.status IN ('active', 'temporarily_closed')
    AND NOT EXISTS (SELECT 1 FROM entity_categories ec WHERE ec.entity_id = e.id)
    AND NOT EXISTS (SELECT 1 FROM change_events x
                    WHERE x.entity_id = e.id AND x.field = 'categories'
                      AND x.new_value = jsonb_build_object('add_category', c.path::text));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.suggest_tags_from_names(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suggest_tags_from_names(text) TO service_role;

-- Accept or reject one tag suggestion. Accepting adds the tag to the place.
CREATE FUNCTION public.decide_tag_suggestion(p_event bigint, p_accept boolean, p_decided_by text)
  RETURNS void
  LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v change_events%ROWTYPE; v_cat uuid;
BEGIN
  SELECT * INTO v FROM change_events WHERE id = p_event FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'pending' OR v.field IS DISTINCT FROM 'categories'
     OR NOT (v.new_value ? 'add_category') THEN
    RAISE EXCEPTION 'event % is not a pending tag suggestion', p_event;
  END IF;
  IF p_accept THEN
    SELECT id INTO v_cat FROM categories WHERE path = (v.new_value->>'add_category')::ltree;
    IF v_cat IS NULL THEN RAISE EXCEPTION 'tag % no longer exists', v.new_value->>'add_category'; END IF;
    INSERT INTO entity_categories (entity_id, category_id)
    VALUES (resolve_entity(v.entity_id), v_cat) ON CONFLICT DO NOTHING;
  END IF;
  UPDATE change_events
  SET status = CASE WHEN p_accept THEN 'approved' ELSE 'rejected' END,
      decided_by = p_decided_by, decided_at = now(),
      applied_at = CASE WHEN p_accept THEN now() END
  WHERE id = p_event;
END $$;
REVOKE EXECUTE ON FUNCTION public.decide_tag_suggestion(bigint, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_tag_suggestion(bigint, boolean, text) TO service_role;
