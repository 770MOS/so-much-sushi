-- More ways of writing the same address are recognised as the same (learned from the 70
-- address proposals left after the first All the Places load):
--   * a unit letter on the street number: "6973-H Hechinger Dr", "3556B S Jefferson St"
--     (only when attached or hyphenated, so DC's "1825 I St" is never confused with "K St");
--   * more street words: Center/Ctr, Plaza/Plz, Way, Trail, Crossing, Point, Mall,
--     Turnpike/Tpke, Expressway, Freeway, Alley, Loop, Bypass, Commons, Building/Bldg,
--     Floor, Room, Space;
--   * ordinal words: "Seventh Street" = "7th St"; DC's "Eye Street" = "I St";
--   * a place name before the street number: "Lee Heights Shops, 4526 Cherry Hill Rd";
--   * spacing inside names: "Gate House Plz" = "Gatehouse Plaza", "Mac Arthur" = "MacArthur".
-- Pending address proposals that are now only formatting are closed.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.norm_address(p text)
  RETURNS text
  LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path TO '' AS $$
  SELECT regexp_replace(trim(regexp_replace(
           ' ' || s4 || ' ',
           ' (street|st|road|rd|drive|dr|avenue|ave|av|boulevard|blvd|lane|ln|court|ct|place|pl|highway|hwy|parkway|pkwy|terrace|ter|circle|cir|square|sq|center|ctr|centre|plaza|plz|way|wy|trail|trl|crossing|xing|point|pt|mall|turnpike|tpke|expressway|expy|freeway|fwy|alley|aly|loop|bypass|byp|commons|cmns|north|n|south|s|east|e|west|w|northwest|nw|northeast|ne|southwest|sw|southeast|se|suite|ste|unit|apartment|apt|number|no|building|bldg|floor|fl|room|rm|space|spc)(?= )',
           ' ', 'g')), ' +', ' ', 'g')
  FROM (SELECT
          -- ordinal words, and DC's Eye Street
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
          regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
            ' ' || s3 || ' ',
            ' first ', ' 1st ', 'g'), ' second ', ' 2nd ', 'g'), ' third ', ' 3rd ', 'g'), ' fourth ', ' 4th ', 'g'),
            ' fifth ', ' 5th ', 'g'), ' sixth ', ' 6th ', 'g'), ' seventh ', ' 7th ', 'g'), ' eighth ', ' 8th ', 'g'),
            ' ninth ', ' 9th ', 'g'), ' tenth ', ' 10th ', 'g'), ' eye ', ' i ', 'g') AS s4
        FROM (SELECT
                -- drop a place name before the street number
                CASE WHEN s2 ~ '\d' THEN regexp_replace(s2, '^[^0-9]*', '') ELSE s2 END AS s3
              FROM (SELECT
                      regexp_replace(
                        -- a unit letter attached to the street number: 6973-H, 3556B
                        regexp_replace(lower(coalesce(p, '')), '^(\s*\d+)-?[a-z](?![a-z])', '\1'),
                        '[^a-z0-9]+', ' ', 'g') AS s2) a) b) c;
$$;

CREATE OR REPLACE FUNCTION public.values_equivalent(p_field text, a text, b text)
  RETURNS boolean
  LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
  SELECT CASE
    WHEN a IS NULL OR b IS NULL THEN a IS NOT DISTINCT FROM b
    WHEN p_field = 'phone' THEN match_phone(a) IS NOT NULL AND match_phone(a) = match_phone(b)
    WHEN p_field = 'website' THEN match_host(a) IS NOT NULL AND match_host(a) = match_host(b)
    WHEN p_field = 'postal_code' THEN left(regexp_replace(a, '\D', '', 'g'), 5) = left(regexp_replace(b, '\D', '', 'g'), 5)
    WHEN p_field IN ('city', 'state') THEN upper(trim(a)) = upper(trim(b))
    WHEN p_field = 'address' THEN norm_address(a) = norm_address(b)
         OR (length(norm_address(a)) >= 5 AND replace(norm_address(a), ' ', '') = replace(norm_address(b), ' ', ''))
         OR (length(norm_address(a)) >= 5 AND length(norm_address(b)) >= 5
             AND (norm_address(a) LIKE norm_address(b) || ' %' OR norm_address(b) LIKE norm_address(a) || ' %'))
    WHEN p_field = 'name' THEN match_name(a) = match_name(b)
         OR (least(length(match_name(a)), length(match_name(b))) >= 4
             AND (strpos(match_name(a), match_name(b)) > 0 OR strpos(match_name(b), match_name(a)) > 0))
    ELSE a = b END;
$$;

UPDATE public.change_events
SET status = 'superseded', decided_by = 'migration: address formatting only', decided_at = now()
WHERE status = 'pending' AND event_type = 'attribute_change' AND field = 'address'
  AND public.values_equivalent('address', old_value #>> '{}', new_value #>> '{}');
