// Load environment variables FIRST (before any other imports that might use them)
import 'dotenv/config';

import cron from 'node-cron';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/db/database.types';
import { syncTournamentsByKeyword } from '@/lib/services/nakka.service';

// Type definition for keyword records from nakka.keyword table
// Note: Run `npm run supabase:types` to regenerate types after migration
interface KeywordRecord {
  id: string;
  keyword: string;
  last_sync_date: string;
  is_league: boolean;
}

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
 * Main sync function that syncs tournaments by keywords from database
 */
async function syncTournamentsByConfiguredKeywords() {
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] ========================================`);
  console.log(`[${timestamp}] Starting tournament keyword sync...`);
  console.log(`[${timestamp}] ========================================\n`);

  try {
    const supabase = createSchedulerSupabaseClient();

    // Step 1: Get keywords from nakka.keyword table where last_sync_date is older than 4 hours
    const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
    
    console.log(`[${timestamp}] Fetching non-league keywords older than 4 hours (before ${fourHoursAgo})...`);
    
    // Note: Using type assertion because nakka.keyword types may not be generated yet
    // Run `npm run supabase:types` to regenerate types after migration
    const { data: keywordRecords, error: fetchError } = (await (supabase as any)
      .schema('nakka')
      .from('keyword')
      .select('id, keyword, last_sync_date, is_league')
      .eq('is_league', false)
      .lt('last_sync_date', fourHoursAgo)
      .order('last_sync_date', { ascending: true })) as { data: KeywordRecord[] | null; error: any };

    if (fetchError) {
      console.error(`[${timestamp}] Error fetching keywords from database:`, fetchError);
      return;
    }

    if (!keywordRecords || keywordRecords.length === 0) {
      console.log(`[${timestamp}] No non-league keywords need syncing (all synced within last 4 hours).`);
      return;
    }

    console.log(`[${timestamp}] Found ${keywordRecords.length} non-league keyword(s) to sync:\n`);
    keywordRecords.forEach((record, idx) => {
      console.log(`[${timestamp}]   ${idx + 1}. "${record.keyword}" (last synced: ${record.last_sync_date})`);
    });
    console.log('');

    // Step 2: Process each keyword
    let totalInserted = 0;
    let totalUpdated = 0;
    let totalSkipped = 0;
    let totalProcessed = 0;
    let successfulKeywords: string[] = [];
    let failedKeywords: string[] = [];

    for (let i = 0; i < keywordRecords.length; i++) {
      const record = keywordRecords[i];
      const keyword = record.keyword;
      
      try {
        console.log(`[${timestamp}] [${i + 1}/${keywordRecords.length}] Syncing keyword: "${keyword}"`);

        const result = await syncTournamentsByKeyword(supabase as never, keyword);

        totalInserted += result.inserted;
        totalUpdated += result.updated;
        totalSkipped += result.skipped;
        totalProcessed += result.total_processed;

        console.log(`[${timestamp}] ✓ Keyword "${keyword}" processed successfully`);
        console.log(`[${timestamp}]   - Inserted: ${result.inserted}`);
        console.log(`[${timestamp}]   - Updated: ${result.updated}`);
        console.log(`[${timestamp}]   - Skipped: ${result.skipped}`);
        console.log(`[${timestamp}]   - Total: ${result.total_processed}`);

        // Step 3: Update last_sync_date on successful sync
        const updateTimestamp = new Date().toISOString();
        const { error: updateError } = await (supabase as any)
          .schema('nakka')
          .from('keyword')
          .update({ last_sync_date: updateTimestamp })
          .eq('id', record.id);

        if (updateError) {
          console.error(`[${timestamp}] ⚠ Warning: Failed to update last_sync_date for "${keyword}":`, updateError);
        } else {
          console.log(`[${timestamp}] ✓ Updated last_sync_date for "${keyword}" to ${updateTimestamp}`);
          successfulKeywords.push(keyword);
        }
        console.log(''); // Empty line for readability
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
    console.log(`[${endTimestamp}] Keywords found: ${keywordRecords.length}`);
    console.log(`[${endTimestamp}] Keywords synced successfully: ${successfulKeywords.length}`);
    console.log(`[${endTimestamp}] Keywords failed: ${failedKeywords.length}`);
    console.log(`[${endTimestamp}] Total tournaments inserted: ${totalInserted}`);
    console.log(`[${endTimestamp}] Total tournaments updated: ${totalUpdated}`);
    console.log(`[${endTimestamp}] Total tournaments skipped: ${totalSkipped}`);
    console.log(`[${endTimestamp}] Total tournaments processed: ${totalProcessed}`);
    if (successfulKeywords.length > 0) {
      console.log(`[${endTimestamp}] Successful keywords: ${successfulKeywords.join(', ')}`);
    }
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
const CRON_SCHEDULE = process.env.TOURNAMENT_SYNC_CRON_SCHEDULE || '*/15 * * * *';

console.log('========================================');
console.log('Tournament Keyword Sync Scheduler Started');
console.log(`Schedule: ${CRON_SCHEDULE}`);
console.log('Keywords source: nakka.keyword table (is_league = false, syncs keywords older than 4 hours)');
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
