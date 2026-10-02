-- match_candidate_pairs joined a CTE to itself, which hid the spatial index on
-- source_records.location and compared every record with every other one.
-- Join the table directly so the index narrows each record to its neighbours.
-- Results are unchanged.
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.match_candidate_pairs(p_source_code text, p_max_m integer DEFAULT 75, p_min_sim real DEFAULT 0.6)
  RETURNS TABLE(record_a bigint, record_b bigint, distance_m integer, name_sim real,
                same_phone boolean, phone_conflict boolean, same_host boolean, host_conflict boolean)
  LANGUAGE sql STABLE SET search_path = public, extensions AS $$
  SELECT a.id, b.id, round(ST_Distance(a.location, b.location))::integer,
         similarity(match_name(a.name), match_name(b.name)),
         match_phone(a.phone) = match_phone(b.phone), match_phone(a.phone) <> match_phone(b.phone),
         match_host(a.website) = match_host(b.website), match_host(a.website) <> match_host(b.website)
  FROM sources s
  JOIN source_records a ON a.source_id = s.id
  JOIN source_records b ON b.source_id = a.source_id AND a.id < b.id
                       AND ST_DWithin(a.location, b.location, p_max_m)
  WHERE s.code = p_source_code
    AND a.match_status = 'unmatched' AND b.match_status = 'unmatched'
    AND NOT is_legal_entity_name(a.name) AND NOT is_legal_entity_name(b.name)
    AND similarity(match_name(a.name), match_name(b.name)) >= p_min_sim;
$$;
