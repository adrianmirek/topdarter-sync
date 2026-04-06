// Load environment variables FIRST (before any other imports that might use them)
import "dotenv/config";

import cron from "node-cron";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/db/database.types";
import { scrapeTournamentPlayersStatsByNakkaIdentifier, importTournamentPlayerStats } from "@/lib/services/nakka.service";

interface PendingTournament {
  tournament_id: number;
  nakka_identifier: string;
  tournament_name: string;
  tournament_date: string;
}

// Create a standalone Supabase client for the scheduler
function createSchedulerSupabaseClient() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceKey = process.env.SUPABASE_PUBLIC_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error("Missing required Supabase environment variables: SUPABASE_URL or SUPABASE_PUBLIC_KEY");
  }

  return createClient<Database>(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

/**
 * Fetches tournaments that have completed match import but whose player stats
 * have not been synced yet (sync_stats = FALSE).
 * Ordered by tournament_date DESC (most recent first).
 */
async function getPendingTournaments(supabase: ReturnType<typeof createSchedulerSupabaseClient>): Promise<PendingTournament[]> {
  try {
    console.log("[PlayerStats Scheduler] Fetching tournaments pending player stats sync...");

    const { data, error } = await (supabase as never as ReturnType<typeof createSchedulerSupabaseClient>)
      .schema("nakka")
      .from("tournaments" as never)
      .select("tournament_id, nakka_identifier, tournament_name, tournament_date")
      .eq("sync_stats", false)
      .eq("match_import_status", "completed")
      .order("tournament_date", { ascending: false });

    if (error) {
      console.error("[PlayerStats Scheduler] Error fetching pending tournaments:", error);
      return [];
    }

    const tournaments = (data ?? []) as PendingTournament[];
    console.log(`[PlayerStats Scheduler] Found ${tournaments.length} tournament(s) pending player stats sync`);
    return tournaments;
  } catch (error) {
    console.error("[PlayerStats Scheduler] Exception fetching pending tournaments:", error);
    return [];
  }
}

/**
 * Marks a tournament's sync_stats flag as TRUE after successful import.
 */
async function markTournamentSynced(
  supabase: ReturnType<typeof createSchedulerSupabaseClient>,
  tournamentId: number
): Promise<void> {
  const { error } = await (supabase as never as ReturnType<typeof createSchedulerSupabaseClient>)
    .schema("nakka")
    .from("tournaments" as never)
    .update({ sync_stats: true } as never)
    .eq("tournament_id", tournamentId);

  if (error) {
    throw new Error(`Failed to update sync_stats for tournament ${tournamentId}: ${error.message}`);
  }
}

/**
 * Main sync function that processes all pending tournaments.
 */
async function syncTournamentPlayerStats() {
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] ========================================`);
  console.log(`[${timestamp}] Starting tournament player stats sync...`);
  console.log(`[${timestamp}] ========================================\n`);

  try {
    const supabase = createSchedulerSupabaseClient();

    // Step 1: Retrieve tournaments where sync_stats = FALSE and match_import_status = 'completed'
    const pendingTournaments = await getPendingTournaments(supabase);

    if (pendingTournaments.length === 0) {
      console.log(`[${timestamp}] No tournaments pending player stats sync. Nothing to process.`);
      return;
    }

    console.log(`[${timestamp}] Processing ${pendingTournaments.length} tournament(s)...\n`);

    let successCount = 0;
    let failCount = 0;

    for (let i = 0; i < pendingTournaments.length; i++) {
      const tournament = pendingTournaments[i];
      const label = `[${timestamp}] [${i + 1}/${pendingTournaments.length}]`;

      console.log(`${label} Processing tournament: ${tournament.nakka_identifier} ("${tournament.tournament_name}")`);

      try {
        // Step 2: Retrieve data from Top Darter API
        const playerStats = await scrapeTournamentPlayersStatsByNakkaIdentifier(tournament.nakka_identifier);

        if (playerStats.length === 0) {
          console.warn(`${label} No player stats returned for ${tournament.nakka_identifier} — skipping sync_stats update`);
          failCount++;
          continue;
        }

        // Step 3: Save to nakka.tournament_player_stats
        const importResult = await importTournamentPlayerStats(supabase as never, tournament.tournament_id, playerStats);

        if (importResult.failed > 0) {
          const errors = importResult.errors?.map((e) => `${e.player_id}: ${e.error}`).join("; ") ?? "unknown error";
          console.error(`${label} ✗ Import failed for ${tournament.nakka_identifier}: ${errors}`);
          failCount++;
          continue;
        }

        // Guard: upsert reported no error but DB verification returned 0 rows — treat as failure
        if (importResult.inserted === 0 && importResult.total_processed > 0) {
          console.error(
            `${label} ✗ DB verification failed for ${tournament.nakka_identifier}: ` +
              `upsert succeeded but 0 rows found in tournament_player_stats. Skipping sync_stats update.`
          );
          failCount++;
          continue;
        }

        // Step 4: Mark tournament as synced
        await markTournamentSynced(supabase, tournament.tournament_id);

        successCount++;
        console.log(`${label} ✓ Tournament ${tournament.nakka_identifier} synced successfully`);
        console.log(`${label}   - Total stats processed: ${importResult.total_processed}`);
        console.log(`${label}   - Rows upserted: ${importResult.inserted}\n`);
      } catch (error) {
        failCount++;
        console.error(
          `${label} ✗ Failed to sync tournament ${tournament.nakka_identifier}:`,
          error instanceof Error ? error.message : "Unknown error"
        );
        console.error(`${label} Stack trace:`, error);
        console.log("");
      }
    }

    // Summary
    const endTimestamp = new Date().toISOString();
    console.log(`\n[${endTimestamp}] ========================================`);
    console.log(`[${endTimestamp}] Sync completed!`);
    console.log(`[${endTimestamp}] Total tournaments processed: ${pendingTournaments.length}`);
    console.log(`[${endTimestamp}] Successful: ${successCount}`);
    console.log(`[${endTimestamp}] Failed: ${failCount}`);
    console.log(`[${endTimestamp}] ========================================\n`);
  } catch (error) {
    console.error(`[${timestamp}] Fatal error during tournament player stats sync:`, error);
  }
}

// Run every 15 minutes
const CRON_SCHEDULE = process.env.TOURNAMENT_PLAYER_STATS_CRON_SCHEDULE || "*/30 * * * *";

console.log("========================================");
console.log("Tournament Player Stats Sync Scheduler Started");
console.log(`Schedule: ${CRON_SCHEDULE}`);
console.log("Source: nakka.tournaments WHERE sync_stats = FALSE AND match_import_status = 'completed'");
console.log("Target: nakka.tournament_player_stats");
console.log("========================================\n");

// Schedule the cron job
cron.schedule(CRON_SCHEDULE, () => {
  syncTournamentPlayerStats();
});

// Optional: Run immediately on startup
if (process.env.RUN_ON_STARTUP === "true") {
  console.log("RUN_ON_STARTUP is enabled. Running sync immediately...\n");
  syncTournamentPlayerStats();
}

// Keep the process running
console.log("Scheduler is running. Press Ctrl+C to stop.\n");
