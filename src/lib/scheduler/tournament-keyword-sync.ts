// Load environment variables FIRST (before any other imports that might use them)
import 'dotenv/config';

import cron from 'node-cron';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/db/database.types';
import { syncTournamentsByKeyword } from '@/lib/services/nakka.service';

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
 * Main sync function that syncs tournaments by configured keyword(s)
 */
async function syncTournamentsByConfiguredKeywords() {
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] ========================================`);
  console.log(`[${timestamp}] Starting tournament keyword sync...`);
  console.log(`[${timestamp}] ========================================\n`);

  try {
    const supabase = createSchedulerSupabaseClient();

    // Get keyword(s) from environment variable
    // Can be comma-separated for multiple keywords: "agawa,wroclaw"
    const keywordsStr = process.env.TOURNAMENT_SYNC_KEYWORDS || 'agawa';
    const keywords = keywordsStr.split(',').map(k => k.trim()).filter(k => k.length > 0);

    if (keywords.length === 0) {
      console.log(`[${timestamp}] No keywords configured. Set TOURNAMENT_SYNC_KEYWORDS env var.`);
      return;
    }

    console.log(`[${timestamp}] Processing ${keywords.length} keyword(s): ${keywords.join(', ')}\n`);

    // Step 2: Process each keyword
    let totalInserted = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;
    let totalProcessed = 0;
    let failedKeywords: string[] = [];

    for (const keyword of keywords) {
      try {
        console.log(`[${timestamp}] [${keywords.indexOf(keyword) + 1}/${keywords.length}] Syncing keyword: "${keyword}"`);

        const result = await syncTournamentsByKeyword(supabase as never, keyword);

        totalInserted += result.inserted;
        totalUpdated += result.updated;
        totalSkipped += result.skipped;
        totalProcessed += result.total_processed;

        console.log(`[${timestamp}] ✓ Keyword "${keyword}" processed successfully`);
        console.log(`[${timestamp}]   - Inserted: ${result.inserted}`);
        console.log(`[${timestamp}]   - Updated: ${result.updated}`);
        console.log(`[${timestamp}]   - Skipped: ${result.skipped}`);
        console.log(`[${timestamp}]   - Total: ${result.total_processed}\n`);
      } catch (error) {
        failedKeywords.push(keyword);
        console.error(
          `[${timestamp}] ✗ Failed to sync keyword "${keyword}":`,
          error instanceof Error ? error.message : 'Unknown error'
        );
        console.error(`[${timestamp}] Stack trace:`, error);
        console.log(''); // Empty line for readability
        // Continue with next keyword even if this one fails
      }
    }

    // Summary
    const endTimestamp = new Date().toISOString();
    console.log(`\n[${endTimestamp}] ========================================`);
    console.log(`[${endTimestamp}] Sync completed!`);
    console.log(`[${endTimestamp}] Keywords processed: ${keywords.length - failedKeywords.length}/${keywords.length}`);
    console.log(`[${endTimestamp}] Total tournaments inserted: ${totalInserted}`);
    console.log(`[${endTimestamp}] Total tournaments updated: ${totalUpdated}`);
    console.log(`[${endTimestamp}] Total tournaments skipped: ${totalSkipped}`);
    console.log(`[${endTimestamp}] Total tournaments processed: ${totalProcessed}`);
    if (failedKeywords.length > 0) {
      console.log(`[${endTimestamp}] Failed keywords: ${failedKeywords.join(', ')}`);
    }
    console.log(`[${endTimestamp}] ========================================\n`);
  } catch (error) {
    console.error(`[${timestamp}] Fatal error during sync:`, error);
  }
}

// Run every minute for testing: * * * * *
// For production every hour: 0 * * * *
// For production every 6 hours: 0 */6 * * *
const CRON_SCHEDULE = process.env.TOURNAMENT_SYNC_CRON_SCHEDULE || '* * * * *';

console.log('========================================');
console.log('Tournament Keyword Sync Scheduler Started');
console.log(`Schedule: ${CRON_SCHEDULE}`);
console.log('Keywords:', process.env.TOURNAMENT_SYNC_KEYWORDS || 'agawa');
console.log('========================================\n');

// Schedule the cron job
cron.schedule(CRON_SCHEDULE, () => {
  syncTournamentsByConfiguredKeywords();
});

// Optional: Run immediately on startup
if (process.env.RUN_ON_STARTUP === 'true') {
  console.log('RUN_ON_STARTUP is enabled. Running sync immediately...\n');
  syncTournamentsByConfiguredKeywords();
}

// Keep the process running
console.log('Scheduler is running. Press Ctrl+C to stop.\n');
