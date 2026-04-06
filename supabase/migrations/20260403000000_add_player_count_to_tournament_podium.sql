-- =====================================================================
-- Migration: Add player_count to tournament_podium_result type and
--            get_top_three_players_and_matches function
-- Purpose: Expose the total number of participants per tournament so
--          the UI can display it alongside the tournament name.
-- Date: 2026-04-03
-- =====================================================================

-- Drop existing function first (depends on the type)
DROP FUNCTION IF EXISTS nakka.get_top_three_players_and_matches();

-- Drop existing composite type (CASCADE removes any remaining deps)
DROP TYPE IF EXISTS nakka.tournament_podium_result CASCADE;

-- -----------------------------------------------------------------------
-- PART 1: Composite type — now includes player_count
-- -----------------------------------------------------------------------

CREATE TYPE nakka.tournament_podium_result AS (
  -- Tournament info
  tournament_id            INTEGER,
  tournament_name          TEXT,
  tournament_date          TIMESTAMPTZ,
  nakka_identifier         TEXT,
  tournament_href          TEXT,

  -- Total number of participants in the tournament
  player_count             INTEGER,

  -- Podium players JSON array (rank 1, 2, 3)
  podium_players           JSONB,

  -- Final match JSON (nullable)
  final_match              JSONB,

  -- Semi-final matches JSON array (0-2 elements)
  semi_final_matches       JSONB,

  -- Third-place match JSON (nullable)
  third_place_match        JSONB,

  -- Whether a dedicated third-place match exists
  has_third_place_match    BOOLEAN
);

-- -----------------------------------------------------------------------
-- PART 2: Main function
-- -----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION nakka.get_top_three_players_and_matches()
RETURNS SETOF nakka.tournament_podium_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH
  -- Step 1: Tournaments in the last 7 days that have completed match imports
  recent_tournaments AS (
    SELECT
      t.tournament_id,
      t.tournament_name,
      t.tournament_date,
      t.nakka_identifier,
      t.href AS tournament_href
    FROM nakka.tournaments t
    WHERE t.tournament_date >= NOW() - INTERVAL '8 days'
      AND t.match_import_status = 'completed'
    ORDER BY t.tournament_date DESC
  ),

  -- Step 2: Count total participants per tournament.
  --         All rows in tournament_player_stats represent one player each,
  --         so a simple COUNT(*) grouped by tournament_id is sufficient.
  player_counts AS (
    SELECT
      tps.tournament_id,
      COUNT(*) AS player_count
    FROM nakka.tournament_player_stats tps
    INNER JOIN recent_tournaments rt ON rt.tournament_id = tps.tournament_id
    GROUP BY tps.tournament_id
  ),

  -- Step 3: Calculate global top 3 winners (rank 1 players) based on average score
  global_top_winners AS (
    SELECT
      tps.player_id,
      AVG(tps.average_score) AS global_avg_score
    FROM nakka.tournament_player_stats tps
    INNER JOIN recent_tournaments rt ON rt.tournament_id = tps.tournament_id
    WHERE tps.rank = 1
      AND tps.import_error IS NULL
      AND tps.average_score IS NOT NULL
    GROUP BY tps.player_id
    ORDER BY global_avg_score DESC
    LIMIT 3
  ),

  -- Step 4: Top 3 ranked players per tournament from tournament_player_stats
  -- Player names are resolved from any match in the tournament where the player appears
  -- (not limited to final/semi-final), so names are always populated regardless of match type values
  top_players AS (
    SELECT
      tps.tournament_id,
      jsonb_agg(
        jsonb_build_object(
          'rank',             tps.rank,
          'player_id',        tps.player_id,
          'player_name',      COALESCE(
            (SELECT tm.first_player_name
               FROM nakka.tournament_matches tm
              WHERE tm.tournament_id = tps.tournament_id
                AND tm.first_player_code = tps.player_id
                ORDER BY tm.match_date DESC
              LIMIT 1),
            (SELECT tm.second_player_name
               FROM nakka.tournament_matches tm
              WHERE tm.tournament_id = tps.tournament_id
                AND tm.second_player_code = tps.player_id
                ORDER BY tm.match_date DESC
              LIMIT 1),
            tps.player_id
          ),
          'score_100_count',  tps.score_100_count,
          'score_140_count',  tps.score_140_count,
          'score_170_count',  tps.score_170_count,
          'score_180_count',  tps.score_180_count,
          'high_finish',      tps.high_finish,
          'best_leg',         tps.best_leg,
          'average_score',    tps.average_score,
          'first_nine_avg',   tps.first_nine_avg
        )
        ORDER BY tps.rank
      ) AS podium_players
    FROM nakka.tournament_player_stats tps
    INNER JOIN recent_tournaments rt ON rt.tournament_id = tps.tournament_id
    WHERE tps.rank BETWEEN 1 AND 3
      AND tps.import_error IS NULL
    GROUP BY tps.tournament_id
  ),

  -- Step 5: Collect codes of top-3 players per tournament for match lookup
  top_player_codes AS (
    SELECT
      tps.tournament_id,
      array_agg(tps.player_id) AS player_codes
    FROM nakka.tournament_player_stats tps
    INNER JOIN recent_tournaments rt ON rt.tournament_id = tps.tournament_id
    WHERE tps.rank BETWEEN 1 AND 3
      AND tps.import_error IS NULL
    GROUP BY tps.tournament_id
  ),

  -- Step 6: Knockout matches involving at least one top-3 player, ranked latest-first.
  -- Strategy: exclude round-robin (match_type = 'rr'), filter by top player codes,
  -- then rank by tournament_match_id DESC so the final (last match) gets rank 1,
  -- the two semi-finals get ranks 2 and 3. No dependency on match_type string values.
  key_matches_ranked AS (
    SELECT
      tm.tournament_id,
      tm.tournament_match_id,
      tm.match_type,
      tm.first_player_name,
      tm.first_player_code,
      tm.second_player_name,
      tm.second_player_code,
      tm.href AS match_href,
      ROW_NUMBER() OVER (
        PARTITION BY tm.tournament_id
        ORDER BY tm.match_date DESC, tm.tournament_match_id DESC
      ) AS match_rank,
      -- First player stats
      jsonb_build_object(
        'player_score',       fp.player_score,
        'opponent_score',     fp.opponent_score,
        'average_score',      fp.average_score,
        'first_nine_avg',     fp.first_nine_avg,
        'score_100_count',    fp.score_100_count,
        'score_140_count',    fp.score_140_count,
        'score_180_count',    fp.score_180_count,
        'high_finish',        fp.high_finish,
        'best_leg',           fp.best_leg
      ) AS first_player_stats,
      -- Second player stats
      jsonb_build_object(
        'player_score',       sp.player_score,
        'opponent_score',     sp.opponent_score,
        'average_score',      sp.average_score,
        'first_nine_avg',     sp.first_nine_avg,
        'score_100_count',    sp.score_100_count,
        'score_140_count',    sp.score_140_count,
        'score_180_count',    sp.score_180_count,
        'high_finish',        sp.high_finish,
        'best_leg',           sp.best_leg
      ) AS second_player_stats
    FROM nakka.tournament_matches tm
    INNER JOIN recent_tournaments rt    ON rt.tournament_id  = tm.tournament_id
    INNER JOIN top_player_codes tpc     ON tpc.tournament_id = tm.tournament_id
    LEFT JOIN nakka.tournament_match_player_results fp
      ON fp.tournament_match_id = tm.tournament_match_id
      AND fp.nakka_match_player_identifier =
          REGEXP_REPLACE(tm.nakka_match_identifier, '_[^_]+_[^_]+$', '')
          || '_' || tm.first_player_code
    LEFT JOIN nakka.tournament_match_player_results sp
      ON sp.tournament_match_id = tm.tournament_match_id
      AND sp.nakka_match_player_identifier =
          REGEXP_REPLACE(tm.nakka_match_identifier, '_[^_]+_[^_]+$', '')
          || '_' || tm.second_player_code
    WHERE tm.match_type != 'rr'   -- exclude round-robin regardless of other type names
      AND (
        tm.first_player_code  = ANY(tpc.player_codes)
        OR tm.second_player_code = ANY(tpc.player_codes)
      )
  ),

  -- Step 7: Keep only the top 3 knockout matches (final + 2 semi-finals)
  key_matches AS (
    SELECT * FROM key_matches_ranked WHERE match_rank <= 3
  ),

  -- Step 8: Aggregate per tournament — rank 1 = final, ranks 2-3 = semi-finals
  matches_by_tournament AS (
    SELECT
      km.tournament_id,
      -- Final: match with the highest tournament_match_id (most recent = final)
      (jsonb_agg(
        jsonb_build_object(
          'match_id',           km.tournament_match_id,
          'match_href',         km.match_href,
          'first_player_name',  km.first_player_name,
          'first_player_code',  km.first_player_code,
          'second_player_name', km.second_player_name,
          'second_player_code', km.second_player_code,
          'first_player_stats', km.first_player_stats,
          'second_player_stats',km.second_player_stats
        )
      ) FILTER (WHERE km.match_rank = 1)) -> 0 AS final_match,
      -- Semi-finals: the next two most recent knockout matches
      jsonb_agg(
        jsonb_build_object(
          'match_id',           km.tournament_match_id,
          'match_href',         km.match_href,
          'first_player_name',  km.first_player_name,
          'first_player_code',  km.first_player_code,
          'second_player_name', km.second_player_name,
          'second_player_code', km.second_player_code,
          'first_player_stats', km.first_player_stats,
          'second_player_stats',km.second_player_stats
        )
      ) FILTER (WHERE km.match_rank IN (2, 3)) AS semi_final_matches,
      -- Third-place match not detected via match_type; always null
      NULL::jsonb AS third_place_match,
      FALSE       AS has_third_place_match
    FROM key_matches km
    GROUP BY km.tournament_id
  ),

  -- Step 9: Identify tournaments won by global top 3 winners
  tournament_winner AS (
    SELECT
      tps.tournament_id,
      tps.player_id AS winner_id
    FROM nakka.tournament_player_stats tps
    WHERE tps.rank = 1
      AND tps.import_error IS NULL
  ),

  -- Step 10: Winner's (rank 1) average score per tournament for intra-day ordering
  winner_avg AS (
    SELECT
      tps.tournament_id,
      tps.average_score AS winner_avg_score
    FROM nakka.tournament_player_stats tps
    INNER JOIN recent_tournaments rt ON rt.tournament_id = tps.tournament_id
    WHERE tps.rank = 1
      AND tps.import_error IS NULL
  )

  -- Final SELECT: join all CTEs and order by global top winners first,
  -- then by day DESC, then by winner's average score DESC within each day
  SELECT
    rt.tournament_id,
    rt.tournament_name,
    rt.tournament_date,
    rt.nakka_identifier,
    rt.tournament_href,
    COALESCE(pc.player_count, 0)::INTEGER                AS player_count,
    COALESCE(tp.podium_players, '[]'::jsonb)             AS podium_players,
    mbt.final_match,
    COALESCE(mbt.semi_final_matches, '[]'::jsonb)        AS semi_final_matches,
    mbt.third_place_match,
    COALESCE(mbt.has_third_place_match, FALSE)           AS has_third_place_match
  FROM recent_tournaments rt
  LEFT JOIN player_counts pc           ON pc.tournament_id = rt.tournament_id
  LEFT JOIN top_players tp             ON tp.tournament_id = rt.tournament_id
  LEFT JOIN matches_by_tournament mbt  ON mbt.tournament_id = rt.tournament_id
  LEFT JOIN tournament_winner tw       ON tw.tournament_id  = rt.tournament_id
  LEFT JOIN winner_avg wa              ON wa.tournament_id  = rt.tournament_id
  LEFT JOIN global_top_winners gtw     ON gtw.player_id     = tw.winner_id
  ORDER BY
    -- Tournaments won by global top 3 winners come first
    CASE WHEN gtw.player_id IS NOT NULL THEN 0 ELSE 1 END,
    -- Among global top winner tournaments, order by winner's global average DESC
    gtw.global_avg_score DESC NULLS LAST,
    -- Group remaining tournaments by calendar day DESC
    DATE(rt.tournament_date) DESC,
    -- Within each day, order by winner's average score DESC
    wa.winner_avg_score DESC NULLS LAST;
END;
$$;

-- Grant execute to both roles (public feature)
GRANT EXECUTE ON FUNCTION nakka.get_top_three_players_and_matches() TO anon, authenticated;

COMMENT ON FUNCTION nakka.get_top_three_players_and_matches() IS
'Returns podium data (top 3 players + key match details + player count) for all
 tournaments from the last 8 days that have completed match imports. Includes
 final, semi-final and optional third-place match data, plus the total number of
 participants (player_count) per tournament. Results are ordered with tournaments
 won by the global top 3 winners (based on average score) first, sorted among
 themselves by the winner''s global average score DESC, then remaining tournaments
 grouped by calendar day DESC and within each day ordered by the 1st-place winner
 average score DESC. Accessible to anon users.';
