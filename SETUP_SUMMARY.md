# 🎯 Node-cron Scheduler Setup - Summary

## ✅ What Was Implemented

A **Node-cron based scheduler** that automatically processes incomplete tournament match results every 10 minutes.

### Core Functionality

**Query:**
```sql
SELECT tournament_match_id, nakka_match_identifier, href
FROM nakka.tournament_matches
WHERE match_result_status IS NULL OR match_result_status != 'completed'
ORDER BY imported_at DESC
LIMIT 30
```

**Processing:**
For each match → Calls `scrapeAndImportMatchPlayerResults` from `nakka.user.service.ts`

---

## 📦 Files Created

### 1. Main Scheduler
```
src/lib/scheduler/match-results-sync.ts
```
- Node-cron implementation
- Standalone Supabase client
- Fetches top 30 incomplete matches
- Processes each match sequentially
- Detailed logging with timestamps
- Error handling and recovery

### 2. Documentation
```
src/lib/scheduler/README.md           - Full documentation
src/lib/scheduler/QUICKSTART.md       - 5-minute quick start
src/lib/scheduler/ENV_SETUP.md        - Environment variables guide
SCHEDULER_SETUP_COMPLETE.md           - Complete setup guide
```

### 3. Updated Files
```
package.json                           - Added dependencies and npm script
```

---

## 📚 Dependencies Added

```json
{
  "dependencies": {
    "node-cron": "^3.0.3"
  },
  "devDependencies": {
    "@types/node-cron": "^3.0.11",
    "tsx": "^4.19.2"
  }
}
```

**Status:** ✅ Installed successfully

---

## 🚀 How to Use

### Step 1: Configure Environment Variables

Add to your `.env` file:

```env
# Required
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Optional
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *  # Default: every 10 minutes
RUN_ON_STARTUP=true                     # Default: false
```

⚠️ **Important:** Use `SUPABASE_SERVICE_ROLE_KEY` (not the public anon key)

### Step 2: Run the Scheduler

```bash
npm run sync:match-results
```

### Step 3: Watch It Work

You'll see output like:

```
========================================
Match Results Sync Scheduler Started
Schedule: */10 * * * *
========================================

Scheduler is running. Press Ctrl+C to stop.

[2026-01-14T10:00:00.000Z] Starting match results sync...
[Scheduler] Found 15 incomplete matches
[2026-01-14T10:00:00.000Z] Processing 15 incomplete matches...

[2026-01-14T10:00:01.000Z] [1/15] Processing match: t_Nd6M_9511_rr_2_3Tm2
[Scrape & Import] Starting scrape for match: t_Nd6M_9511_rr_2_3Tm2
...
[2026-01-14T10:00:03.000Z] ✓ Match processed successfully

[2026-01-14T10:05:00.000Z] Sync completed!
[2026-01-14T10:05:00.000Z] Total processed: 15
[2026-01-14T10:05:00.000Z] Successful: 14
[2026-01-14T10:05:00.000Z] Failed: 1
```

---

## ⚙️ Configuration

### Change Schedule

Edit `.env`:

```env
# Every 5 minutes
MATCH_SYNC_CRON_SCHEDULE=*/5 * * * *

# Every hour
MATCH_SYNC_CRON_SCHEDULE=0 * * * *

# Every day at 9 AM
MATCH_SYNC_CRON_SCHEDULE=0 9 * * *
```

Use [Crontab Guru](https://crontab.guru/) for custom schedules.

### Run Immediately on Startup

For testing:

```env
RUN_ON_STARTUP=true
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Node-cron Scheduler                       │
│                  (Every 10 minutes)                         │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│           Query nakka.tournament_matches                    │
│   WHERE match_result_status IS NULL OR != 'completed'       │
│   ORDER BY imported_at DESC                                 │
│   LIMIT 30                                                  │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              For each match (sequentially)                  │
│                                                             │
│   1. Update status → 'in_progress'                          │
│   2. Scrape player results from Nakka.pl                    │
│   3. Import to tournament_match_player_results              │
│   4. Update status → 'completed' or 'failed'                │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎁 Features

✅ **Automatic Processing** - Runs every 10 minutes (configurable)  
✅ **Smart Querying** - Finds incomplete matches ordered by import date  
✅ **Batch Processing** - Handles up to 30 matches per run  
✅ **Error Recovery** - Continues on errors, logs details  
✅ **Detailed Logging** - Timestamps, progress, summaries  
✅ **Configurable** - Cron schedule, startup behavior  
✅ **Standalone** - No Astro dependency, pure Node.js  
✅ **Production Ready** - PM2, systemd, Task Scheduler support  

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| `QUICKSTART.md` | Get started in 5 minutes |
| `README.md` | Complete documentation |
| `ENV_SETUP.md` | Environment variables guide |
| `SCHEDULER_SETUP_COMPLETE.md` | Full setup guide with examples |

---

## 🔍 Quick Check

Verify everything is ready:

```bash
# 1. Check dependencies installed
npm list node-cron tsx @types/node-cron

# 2. Check npm script exists
npm run | grep sync:match-results

# 3. Verify files exist
ls src/lib/scheduler/
```

---

## 🚦 Next Steps

1. **Add environment variables** to `.env`
2. **Run the scheduler**: `npm run sync:match-results`
3. **Monitor the logs** to see processing
4. **Adjust schedule** as needed in `.env`
5. **Deploy to production** with PM2/Task Scheduler/systemd

---

## 🎉 Ready to Go!

Your scheduler is fully set up and ready to use. To start it right now:

```bash
npm run sync:match-results
```

The scheduler will:
- Start immediately
- Show you the cron schedule
- Process matches every 10 minutes (or your custom schedule)
- Log all activity with timestamps
- Continue running until you press Ctrl+C

**Happy scheduling!** 🚀

---

## 💡 Tips

- **Testing:** Set `RUN_ON_STARTUP=true` to test immediately
- **Monitoring:** Check logs for processing status
- **Performance:** Default 30 matches per run prevents overload
- **Production:** Use PM2 for auto-restart and monitoring
- **Security:** Keep `SUPABASE_SERVICE_ROLE_KEY` secret

---

## 🆘 Need Help?

- **Quick Start:** `src/lib/scheduler/QUICKSTART.md`
- **Environment Setup:** `src/lib/scheduler/ENV_SETUP.md`
- **Full Docs:** `src/lib/scheduler/README.md`
- **Complete Guide:** `SCHEDULER_SETUP_COMPLETE.md`

