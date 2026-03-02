/**
 * API Endpoint: POST /api/sync/tournaments
 * Triggers tournament keyword sync (called by scheduled jobs)
 */

import type { APIRoute } from "astro";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/db/database.types";
import { syncTournamentsByKeyword } from "@/lib/services/nakka.service";

export const POST: APIRoute = async ({ request }) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] POST /api/sync/tournaments - Tournament sync triggered`);

  try {
    // Authentication check
    const authHeader = request.headers.get("Authorization");
    const expectedKey = import.meta.env.SYNC_API_KEY || process.env.SYNC_API_KEY;

    if (!expectedKey) {
      console.error(`[${timestamp}] SYNC_API_KEY not configured`);
      return new Response(JSON.stringify({ error: "Sync service not configured" }), {
        status: 503,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const providedKey = authHeader.substring(7); // Remove 'Bearer '
    if (providedKey !== expectedKey) {
      return new Response(JSON.stringify({ error: "Invalid API key" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Create Supabase client
    const supabaseUrl = import.meta.env.SUPABASE_URL || process.env.SUPABASE_URL;
    const supabaseKey = import.meta.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      console.error(`[${timestamp}] Supabase credentials not configured`);
      return new Response(JSON.stringify({ error: "Database not configured" }), {
        status: 503,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient<Database>(supabaseUrl, supabaseKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Get keywords from database (older than 4 hours)
    const fourHoursAgo = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString();
    console.log(`[${timestamp}] Fetching keywords older than 4 hours (before ${fourHoursAgo})...`);

    const { data: keywordRecords, error: fetchError } = await (supabase as any)
      .schema("nakka")
      .from("keyword")
      .select("id, keyword, last_sync_date")
      .lt("last_sync_date", fourHoursAgo)
      .order("last_sync_date", { ascending: true });

    if (fetchError) {
      console.error(`[${timestamp}] Error fetching keywords:`, fetchError);
      return new Response(JSON.stringify({ error: "Failed to fetch keywords", details: fetchError }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!keywordRecords || keywordRecords.length === 0) {
      console.log(`[${timestamp}] No keywords need syncing`);
      return new Response(JSON.stringify({ message: "No keywords to sync", synced: 0 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`[${timestamp}] Found ${keywordRecords.length} keyword(s) to sync`);

    // Process each keyword
    let successCount = 0;
    let failCount = 0;
    const results: any[] = [];

    for (const record of keywordRecords) {
      try {
        console.log(`[${timestamp}] Syncing keyword: "${record.keyword}"`);
        const result = await syncTournamentsByKeyword(supabase as never, record.keyword);

        // Update last_sync_date
        const updateTimestamp = new Date().toISOString();
        const { error: updateError } = await (supabase as any)
          .schema("nakka")
          .from("keyword")
          .update({ last_sync_date: updateTimestamp })
          .eq("id", record.id);

        if (updateError) {
          console.error(`[${timestamp}] Warning: Failed to update last_sync_date for "${record.keyword}"`);
        }

        successCount++;
        results.push({ keyword: record.keyword, status: "success", ...result });
        console.log(`[${timestamp}] ✓ Synced: ${record.keyword}`);
      } catch (error) {
        failCount++;
        const errorMessage = error instanceof Error ? error.message : "Unknown error";
        results.push({ keyword: record.keyword, status: "failed", error: errorMessage });
        console.error(`[${timestamp}] ✗ Failed: ${record.keyword}`, errorMessage);
      }
    }

    const summary = {
      timestamp,
      keywords_found: keywordRecords.length,
      success: successCount,
      failed: failCount,
      results,
    };

    console.log(`[${timestamp}] Tournament sync completed: ${successCount} success, ${failCount} failed`);

    return new Response(JSON.stringify(summary), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (error) {
    console.error(`[${timestamp}] Fatal error in tournament sync:`, error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
};
