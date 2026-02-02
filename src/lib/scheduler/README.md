# Schedulers

This directory contains automated schedulers for syncing data from Nakka.pl:

1. **Match Results Sync Scheduler** (`match-results-sync.ts`) - Automatically processes incomplete match results
2. **Tournament Keyword Sync Scheduler** (`tournament-keyword-sync.ts`) - Automatically discovers and syncs tournaments by keyword

## Match Results Sync Scheduler

This scheduler automatically processes incomplete match results by scraping player statistics from Nakka.pl and importing them into the database.

## How It Works

### Match Results Sync

1. **Fetches Incomplete Matches**: Queries the database for up to 30 matches where `match_result_status` is `NULL` or not `'completed'`, ordered by `imported_at DESC` (most recent first).

2. **Processes Each Match**: For each incomplete match, it calls `scrapeAndImportMatchPlayerResults` which:
   - Scrapes player statistics from the match page on Nakka.pl
   - Imports the data into the `nakka.tournament_match_player_results` table
   - Updates the match status to `'completed'` on success or `'failed'` on error

3. **Runs on Schedule**: By default, runs every 10 minutes using node-cron.

### Tournament Keyword Sync

1. **Searches by Keywords**: Uses configured keywords (e.g., "agawa") to search for tournaments on Nakka.pl

2. **Syncs Tournaments**: For each keyword, it calls `syncTournamentsByKeyword` which:
   - Scrapes tournament listings from Nakka.pl search results
   - Imports new tournaments into the `nakka.tournaments` table (skips existing ones)
   - Automatically scrapes and imports matches for each tournament
   - Processes player results for uncompleted matches

3. **Runs on Schedule**: By default, runs every minute for testing (recommended: every 6-24 hours for production).

## Environment Variables

Required in your `.env` file:

```env
# Supabase Configuration (REQUIRED)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Match Results Sync (OPTIONAL)
# Customize cron schedule (default: */10 * * * * = every 10 minutes)
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *

# Tournament Keyword Sync (OPTIONAL)
# Customize cron schedule (default: * * * * * = every minute for testing)
TOURNAMENT_SYNC_CRON_SCHEDULE=* * * * *

# Keywords to search for tournaments (comma-separated, default: agawa)
TOURNAMENT_SYNC_KEYWORDS=agawa

# Run sync immediately on startup (default: false)
RUN_ON_STARTUP=true
```

**Important**: Use `SUPABASE_SERVICE_ROLE_KEY` (not the public anon key) to bypass Row Level Security policies.

See [ENV_SETUP.md](./ENV_SETUP.md) for detailed configuration guide.

## Cron Schedule Examples

### Match Results Sync
- Every 10 minutes (default): `*/10 * * * *`
- Every 5 minutes: `*/5 * * * *`
- Every hour: `0 * * * *`
- Every hour at 30 minutes: `30 * * * *`

### Tournament Keyword Sync
- Every minute (default for testing): `* * * * *`
- Every hour: `0 * * * *`
- Every 6 hours: `0 */6 * * *`
- Every day at 3 AM: `0 3 * * *`
- Every day at 9 AM and 9 PM: `0 9,21 * * *`

**Recommendation**: Tournament keyword sync should run less frequently (every 6-24 hours) since tournaments don't change often.

## Usage

### Development

```bash
# Install dependencies (if not already installed)
npm install

# Run match results sync
npm run sync:match-results

# Run tournament keyword sync
npm run sync:tournaments
```

Both schedulers will:
- Start and display the schedule
- Run the sync based on the cron schedule
- Display detailed logs for each item processed
- Keep running until you stop them (Ctrl+C)

### Quick Test

```bash
# Test match results sync immediately
RUN_ON_STARTUP=true npm run sync:match-results

# Test tournament keyword sync immediately
RUN_ON_STARTUP=true npm run sync:tournaments
```

### Production

For production deployment, you can use:

1. **PM2** (Process Manager):
```bash
# Start match results sync
pm2 start npm --name "match-sync" -- run sync:match-results

# Start tournament keyword sync
pm2 start npm --name "tournament-sync" -- run sync:tournaments

# Save PM2 process list
pm2 save

# Setup PM2 to start on system boot
pm2 startup
```

2. **Windows Task Scheduler**: Schedule the commands to run on system startup
3. **systemd** (Linux): Create systemd services
4. **Docker**: Include in your Docker container's startup script

## Logs

Both schedulers output detailed logs:

### Match Results Sync
- Match processing progress (e.g., `[3/30] Processing match...`)
- Success/failure status for each match
- Summary statistics at the end of each sync
- Timestamps for all operations

### Tournament Keyword Sync
- Keyword processing progress
- Tournament scraping and import statistics (inserted/updated/skipped)
- Match import progress for each tournament
- Player results processing status
- Summary statistics at the end of each sync
- Timestamps for all operations

## Error Handling

### Match Results Sync
- If a match fails to process, the error is logged and the scheduler continues with the next match
- Match status is updated to `'failed'` with error details in the database
- The scheduler itself never crashes - it catches all errors and continues running

### Tournament Keyword Sync
- If a keyword fails, the error is logged and the scheduler continues with the next keyword
- If tournament scraping fails, the error is logged and tracked
- If match import fails for a tournament, the tournament status is updated to `'failed'`
- If player results import fails for a match, the match status is updated to `'failed'`
- The scheduler itself never crashes - it catches all errors and continues running

## Database Schema

The schedulers work with these tables:

### `nakka.tournaments`
- `tournament_id`: Primary key
- `nakka_identifier`: Unique identifier from Nakka.pl
- `tournament_name`: Name of the tournament
- `tournament_date`: Date of the tournament
- `href`: URL to the tournament page
- `match_import_status`: `NULL`, `'in_progress'`, `'completed'`, or `'failed'`

### `nakka.tournament_matches`
- `tournament_match_id`: Primary key
- `tournament_id`: Foreign key to tournaments
- `nakka_match_identifier`: Unique identifier from Nakka.pl
- `href`: URL to the match page
- `match_result_status`: `NULL`, `'in_progress'`, `'completed'`, or `'failed'`
- `imported_at`: Timestamp when match was first imported

### `nakka.tournament_match_player_results`
- Stores player statistics for each match
- Linked to `tournament_matches` via `tournament_match_id`

## Troubleshooting

### Scheduler doesn't start
- Check that all environment variables are set in `.env`
- Verify you have the service role key (not the public anon key)
- Check console for error messages

### Match Results Sync: Matches not being processed
- Verify matches exist in the database with status `NULL` or not `'completed'`
- Check the external scraper API is running (TopDarter API)
- Review logs for specific error messages

### Tournament Keyword Sync: Tournaments not being found
- Verify the keyword matches tournaments on Nakka.pl
- Check the external scraper API is running (TopDarter API)
- Try testing with `RUN_ON_STARTUP=true` to see immediate results
- Review logs for specific error messages

### Performance issues
- **Match Results Sync**: Reduce frequency by adjusting `MATCH_SYNC_CRON_SCHEDULE`
- **Tournament Keyword Sync**: Run less frequently (e.g., every 6-24 hours) since tournaments don't change often
- The match results scheduler processes max 30 matches per run to avoid overload
- Consider running during off-peak hours

