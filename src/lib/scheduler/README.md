# Match Results Sync Scheduler

This scheduler automatically processes incomplete match results by scraping player statistics from Nakka.pl and importing them into the database.

## How It Works

1. **Fetches Incomplete Matches**: Queries the database for up to 30 matches where `match_result_status` is `NULL` or not `'completed'`, ordered by `imported_at DESC` (most recent first).

2. **Processes Each Match**: For each incomplete match, it calls `scrapeAndImportMatchPlayerResults` which:
   - Scrapes player statistics from the match page on Nakka.pl
   - Imports the data into the `nakka.tournament_match_player_results` table
   - Updates the match status to `'completed'` on success or `'failed'` on error

3. **Runs on Schedule**: By default, runs every 10 minutes using node-cron.

## Environment Variables

Required in your `.env` file:

```env
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Optional: Customize cron schedule (default: */10 * * * * = every 10 minutes)
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *

# Optional: Run sync immediately on startup (default: false)
RUN_ON_STARTUP=true
```

**Important**: Use `SUPABASE_SERVICE_ROLE_KEY` (not the public anon key) to bypass Row Level Security policies.

## Cron Schedule Examples

- Every 10 minutes (default): `*/10 * * * *`
- Every 5 minutes: `*/5 * * * *`
- Every hour: `0 * * * *`
- Every hour at 30 minutes: `30 * * * *`
- Every day at 9 AM: `0 9 * * *`
- Every minute (for testing): `* * * * *`

## Usage

### Development

```bash
# Install dependencies (if not already installed)
npm install

# Run the scheduler
npm run sync:match-results
```

The scheduler will:
- Start and display the schedule
- Run the sync based on the cron schedule
- Display detailed logs for each match processed
- Keep running until you stop it (Ctrl+C)

### Production

For production deployment, you can use:

1. **PM2** (Process Manager):
```bash
pm2 start npm --name "match-sync" -- run sync:match-results
pm2 save
pm2 startup
```

2. **Windows Task Scheduler**: Schedule the command to run on system startup
3. **systemd** (Linux): Create a systemd service
4. **Docker**: Include in your Docker container's startup script

## Logs

The scheduler outputs detailed logs:
- Match processing progress (e.g., `[3/30] Processing match...`)
- Success/failure status for each match
- Summary statistics at the end of each sync
- Timestamps for all operations

## Error Handling

- If a match fails to process, the error is logged and the scheduler continues with the next match
- Match status is updated to `'failed'` with error details in the database
- The scheduler itself never crashes - it catches all errors and continues running

## Database Schema

The scheduler works with these tables:

### `nakka.tournament_matches`
- `tournament_match_id`: Primary key
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

### Matches not being processed
- Verify matches exist in the database with status `NULL` or not `'completed'`
- Check the external scraper API is running (TopDarter API)
- Review logs for specific error messages

### Performance issues
- Reduce the frequency by adjusting `MATCH_SYNC_CRON_SCHEDULE`
- The scheduler processes max 30 matches per run to avoid overload
- Consider running during off-peak hours

