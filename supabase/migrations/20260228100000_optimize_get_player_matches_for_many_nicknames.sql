-- Migration: Optimize get_player_matches_by_nickname for handling many nicknames
-- Created: 2026-02-28
-- Description: Increase statement timeout and optimize query for better performance with many nicknames
--              Uses optimized matching logic to prevent timeout issues

-- Drop existing function
DROP FUNCTION IF EXISTS nakka.get_player_matches_by_nickname(TEXT[], INTEGER) CASCADE;

-- Recreate function with increased timeout and optimized matching
CREATE OR REPLACE FUNCTION nakka.get_player_matches_by_nickname(
  search_nicknames TEXT[],
  match_limit INTEGER DEFAULT 30
)
RETURNS SETOF nakka.player_match_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_nickname TEXT;
  v_is_combined BOOLEAN;
  v_first_matches BOOLEAN;
  v_second_matches BOOLEAN;
BEGIN
  -- Validate input: ensure array is not empty
  IF search_nicknames IS NULL OR array_length(search_nicknames, 1) IS NULL THEN
    RAISE EXCEPTION 'search_nicknames array cannot be empty';
  END IF;

  -- Increase statement timeout for this function to 30 seconds
  PERFORM set_config('statement_timeout', '30000', true);

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
        WHEN (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.second_player_name, nickname)
                AND tm.second_player_name NOT LIKE '%/%'
                AND tm.second_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        ) AND NOT (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.first_player_name, nickname)
                AND tm.first_player_name NOT LIKE '%/%'
                AND tm.first_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        )
        THEN tm.second_player_name
        ELSE tm.first_player_name
      END AS player_name,
      
      CASE 
        WHEN (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.second_player_name, nickname)
                AND tm.second_player_name NOT LIKE '%/%'
                AND tm.second_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        ) AND NOT (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.first_player_name, nickname)
                AND tm.first_player_name NOT LIKE '%/%'
                AND tm.first_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        )
        THEN tm.second_player_code
        ELSE tm.first_player_code
      END AS player_code,
      
      CASE 
        WHEN (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.second_player_name, nickname)
                AND tm.second_player_name NOT LIKE '%/%'
                AND tm.second_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        ) AND NOT (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.first_player_name, nickname)
                AND tm.first_player_name NOT LIKE '%/%'
                AND tm.first_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        )
        THEN tm.first_player_name
        ELSE tm.second_player_name
      END AS opponent_name,
      
      CASE 
        WHEN (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.second_player_name, nickname)
                AND tm.second_player_name NOT LIKE '%/%'
                AND tm.second_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        ) AND NOT (
          SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
          WHERE (
            CASE 
              WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
                nakka.word_boundary_match(tm.first_player_name, nickname)
                AND tm.first_player_name NOT LIKE '%/%'
                AND tm.first_player_name NOT LIKE '%\%'
              ELSE
                nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
            END
          )
        )
        THEN tm.first_player_code
        ELSE tm.second_player_code
      END AS opponent_code,
      
      tm.imported_at
      
    FROM nakka.tournament_matches tm
    INNER JOIN nakka.tournaments t ON tm.tournament_id = t.tournament_id
    WHERE 
      -- Match if ANY nickname is found in either player name
      (
        SELECT COUNT(*) > 0 FROM unnest(search_nicknames) AS nickname
        WHERE (
          CASE 
            WHEN nickname NOT LIKE '%/%' AND nickname NOT LIKE '%\%' THEN
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
            ELSE
              nakka.normalize_polish_text(tm.first_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
              OR nakka.normalize_polish_text(tm.second_player_name) LIKE '%' || nakka.normalize_polish_text(nickname) || '%'
          END
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
Includes 30-second statement timeout to handle complex queries with many nicknames.
Uses word boundary matching to prevent partial word matches:
- "ski" matches "John Ski" but NOT "Walkowski", "Ossowski", "Polski"
- "Kowalski" matches "Jan Kowalski" exactly
- "Kowal" does NOT match "Jan Kowalski" (partial word)
Handles combined player names intelligently (names with / or \ separators):
- When searching for individual names (e.g., "Sebastian Szymkowiak"), excludes combined names (e.g., "Mateusz Obroszko/Sebastian Szymkowiak")
- When searching for combined names (e.g., "Mateusz Obroszko/Sebastian Szymkowiak" or "Mateusz Obroszko\Sebastian Szymkowiak"), uses substring matching for those combined matches
- Returns matches ordered by tournament date (newest first)
- Includes player and opponent statistics when available
Performance: Statement timeout set to 30 seconds. Uses scalar subqueries for compatibility and to prevent set-returning function errors';

