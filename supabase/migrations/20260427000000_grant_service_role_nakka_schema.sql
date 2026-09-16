-- =====================================================================
-- Migration: Grant service_role full access to nakka schema
-- Purpose: Allow the Supabase admin client (service_role) to read and
--          write all tables in the nakka schema, bypassing RLS.
--          Required for server-side operations that run without an
--          authenticated user session (e.g. certificate generation).
-- Date: 2026-04-27
-- =====================================================================

GRANT USAGE ON SCHEMA nakka TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA nakka TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA nakka TO service_role;

-- Ensure future tables created in nakka also inherit these grants
ALTER DEFAULT PRIVILEGES IN SCHEMA nakka GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA nakka GRANT ALL ON SEQUENCES TO service_role;
