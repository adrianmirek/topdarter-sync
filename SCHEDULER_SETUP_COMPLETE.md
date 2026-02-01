# ✅ Match Results Sync Scheduler - Setup Complete!

The Node-cron scheduler has been successfully set up for automatically processing tournament match results.

## 📁 What Was Created

### Main Files

1. **`src/lib/scheduler/match-results-sync.ts`**
   - Main scheduler implementation
   - Fetches top 30 incomplete matches from database
   - Processes each match using `scrapeAndImportMatchPlayerResults`
   - Runs on configurable cron schedule (default: every 10 minutes)

2. **`package.json`** (updated)
   - Added dependencies: `node-cron` (^3.0.3)
   - Added dev dependencies: `@types/node-cron` (^3.0.11), `tsx` (^4.19.2)
   - Added npm script: `sync:match-results`

### Documentation Files

3. **`src/lib/scheduler/README.md`**
   - Comprehensive documentation
   - How the scheduler works
   - Environment variable reference
   - Troubleshooting guide

4. **`src/lib/scheduler/QUICKSTART.md`**
   - 5-minute quick start guide
   - Step-by-step setup instructions
   - Example output
   - Common issues and solutions

5. **`src/lib/scheduler/ENV_SETUP.md`**
   - Detailed environment variables documentation
   - Cron expression guide
   - Security best practices
   - Verification steps

## 🚀 How to Use

### Quick Start (3 Steps)

1. **Set up environment variables** (in your `.env` file):
   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
   MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *  # Optional: every 10 minutes (default)
   RUN_ON_STARTUP=true                     # Optional: run immediately (default: false)
   ```

2. **Install dependencies** (already done):
   ```bash
   npm install
   ```

3. **Start the scheduler**:
   ```bash
   npm run sync:match-results
   ```

That's it! The scheduler is now running and will process matches every 10 minutes.

## 🎯 What It Does

### Scheduler Logic

Every 10 minutes (or your custom schedule), the scheduler:

1. **Queries Database:**
   ```sql
   SELECT tournament_match_id, nakka_match_identifier, href
   FROM nakka.tournament_matches
   WHERE match_result_status IS NULL OR match_result_status != 'completed'
   ORDER BY imported_at DESC
   LIMIT 30
   ```

2. **Processes Each Match:**
   - Calls `scrapeAndImportMatchPlayerResults` from `nakka.user.service.ts`
   - Scrapes player statistics from Nakka.pl match page
   - Imports data to `nakka.tournament_match_player_results` table
   - Updates `match_result_status` to `'completed'` or `'failed'`

3. **Logs Results:**
   - Progress counter (e.g., `[3/30] Processing match...`)
   - Success/failure status for each match
   - Summary statistics (total, successful, failed)

### Error Handling

- If a match fails, the error is logged and the scheduler continues with the next match
- Match status is updated to `'failed'` with error details
- The scheduler itself never crashes - it catches all errors

## 📊 Database Schema

The scheduler works with these tables:

### `nakka.tournament_matches`
```sql
CREATE TABLE nakka.tournament_matches (
  tournament_match_id SERIAL PRIMARY KEY,
  tournament_id INTEGER REFERENCES nakka.tournaments(tournament_id),
  nakka_match_identifier TEXT NOT NULL,
  match_type TEXT NOT NULL,
  first_player_name TEXT NOT NULL,
  first_player_code TEXT NOT NULL,
  second_player_name TEXT NOT NULL,
  second_player_code TEXT NOT NULL,
  href TEXT NOT NULL,
  match_result_status TEXT CHECK (match_result_status IN ('in_progress', 'completed', 'failed')),
  match_result_error TEXT,
  imported_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (tournament_id, nakka_match_identifier)
);
```

### `nakka.tournament_match_player_results`
```sql
CREATE TABLE nakka.tournament_match_player_results (
  tournament_match_player_result_id SERIAL PRIMARY KEY,
  tournament_match_id INTEGER REFERENCES nakka.tournament_matches(tournament_match_id),
  nakka_match_player_identifier TEXT NOT NULL,
  average_score NUMERIC(5,2),
  first_nine_avg NUMERIC(5,2),
  checkout_percentage NUMERIC(5,2),
  score_60_count INTEGER,
  score_100_count INTEGER,
  score_140_count INTEGER,
  score_180_count INTEGER,
  high_finish INTEGER,
  best_leg INTEGER,
  worst_leg INTEGER,
  player_score INTEGER,
  opponent_score INTEGER,
  UNIQUE (tournament_match_id, nakka_match_player_identifier)
);
```

## ⚙️ Configuration Options

### Cron Schedule

Change how often the scheduler runs:

```env
# Every 10 minutes (default)
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *

# Every 5 minutes
MATCH_SYNC_CRON_SCHEDULE=*/5 * * * *

# Every hour
MATCH_SYNC_CRON_SCHEDULE=0 * * * *

# Every day at 9 AM
MATCH_SYNC_CRON_SCHEDULE=0 9 * * *

# Every Monday at 6 AM
MATCH_SYNC_CRON_SCHEDULE=0 6 * * 1
```

Use [Crontab Guru](https://crontab.guru/) to create custom schedules.

### Run on Startup

Run sync immediately when scheduler starts (useful for testing):

```env
RUN_ON_STARTUP=true
```

## 🔧 Production Deployment

### Option 1: PM2 (Recommended)

```bash
# Install PM2 globally
npm install -g pm2

# Start scheduler
pm2 start npm --name "match-sync" -- run sync:match-results

# Save configuration
pm2 save

# Setup auto-start on system boot
pm2 startup
```

### Option 2: Windows Task Scheduler

1. Open Task Scheduler
2. Create Basic Task
3. Trigger: At system startup
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-Command "cd D:\Repo\AI\darterassistant; npm run sync:match-results"`

### Option 3: systemd (Linux)

Create `/etc/systemd/system/match-sync.service`:

```ini
[Unit]
Description=Match Results Sync Scheduler
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/darterassistant
ExecStart=/usr/bin/npm run sync:match-results
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable match-sync
sudo systemctl start match-sync
sudo systemctl status match-sync
```

## 📝 Example Output

```
========================================
Match Results Sync Scheduler Started
Schedule: */10 * * * *
========================================

Scheduler is running. Press Ctrl+C to stop.

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

[2026-01-14T10:00:04.000Z] [2/15] Processing match: t_Nd6M_9511_rr_3_4Kp8
...

[2026-01-14T10:05:00.000Z] ========================================
[2026-01-14T10:05:00.000Z] Sync completed!
[2026-01-14T10:05:00.000Z] Total processed: 15
[2026-01-14T10:05:00.000Z] Successful: 14
[2026-01-14T10:05:00.000Z] Failed: 1
[2026-01-14T10:05:00.000Z] ========================================
```

## 🐛 Troubleshooting

### Scheduler doesn't start

**Error:** "Missing required Supabase environment variables"

**Solution:**
```env
# Add to .env file
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

---

### No matches being processed

**Error:** "No incomplete matches found"

**Check database:**
```sql
SELECT COUNT(*) 
FROM nakka.tournament_matches 
WHERE match_result_status IS NULL OR match_result_status != 'completed';
```

**Solution:** Import matches first using the tournament sync functionality.

---

### Scraping fails

**Error:** 401/403 from scraper API

**Solution:**
1. Check TopDarter scraper API is running: `http://localhost:3001`
2. Verify `TOPDARTER_API_KEY` in `.env`
3. Check API is accessible from your machine

---

### "tsx: command not found"

**Solution:**
```bash
npm install
```

This installs `tsx` which is needed to run TypeScript files.

## 📚 Additional Resources

- **Quick Start Guide:** `src/lib/scheduler/QUICKSTART.md`
- **Full Documentation:** `src/lib/scheduler/README.md`
- **Environment Setup:** `src/lib/scheduler/ENV_SETUP.md`
- **Cron Expression Editor:** https://crontab.guru/

## 🎉 Next Steps

1. **Set up your `.env` file** with Supabase credentials
2. **Run the scheduler:** `npm run sync:match-results`
3. **Monitor the logs** to see matches being processed
4. **Configure cron schedule** to your preference
5. **Deploy to production** using PM2, Task Scheduler, or systemd

---

## ✨ Features

- ✅ Automatic processing of incomplete matches
- ✅ Configurable cron schedule
- ✅ Detailed logging with timestamps
- ✅ Error handling and recovery
- ✅ Progress tracking (e.g., [3/30])
- ✅ Summary statistics after each run
- ✅ Standalone Supabase client (no Astro dependency)
- ✅ Run on startup option for testing
- ✅ Processes up to 30 matches per run (prevents overload)
- ✅ Comprehensive documentation

---

**Congratulations! Your match results sync scheduler is ready to use!** 🎉

To start using it right now:

```bash
npm run sync:match-results
```

Press `Ctrl+C` to stop the scheduler when needed.

