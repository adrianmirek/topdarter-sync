// Load environment variables FIRST (before any other imports that might use them)
import 'dotenv/config';

import cron from 'node-cron';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/db/database.types';
import { scrapeAndImportMatchPlayerResults } from '@/lib/services/nakka.user.service';

// Create a standalone Supabase client for the scheduler
function createSchedulerSupabaseClient() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceKey = process.env.SUPABASE_PUBLIC_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Missing required Supabase environment variables: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  }

  return createClient<Database>(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Fetches up to 30 matches from database where match_result_status is NULL or not 'completed'
 * Ordered by tournament_date DESC (most recent tournament first)
 */
async function getIncompleteMatches(supabase: ReturnType<typeof createSchedulerSupabaseClient>) {
  try {
    console.log('[Scheduler] Fetching incomplete matches from database...');

    const { data, error } = await supabase
      .schema('nakka')
      .from('tournament_matches' as never)
      .select(`
        tournament_match_id, 
        nakka_match_identifier, 
        href,
        tournaments!inner(tournament_date)
      `)
      .or('match_result_status.is.null,match_result_status.neq.completed')
      .order('tournaments(tournament_date)', { ascending: false } as never)
      .limit(30);

    if (error) {
      console.error('[Scheduler] Error fetching incomplete matches:', error);
      return [];
    }

    console.log(`[Scheduler] Found ${data?.length || 0} incomplete matches`);
    
    // Map to extract only the fields we need (tournament data is only used for ordering)
    return (data || []).map((match: any) => ({
      tournament_match_id: match.tournament_match_id,
      nakka_match_identifier: match.nakka_match_identifier,
      href: match.href,
    }));
  } catch (error) {
    console.error('[Scheduler] Exception fetching incomplete matches:', error);
    return [];
  }
}

/**
 * Main sync function that processes incomplete matches
 */
async function syncIncompleteMatchResults() {
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] ========================================`);
  console.log(`[${timestamp}] Starting match results sync...`);
  console.log(`[${timestamp}] ========================================\n`);

  try {
    const supabase = createSchedulerSupabaseClient();

    // Step 1: Fetch incomplete matches
    const incompleteMatches = await getIncompleteMatches(supabase);

    if (incompleteMatches.length === 0) {
      console.log(`[${timestamp}] No incomplete matches found. Nothing to process.`);
      return;
    }

    console.log(`[${timestamp}] Processing ${incompleteMatches.length} incomplete matches...\n`);

    // Step 2: Process each match
    let successCount = 0;
    let failCount = 0;

    for (const match of incompleteMatches) {
      try {
        console.log(
          `[${timestamp}] [${successCount + failCount + 1}/${incompleteMatches.length}] Processing match: ${match.nakka_match_identifier}`
        );

        await scrapeAndImportMatchPlayerResults(
          supabase as never,
          match.tournament_match_id,
          match.nakka_match_identifier,
          match.href
        );

        successCount++;
        console.log(`[${timestamp}] ✓ Match ${match.nakka_match_identifier} processed successfully\n`);
      } catch (error) {
        failCount++;
        console.error(
          `[${timestamp}] ✗ Failed to process match ${match.nakka_match_identifier}:`,
          error instanceof Error ? error.message : 'Unknown error'
        );
        console.error(`[${timestamp}] Stack trace:`, error);
        console.log(''); // Empty line for readability
        // Continue with next match even if this one fails
      }
    }

    // Summary
    const endTimestamp = new Date().toISOString();
    console.log(`\n[${endTimestamp}] ========================================`);
    console.log(`[${endTimestamp}] Sync completed!`);
    console.log(`[${endTimestamp}] Total processed: ${incompleteMatches.length}`);
    console.log(`[${endTimestamp}] Successful: ${successCount}`);
    console.log(`[${endTimestamp}] Failed: ${failCount}`);
    console.log(`[${endTimestamp}] ========================================\n`);
  } catch (error) {
    console.error(`[${timestamp}] Fatal error during sync:`, error);
  }
}

// Run every 10 minutes: */10 * * * *
// For testing every minute: * * * * *
// For testing every 5 minutes: */5 * * * *
const CRON_SCHEDULE = process.env.MATCH_SYNC_CRON_SCHEDULE || '*/10 * * * *';

console.log('========================================');
console.log('Match Results Sync Scheduler Started');
console.log(`Schedule: ${CRON_SCHEDULE}`);
console.log('========================================\n');

// Schedule the cron job
cron.schedule(CRON_SCHEDULE, () => {
  syncIncompleteMatchResults();
});

// Optional: Run immediately on startup
if (process.env.RUN_ON_STARTUP === 'true') {
  console.log('RUN_ON_STARTUP is enabled. Running sync immediately...\n');
  syncIncompleteMatchResults();
}

// Keep the process running
console.log('Scheduler is running. Press Ctrl+C to stop.\n');

