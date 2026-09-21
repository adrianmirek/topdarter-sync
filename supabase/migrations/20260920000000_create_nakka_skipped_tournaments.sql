-- =====================================================================
-- Migration: Create nakka.skipped_tournaments
-- Purpose: Store Nakka tournaments that should be skipped during import
-- Date: 2026-09-20
-- Column types match nakka.tournaments
-- =====================================================================

CREATE TABLE IF NOT EXISTS nakka.skipped_tournaments (
  skipped_tournament_id SERIAL PRIMARY KEY,
  nakka_identifier TEXT NOT NULL UNIQUE,
  tournament_name TEXT NOT NULL,
  href TEXT NOT NULL,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  league_identifier TEXT DEFAULT NULL,
  league_href TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_nakka_skipped_tournaments_identifier
  ON nakka.skipped_tournaments (nakka_identifier);

CREATE INDEX IF NOT EXISTS idx_nakka_skipped_tournaments_league_identifier
  ON nakka.skipped_tournaments (league_identifier)
  WHERE league_identifier IS NOT NULL;

COMMENT ON TABLE nakka.skipped_tournaments IS
  'Stores Nakka tournaments that should be skipped during import (n01darts.com)';
COMMENT ON COLUMN nakka.skipped_tournaments.nakka_identifier IS
  'Unique identifier from Nakka platform (e.g., t_WWGB_9024)';
COMMENT ON COLUMN nakka.skipped_tournaments.tournament_name IS
  'Display name of the skipped tournament';
COMMENT ON COLUMN nakka.skipped_tournaments.href IS
  'URL/href of the skipped tournament page';
COMMENT ON COLUMN nakka.skipped_tournaments.imported_at IS
  'Timestamp when the skipped tournament record was created';
COMMENT ON COLUMN nakka.skipped_tournaments.league_identifier IS
  'Identifier for the league this tournament belongs to (NULL if not part of a league)';
COMMENT ON COLUMN nakka.skipped_tournaments.league_href IS
  'URL/href for the league page (NULL if not part of a league)';

ALTER TABLE nakka.skipped_tournaments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_anon_select_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR SELECT
  TO anon
  USING (true);

CREATE POLICY "allow_authenticated_select_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "allow_anon_insert_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR INSERT
  TO anon
  WITH CHECK (true);

CREATE POLICY "allow_authenticated_insert_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "allow_anon_update_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);

CREATE POLICY "allow_authenticated_update_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "allow_anon_delete_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR DELETE
  TO anon
  USING (true);

CREATE POLICY "allow_authenticated_delete_skipped_tournaments"
  ON nakka.skipped_tournaments
  FOR DELETE
  TO authenticated
  USING (true);

GRANT ALL ON nakka.skipped_tournaments TO service_role;
GRANT ALL ON nakka.skipped_tournaments TO postgres;

GRANT SELECT, INSERT, UPDATE, DELETE ON nakka.skipped_tournaments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON nakka.skipped_tournaments TO anon;

GRANT USAGE, SELECT ON SEQUENCE nakka.skipped_tournaments_skipped_tournament_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE nakka.skipped_tournaments_skipped_tournament_id_seq TO anon;
GRANT ALL ON SEQUENCE nakka.skipped_tournaments_skipped_tournament_id_seq TO service_role;
GRANT ALL ON SEQUENCE nakka.skipped_tournaments_skipped_tournament_id_seq TO postgres;
