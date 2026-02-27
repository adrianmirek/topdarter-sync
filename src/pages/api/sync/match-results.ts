/**
 * API Endpoint: POST /api/sync/match-results
 * Triggers match results sync (called by scheduled jobs)
 */

import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/db/database.types';
import { scrapeAndImportMatchPlayerResults } from '@/lib/services/nakka.user.service';

export const POST: APIRoute = async ({ request }) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] POST /api/sync/match-results - Match results sync triggered`);

  try {
    // Authentication check
    const authHeader = request.headers.get('Authorization');
    const expectedKey = import.meta.env.SYNC_API_KEY || process.env.SYNC_API_KEY;

    if (!expectedKey) {
      console.error(`[${timestamp}] SYNC_API_KEY not configured`);
      return new Response(
        JSON.stringify({ error: 'Sync service not configured' }),
        { status: 503, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing or invalid authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const providedKey = authHeader.substring(7); // Remove 'Bearer '
    if (providedKey !== expectedKey) {
      return new Response(
        JSON.stringify({ error: 'Invalid API key' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Create Supabase client
    const supabaseUrl = import.meta.env.SUPABASE_URL || process.env.SUPABASE_URL;
    const supabaseKey = import.meta.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      console.error(`[${timestamp}] Supabase credentials not configured`);
      return new Response(
        JSON.stringify({ error: 'Database not configured' }),
        { status: 503, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient<Database>(supabaseUrl, supabaseKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    });

    // Get incomplete matches (up to 30)
    console.log(`[${timestamp}] Fetching incomplete matches...`);

    const { data: matches, error: fetchError } = await (supabase as any)
      .schema('nakka')
      .from('tournament_match')
      .select('tournament_match_id, nakka_match_identifier, href, match_result_status')
      .or('match_result_status.is.null,match_result_status.neq.completed')
      .order('imported_at', { ascending: false })
      .limit(30);

    if (fetchError) {
      console.error(`[${timestamp}] Error fetching matches:`, fetchError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch matches', details: fetchError }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!matches || matches.length === 0) {
      console.log(`[${timestamp}] No incomplete matches found`);
      return new Response(
        JSON.stringify({ message: 'No incomplete matches', processed: 0 }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[${timestamp}] Found ${matches.length} incomplete match(es) to process`);

    // Process each match
    let successCount = 0;
    let failCount = 0;
    const results: any[] = [];

    for (const match of matches) {
      try {
        console.log(`[${timestamp}] Processing match: ${match.nakka_match_identifier}`);
        
        await scrapeAndImportMatchPlayerResults(
          supabase as never,
          match.tournament_match_id,
          match.nakka_match_identifier,
          match.href
        );

        successCount++;
        results.push({ 
          match_id: match.nakka_match_identifier, 
          status: 'success' 
        });
        console.log(`[${timestamp}] ✓ Processed: ${match.nakka_match_identifier}`);
      } catch (error) {
        failCount++;
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        results.push({ 
          match_id: match.nakka_match_identifier, 
          status: 'failed', 
          error: errorMessage 
        });
        console.error(`[${timestamp}] ✗ Failed: ${match.nakka_match_identifier}`, errorMessage);
      }
    }

    const summary = {
      timestamp,
      matches_found: matches.length,
      success: successCount,
      failed: failCount,
      results
    };

    console.log(`[${timestamp}] Match results sync completed: ${successCount} success, ${failCount} failed`);

    return new Response(
      JSON.stringify(summary),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error(`[${timestamp}] Fatal error in match results sync:`, error);
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : 'Unknown error'
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
};
