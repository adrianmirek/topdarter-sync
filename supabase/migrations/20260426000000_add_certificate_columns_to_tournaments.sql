-- =====================================================================
-- Migration: Add Certificate Columns to nakka.tournaments
-- Purpose: Enable certificate functionality per tournament
-- Date: 2026-04-26
-- =====================================================================

ALTER TABLE nakka.tournaments
  ADD COLUMN IF NOT EXISTS is_certificate_enable BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN nakka.tournaments.is_certificate_enable IS
'When TRUE, certificate generation is enabled for this tournament.
Template assets are resolved automatically from nakka_identifier:
  - watermark base  : certificates/templates/{nakka_identifier}/watermark.webp
  - detection guide : certificates/templates/{nakka_identifier}/watermark-red-rectangle.webp
  - example cert    : certificates/templates/{nakka_identifier}/example.webp';
