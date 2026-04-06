-- =====================================================================
-- Migration: Fix keyword unique constraint
-- Purpose: Change unique constraint on nakka.keyword from single-column
--          (keyword) to composite (keyword, is_league), allowing the same
--          keyword text to exist for both league and non-league entries.
-- Date: 2026-03-02
-- =====================================================================

-- Step 1: Drop the existing single-column unique constraint
ALTER TABLE nakka.keyword
DROP CONSTRAINT keyword_keyword_key;

-- Step 2: Add a composite unique constraint on (keyword, is_league)
ALTER TABLE nakka.keyword
ADD CONSTRAINT keyword_keyword_is_league_key UNIQUE (keyword, is_league);
