# Quick Start Guide - Schedulers

This guide will help you get the schedulers up and running in **5 minutes**.

We have two schedulers:
1. **Match Results Sync** - Processes incomplete match results
2. **Tournament Keyword Sync** - Discovers and syncs tournaments by keyword

## Prerequisites

- Node.js installed
- Supabase project set up
- Environment variables configured

## Step 1: Install Dependencies

```bash
npm install
```

This will install:
- `node-cron` - for scheduling jobs
- `tsx` - for running TypeScript files directly

## Step 2: Configure Environment Variables

Add these to your `.env` file:

```env
# Required - Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here

# Optional - Match Results Sync Configuration
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *  # Default: every 10 minutes

# Optional - Tournament Keyword Sync Configuration
TOURNAMENT_SYNC_CRON_SCHEDULE=* * * * *  # Default: every minute (for testing)
TOURNAMENT_SYNC_KEYWORDS=agawa            # Default: agawa

# Optional - Run sync immediately on startup
RUN_ON_STARTUP=true                       # Default: false
```

**Important Notes:**
- ✅ Use `SUPABASE_SERVICE_ROLE_KEY` (service role key with bypass RLS)
- ❌ Don't use `SUPABASE_PUBLIC_KEY` (anon key - won't work for scheduler)
- You can find the service role key in your Supabase dashboard under Settings > API
- For production, set `TOURNAMENT_SYNC_CRON_SCHEDULE` to run less frequently (e.g., `0 */6 * * *` for every 6 hours)

## Step 3: Run the Scheduler

### Match Results Sync

```bash
npm run sync:match-results
```

You should see output like:

```
========================================
Match Results Sync Scheduler Started
Schedule: */10 * * * *
========================================

Scheduler is running. Press Ctrl+C to stop.
```

### Tournament Keyword Sync

```bash
npm run sync:tournaments
```

You should see output like:

```
========================================
Tournament Keyword Sync Scheduler Started
Schedule: * * * * *
Keywords: agawa
========================================

Scheduler is running. Press Ctrl+C to stop.
```

## Step 4: Test It (Optional)

To run the sync immediately on startup for testing:

```env
RUN_ON_STARTUP=true
```

### Match Results Sync
Adjust the schedule to run every minute for testing:

```env
MATCH_SYNC_CRON_SCHEDULE=* * * * *
```

Then restart:

```bash
npm run sync:match-results
```

### Tournament Keyword Sync
The default schedule already runs every minute for testing. To test with a different keyword:

```env
TOURNAMENT_SYNC_KEYWORDS=wroclaw,agawa
```

Then restart:

```bash
npm run sync:tournaments
```

## What Happens Next?

### Match Results Sync

The scheduler will:

1. **Every 10 minutes** (or your custom schedule):
   - Query database for up to 30 incomplete matches
   - Process each match:
     - Scrape player statistics from Nakka.pl
     - Import data to `nakka.tournament_match_player_results`
     - Update match status to `'completed'` or `'failed'`
   - Display progress and summary

2. **Log everything**:
   - Match processing progress (e.g., `[3/30]`)
   - Success/failure status
   - Error details
   - Summary statistics

### Tournament Keyword Sync

The scheduler will:

1. **Every minute** (or your custom schedule):
   - Search Nakka.pl for tournaments matching configured keywords
   - For each keyword:
     - Scrape tournament listings
     - Import new tournaments (skip existing ones)
     - Scrape matches for each tournament
     - Process player results for uncompleted matches
   - Display progress and summary

2. **Log everything**:
   - Keyword processing progress
   - Tournament import statistics (inserted/updated/skipped)
   - Match import progress
   - Player results processing status
   - Summary statistics

## Example Output

### Match Results Sync

```
[2026-01-14T10:00:00.000Z] ========================================
[2026-01-14T10:00:00.000Z] Starting match results sync...
[2026-01-14T10:00:00.000Z] ========================================

[Scheduler] Fetching incomplete matches from database...
[Scheduler] Found 15 incomplete matches
[2026-01-14T10:00:00.000Z] Processing 15 incomplete matches...

[2026-01-14T10:00:01.000Z] [1/15] Processing match: t_Nd6M_9511_rr_2_3Tm2
[Scrape & Import] Starting scrape for match: t_Nd6M_9511_rr_2_3Tm2
[Scrape & Import] Match status updated to in_progress
[Scrape & Import] Scraping player results from: https://nakka.pl/match/...
[Scrape & Import] Successfully scraped 2 player results
[Scrape & Import] Importing player results to database...
[Scrape & Import] Match t_Nd6M_9511_rr_2_3Tm2 completed successfully. Inserted: 2, Skipped: 0
[2026-01-14T10:00:03.000Z] ✓ Match t_Nd6M_9511_rr_2_3Tm2 processed successfully

... (continues for all matches)

[2026-01-14T10:05:00.000Z] ========================================
[2026-01-14T10:05:00.000Z] Sync completed!
[2026-01-14T10:05:00.000Z] Total processed: 15
[2026-01-14T10:05:00.000Z] Successful: 14
[2026-01-14T10:05:00.000Z] Failed: 1
[2026-01-14T10:05:00.000Z] ========================================
```

### Tournament Keyword Sync

```
[2026-02-01T10:00:00.000Z] ========================================
[2026-02-01T10:00:00.000Z] Starting tournament keyword sync...
[2026-02-01T10:00:00.000Z] ========================================

[2026-02-01T10:00:00.000Z] Processing 1 keyword(s): agawa

[2026-02-01T10:00:01.000Z] [1/1] Syncing keyword: "agawa"
Calling external scraper API for keyword: "agawa"
Successfully scraped 3 tournaments from external API
Processing matches for 3 tournaments...
... (continues for all tournaments)

[2026-02-01T10:00:30.000Z] ✓ Keyword "agawa" processed successfully
[2026-02-01T10:00:30.000Z]   - Inserted: 2
[2026-02-01T10:00:30.000Z]   - Updated: 0
[2026-02-01T10:00:30.000Z]   - Skipped: 1
[2026-02-01T10:00:30.000Z]   - Total: 3

[2026-02-01T10:00:30.000Z] ========================================
[2026-02-01T10:00:30.000Z] Sync completed!
[2026-02-01T10:00:30.000Z] Keywords processed: 1/1
[2026-02-01T10:00:30.000Z] Total tournaments inserted: 2
[2026-02-01T10:00:30.000Z] Total tournaments updated: 0
[2026-02-01T10:00:30.000Z] Total tournaments skipped: 1
[2026-02-01T10:00:30.000Z] Total tournaments processed: 3
[2026-02-01T10:00:30.000Z] ========================================
```

## Troubleshooting

### "Missing required Supabase environment variables"
- Check that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set in `.env`
- Make sure you're using the **service role key**, not the public anon key

### "No incomplete matches found"
- Check database: `SELECT * FROM nakka.tournament_matches WHERE match_result_status IS NULL OR match_result_status != 'completed' LIMIT 30;`
- Make sure matches exist in the database

### "No keywords configured"
- Check that `TOURNAMENT_SYNC_KEYWORDS` is set in `.env`
- Default is `agawa` if not configured

### "Successfully scraped 0 tournaments"
- Verify the keyword matches tournaments on Nakka.pl
- Try a different keyword like `wroclaw` or `katowice`
- Check that tournaments exist for that keyword on https://nakka.pl

### Scraping fails with 401/403 errors
- Verify the TopDarter scraper API is running at `http://localhost:3001`
- Check `TOPDARTER_API_KEY` is set correctly in `.env`
- Ensure the scraper API is accessible from your machine

### Scheduler stops unexpectedly
- Check console for error messages
- Verify all dependencies are installed: `npm install`
- Try running with `RUN_ON_STARTUP=true` to see immediate errors

## Running in Production

For long-term production use, consider:

### Option 1: PM2 (Recommended for Node.js)

```bash
# Install PM2 globally
npm install -g pm2

# Start the scheduler
pm2 start npm --name "match-sync" -- run sync:match-results

# Start tournament keyword sync
pm2 start npm --name "tournament-sync" -- run sync:tournaments

# Save PM2 configuration
pm2 save

# Setup PM2 to start on system boot
pm2 startup
```

### Option 2: Windows Task Scheduler

1. Open Task Scheduler
2. Create Basic Task
3. Trigger: At system startup
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-Command "cd D:\Repo\AI\darterassistant; npm run sync:match-results"`

### Option 3: Docker

Add to your Dockerfile:

```dockerfile
CMD ["npm", "run", "sync:match-results"]
```

## Stop the Scheduler

Press `Ctrl+C` in the terminal where it's running.

Or if using PM2:

```bash
# Stop match results sync
pm2 stop match-sync

# Stop tournament keyword sync
pm2 stop tournament-sync
```

## Need More Help?

See the full documentation in `README.md` in this directory.

