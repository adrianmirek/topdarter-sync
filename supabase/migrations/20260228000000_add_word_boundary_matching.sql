-- Migration: Add word boundary matching for player search
-- Date: 2026-02-28
-- Description: Implement word boundary matching to prevent partial word matches
--              Example: 
--                - Search "ski" → matches "John Ski" but NOT "Walkowski", "Ossowski", "Polski"
--                - Search "Kowalski" → matches "Jan Kowalski" exactly
--                - Search "Kowal" → does NOT match "Jan Kowalski" (partial word)

-- Create a function to check if a search term matches complete words in a text
-- For single-word searches: checks if word exists in text
-- For multi-word searches: uses exact normalized match to prevent order issues
CREATE OR REPLACE FUNCTION nakka.word_boundary_match(
  full_text TEXT,
  search_term TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
AS $$
DECLARE
  normalized_text TEXT;
  normalized_search TEXT;
  text_word_array TEXT[];
  search_word_array TEXT[];
BEGIN
  -- Normalize both texts (remove accents, lowercase)
  normalized_text := nakka.normalize_polish_text(full_text);
  normalized_search := nakka.normalize_polish_text(search_term);
  
  -- Empty search matches everything
  IF normalized_search = '' OR normalized_search IS NULL THEN
    RETURN TRUE;
  END IF;
  
  IF normalized_text = '' OR normalized_text IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Split search term into words
  search_word_array := regexp_split_to_array(normalized_search, E'[\\s\\-_]+');
  
  -- Remove empty strings from array
  search_word_array := array_remove(search_word_array, '');
  search_word_array := array_remove(search_word_array, NULL);
  
  -- For multi-word searches, use exact normalized match to prevent order issues
  -- Example: "Adrian Mirek" should NOT match "Mirek Adrian"
  IF array_length(search_word_array, 1) > 1 THEN
    RETURN normalized_text = normalized_search;
  END IF;
  
  -- For single-word searches, check if word exists in text
  text_word_array := regexp_split_to_array(normalized_text, E'[\\s\\-_]+');
  text_word_array := array_remove(text_word_array, '');
  text_word_array := array_remove(text_word_array, NULL);
  
  -- Check if the single search word exists in text words
  RETURN search_word_array[1] = ANY(text_word_array);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION nakka.word_boundary_match(TEXT, TEXT) TO authenticated, anon;

COMMENT ON FUNCTION nakka.word_boundary_match(TEXT, TEXT) IS 
'Checks if a search term matches complete words in the text (not partial substrings).
For single-word searches: checks if word exists in text.
For multi-word searches: uses exact normalized match to prevent order issues.
Uses word boundary matching with spaces, hyphens, and underscores as separators.
Does NOT split on slashes - those are handled separately for combined player names.
Applies accent-insensitive normalization for Polish characters.
Examples:
- word_boundary_match(''Jacek Machocki'', ''Jacek'') = true (single word match)
- word_boundary_match(''Jacek Machocki'', ''Jacek Machocki'') = true (exact match)
- word_boundary_match(''Mirek Adrian'', ''Adrian Mirek'') = false (different order)
- word_boundary_match(''Walkowski'', ''ski'') = false (partial match)
- word_boundary_match(''John Ski'', ''ski'') = true (complete word match)';

-- Drop existing function
DROP FUNCTION IF EXISTS nakka.get_player_matches_by_nickname(TEXT[], INTEGER) CASCADE;

-- Recreate function with word boundary matching
CREATE OR REPLACE FUNCTION nakka.get_player_matches_by_nickname(
  search_nicknames TEXT[],
  match_limit INTEGER DEFAULT 30
)
RETURNS SETOF nakka.player_match_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  -- Validate input: ensure array is not empty
  IF search_nicknames IS NULL OR array_length(search_nicknames, 1) IS NULL THEN
    RAISE EXCEPTION 'search_nicknames array cannot be empty';
  END IF;

  RETURN QUERY
  WITH match_data AS (
    SELECT 
      t.tournament_id,
      t.nakka_identifier AS nakka_tournament_identifier,
      t.tournament_name,
      t.tournament_date,
      t.href AS tournament_href,
      
      tm.tournament_match_id,
      tm.nakka_match_identifier,
      tm.match_type,
      tm.href AS match_href,
      tm.match_date,
      
      -- Determine which player matched the search
      -- Check if second player matches any nickname but first player doesn't
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.second_player_name, nickname)
        ) AND NOT EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.first_player_name, nickname)
        )
        THEN tm.second_player_name
        ELSE tm.first_player_name
      END AS player_name,
      
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.second_player_name, nickname)
        ) AND NOT EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.first_player_name, nickname)
        )
        THEN tm.second_player_code
        ELSE tm.first_player_code
      END AS player_code,
      
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.second_player_name, nickname)
        ) AND NOT EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.first_player_name, nickname)
        )
        THEN tm.first_player_name
        ELSE tm.second_player_name
      END AS opponent_name,
      
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.second_player_name, nickname)
        ) AND NOT EXISTS (
          SELECT 1 FROM unnest(search_nicknames) AS nickname
          WHERE nakka.word_boundary_match(tm.first_player_name, nickname)
        )
        THEN tm.first_player_code
        ELSE tm.second_player_code
      END AS opponent_code,
      
      tm.imported_at
      
    FROM nakka.tournament_matches tm
    INNER JOIN nakka.tournaments t ON tm.tournament_id = t.tournament_id
    WHERE 
      -- Match if ANY nickname is found in either player name using word boundary matching
      -- BUT: If the search nickname doesn't contain '/' or '\', exclude combined player names (those with '/' or '\')
      --      If the search nickname contains '/' or '\', allow matching combined names normally
      EXISTS (
        SELECT 1 FROM unnest(search_nicknames) AS nickname
        WHERE (
          -- For nicknames without '/' or '\', only match player names that also don't contain '/' or '\'
          -- (exclude combined player names when searching for individual players)
          (
            nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' AND (
              (
                nakka.word_boundary_match(tm.first_player_name, nickname)
                AND tm.first_player_name NOT LIKE '%/%'
                AND tm.first_player_name NOT LIKE '%\%'
              )
              OR
              (
                nakka.word_boundary_match(tm.second_player_name, nickname)
                AND tm.second_player_name NOT LIKE '%/%'
                AND tm.second_player_name NOT LIKE '%\%'
              )
            )
          )
          OR
          -- For nicknames with '/' or '\', use substring matching (including combined names)
          (
            (nickname LIKE '%/%' OR nickname LIKE '%\%') AND (
              nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
              OR nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            )
          )
        )
      )
    ORDER BY t.tournament_date DESC, tm.match_date DESC, tm.tournament_match_id DESC
    LIMIT match_limit
  )
  SELECT 
    md.tournament_id,
    md.nakka_tournament_identifier,
    md.tournament_name,
    md.tournament_date,
    md.tournament_href,
    md.tournament_match_id,
    md.nakka_match_identifier,
    md.match_type,
    md.match_href,
    md.match_date,
    md.player_name,
    md.player_code,
    md.opponent_name,
    md.opponent_code,
    
    -- Player statistics
    pr.average_score,
    pr.first_nine_avg,
    pr.checkout_percentage,
    pr.score_60_count,
    pr.score_100_count,
    pr.score_140_count,
    pr.score_180_count,
    pr.high_finish,
    pr.best_leg,
    pr.worst_leg,
    pr.player_score,
    pr.opponent_score,
    
    -- Opponent statistics
    opr.average_score AS opponent_average_score,
    opr.first_nine_avg AS opponent_first_nine_avg,
    opr.checkout_percentage AS opponent_checkout_percentage,
    opr.score_60_count AS opponent_score_60_count,
    opr.score_100_count AS opponent_score_100_count,
    opr.score_140_count AS opponent_score_140_count,
    opr.score_180_count AS opponent_score_180_count,
    opr.high_finish AS opponent_high_finish,
    opr.best_leg AS opponent_best_leg,
    opr.worst_leg AS opponent_worst_leg,
    
    md.imported_at
    
  FROM match_data md
  LEFT JOIN nakka.tournament_match_player_results pr 
    ON pr.tournament_match_id = md.tournament_match_id
    AND pr.nakka_match_player_identifier = (
      -- Construct player identifier: {tournamentId}_{matchType}_{round}_{playerCode}
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.player_code
    )
  LEFT JOIN nakka.tournament_match_player_results opr 
    ON opr.tournament_match_id = md.tournament_match_id
    AND opr.nakka_match_player_identifier = (
      -- Construct opponent identifier: {tournamentId}_{matchType}_{round}_{opponentCode}
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.opponent_code
    )
  ORDER BY md.tournament_date DESC, md.match_date DESC, md.tournament_match_id DESC;
END;
$$;

-- Grant execute permission to authenticated and anon roles
GRANT EXECUTE ON FUNCTION nakka.get_player_matches_by_nickname(TEXT[], INTEGER) TO authenticated, anon;

-- Add comments
COMMENT ON FUNCTION nakka.get_player_matches_by_nickname(TEXT[], INTEGER) IS 
'Retrieves player matches by nickname(s) from the database using word boundary matching.
Uses word boundary matching to prevent partial word matches:
- "ski" matches "John Ski" but NOT "Walkowski", "Ossowski", "Polski"
- "Kowalski" matches "Jan Kowalski" exactly
- "Kowal" does NOT match "Jan Kowalski" (partial word)
Handles combined player names intelligently (names with / or \ separators):
- When searching for individual names (e.g., "Sebastian Szymkowiak"), excludes combined names (e.g., "Mateusz Obroszko/Sebastian Szymkowiak")
- When searching for combined names (e.g., "Mateusz Obroszko/Sebastian Szymkowiak" or "Mateusz Obroszko\Sebastian Szymkowiak"), uses substring matching for those combined matches
- Returns matches ordered by tournament date (newest first)
- Includes player and opponent statistics when available';

-- ============================================================================
-- Update get_player_matches_by_tournament_and_nickname with word boundary matching
-- ============================================================================

DROP FUNCTION IF EXISTS nakka.get_player_matches_by_tournament_and_nickname(TEXT, TEXT, INTEGER) CASCADE;

CREATE OR REPLACE FUNCTION nakka.get_player_matches_by_tournament_and_nickname(
  search_tournament_keyword TEXT,
  search_nickname TEXT,
  match_limit INTEGER DEFAULT 30
)
RETURNS SETOF nakka.player_match_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH match_data AS (
    SELECT 
      t.tournament_id,
      t.nakka_identifier AS nakka_tournament_identifier,
      t.tournament_name,
      t.tournament_date,
      t.href AS tournament_href,
      
      tm.tournament_match_id,
      tm.nakka_match_identifier,
      tm.match_type,
      tm.href AS match_href,
      tm.match_date,
      
      -- Determine which player matched the search
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.second_player_name
        ELSE tm.first_player_name
      END AS player_name,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.second_player_code
        ELSE tm.first_player_code
      END AS player_code,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.first_player_name
        ELSE tm.second_player_name
      END AS opponent_name,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.first_player_code
        ELSE tm.second_player_code
      END AS opponent_code,
      
      tm.imported_at
      
    FROM nakka.tournament_matches tm
    INNER JOIN nakka.tournaments t ON tm.tournament_id = t.tournament_id
    WHERE 
      -- Filter by tournament keyword (accent-insensitive, substring match for tournament name)
      nakka.normalize_polish_text(t.tournament_name) LIKE '%' || nakka.normalize_polish_text(search_tournament_keyword) || '%'
      -- Match if nickname is found as complete word in either player name
      AND (
        nakka.word_boundary_match(tm.first_player_name, search_nickname)
        OR nakka.word_boundary_match(tm.second_player_name, search_nickname)
      )
    ORDER BY t.tournament_date DESC, tm.match_date DESC, tm.tournament_match_id DESC
    LIMIT match_limit
  )
  SELECT 
    md.tournament_id,
    md.nakka_tournament_identifier,
    md.tournament_name,
    md.tournament_date,
    md.tournament_href,
    md.tournament_match_id,
    md.nakka_match_identifier,
    md.match_type,
    md.match_href,
    md.match_date,
    md.player_name,
    md.player_code,
    md.opponent_name,
    md.opponent_code,
    
    -- Player statistics
    pr.average_score,
    pr.first_nine_avg,
    pr.checkout_percentage,
    pr.score_60_count,
    pr.score_100_count,
    pr.score_140_count,
    pr.score_180_count,
    pr.high_finish,
    pr.best_leg,
    pr.worst_leg,
    pr.player_score,
    pr.opponent_score,
    
    -- Opponent statistics
    opr.average_score AS opponent_average_score,
    opr.first_nine_avg AS opponent_first_nine_avg,
    opr.checkout_percentage AS opponent_checkout_percentage,
    opr.score_60_count AS opponent_score_60_count,
    opr.score_100_count AS opponent_score_100_count,
    opr.score_140_count AS opponent_score_140_count,
    opr.score_180_count AS opponent_score_180_count,
    opr.high_finish AS opponent_high_finish,
    opr.best_leg AS opponent_best_leg,
    opr.worst_leg AS opponent_worst_leg,
    
    md.imported_at
    
  FROM match_data md
  LEFT JOIN nakka.tournament_match_player_results pr 
    ON pr.tournament_match_id = md.tournament_match_id
    AND pr.nakka_match_player_identifier = (
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.player_code
    )
  LEFT JOIN nakka.tournament_match_player_results opr 
    ON opr.tournament_match_id = md.tournament_match_id
    AND opr.nakka_match_player_identifier = (
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.opponent_code
    )
  ORDER BY md.tournament_date DESC, md.match_date DESC, md.tournament_match_id DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION nakka.get_player_matches_by_tournament_and_nickname(TEXT, TEXT, INTEGER) TO authenticated, anon;

COMMENT ON FUNCTION nakka.get_player_matches_by_tournament_and_nickname(TEXT, TEXT, INTEGER) IS 
'Retrieves matches for a player filtered by tournament keyword and nickname. 
Uses word boundary matching for player names to prevent partial matches.
Tournament name uses substring matching. 
Returns matches where the nickname matches a complete word in either player name within tournaments matching the keyword. 
The matched player is always returned as "player" (first position). 
Results are grouped by tournament (ordered by tournament_date DESC - most recent first), then within each tournament ordered by match_date DESC (latest matches first), and limited to the specified number (default 30).';

-- ============================================================================
-- Update get_player_match_by_id_and_nickname with word boundary matching
-- ============================================================================

DROP FUNCTION IF EXISTS nakka.get_player_match_by_id_and_nickname(INTEGER, TEXT) CASCADE;

CREATE OR REPLACE FUNCTION nakka.get_player_match_by_id_and_nickname(
  match_id INTEGER,
  search_nickname TEXT
)
RETURNS nakka.player_match_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  result nakka.player_match_result;
BEGIN
  WITH match_data AS (
    SELECT 
      t.tournament_id,
      t.nakka_identifier AS nakka_tournament_identifier,
      t.tournament_name,
      t.tournament_date,
      t.href AS tournament_href,
      
      tm.tournament_match_id,
      tm.nakka_match_identifier,
      tm.match_type,
      tm.href AS match_href,
      tm.match_date,
      
      -- Determine which player matched the search
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.second_player_name
        ELSE tm.first_player_name
      END AS player_name,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.second_player_code
        ELSE tm.first_player_code
      END AS player_code,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.first_player_name
        ELSE tm.second_player_name
      END AS opponent_name,
      
      CASE 
        WHEN nakka.word_boundary_match(tm.second_player_name, search_nickname)
             AND NOT nakka.word_boundary_match(tm.first_player_name, search_nickname)
        THEN tm.first_player_code
        ELSE tm.second_player_code
      END AS opponent_code,
      
      tm.imported_at
      
    FROM nakka.tournament_matches tm
    INNER JOIN nakka.tournaments t ON tm.tournament_id = t.tournament_id
    WHERE 
      tm.tournament_match_id = match_id
      AND (
        nakka.word_boundary_match(tm.first_player_name, search_nickname)
        OR nakka.word_boundary_match(tm.second_player_name, search_nickname)
      )
  )
  SELECT 
    md.tournament_id,
    md.nakka_tournament_identifier,
    md.tournament_name,
    md.tournament_date,
    md.tournament_href,
    md.tournament_match_id,
    md.nakka_match_identifier,
    md.match_type,
    md.match_href,
    md.match_date,
    md.player_name,
    md.player_code,
    md.opponent_name,
    md.opponent_code,
    
    -- Player statistics
    pr.average_score,
    pr.first_nine_avg,
    pr.checkout_percentage,
    pr.score_60_count,
    pr.score_100_count,
    pr.score_140_count,
    pr.score_180_count,
    pr.high_finish,
    pr.best_leg,
    pr.worst_leg,
    pr.player_score,
    pr.opponent_score,
    
    -- Opponent statistics
    opr.average_score AS opponent_average_score,
    opr.first_nine_avg AS opponent_first_nine_avg,
    opr.checkout_percentage AS opponent_checkout_percentage,
    opr.score_60_count AS opponent_score_60_count,
    opr.score_100_count AS opponent_score_100_count,
    opr.score_140_count AS opponent_score_140_count,
    opr.score_180_count AS opponent_score_180_count,
    opr.high_finish AS opponent_high_finish,
    opr.best_leg AS opponent_best_leg,
    opr.worst_leg AS opponent_worst_leg,
    
    md.imported_at
    
  INTO result
  FROM match_data md
  LEFT JOIN nakka.tournament_match_player_results pr 
    ON pr.tournament_match_id = md.tournament_match_id
    AND pr.nakka_match_player_identifier = (
      -- Construct player identifier: {tournamentId}_{matchType}_{round}_{playerCode}
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.player_code
    )
  LEFT JOIN nakka.tournament_match_player_results opr 
    ON opr.tournament_match_id = md.tournament_match_id
    AND opr.nakka_match_player_identifier = (
      REGEXP_REPLACE(md.nakka_match_identifier, '_[^_]+_[^_]+$', '') || '_' || md.opponent_code
    );
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION nakka.get_player_match_by_id_and_nickname(INTEGER, TEXT) TO authenticated, anon;

COMMENT ON FUNCTION nakka.get_player_match_by_id_and_nickname(INTEGER, TEXT) IS 
'Retrieves a single match by tournament_match_id filtered by nickname using word boundary matching. 
The matched player is always returned as "player" (first position). 
Returns null if match not found or nickname does not match.';
