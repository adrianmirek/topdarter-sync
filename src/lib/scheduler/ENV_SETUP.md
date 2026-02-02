# Environment Variables Setup

This document explains the environment variables needed for the schedulers (Match Results Sync and Tournament Keyword Sync).

## Required Environment Variables

### 1. SUPABASE_URL
Your Supabase project URL.

**Example:**
```env
SUPABASE_URL=https://abcdefghijklmnop.supabase.co
```

**Where to find it:**
- Supabase Dashboard → Settings → API → Project URL

---

### 2. SUPABASE_SERVICE_ROLE_KEY
Your Supabase service role key (NOT the anon/public key).

**Example:**
```env
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Where to find it:**
- Supabase Dashboard → Settings → API → Project API keys → `service_role` (secret)

**⚠️ Important:**
- This key bypasses Row Level Security (RLS) policies
- Never expose this key in client-side code
- Never commit this key to version control
- The scheduler needs this to access the database without user authentication

**Why not use SUPABASE_PUBLIC_KEY?**
- The public/anon key respects RLS policies
- The scheduler runs server-side without a user session
- RLS policies would block the scheduler from accessing data

---

## Optional Environment Variables

### 3. MATCH_SYNC_CRON_SCHEDULE
Customize when the scheduler runs.

**Default:** `*/10 * * * *` (every 10 minutes)

**Examples:**
```env
# Every 5 minutes
MATCH_SYNC_CRON_SCHEDULE=*/5 * * * *

# Every hour
MATCH_SYNC_CRON_SCHEDULE=0 * * * *

# Every hour at 30 minutes past
MATCH_SYNC_CRON_SCHEDULE=30 * * * *

# Every day at 9 AM
MATCH_SYNC_CRON_SCHEDULE=0 9 * * *

# Every Monday at 6 AM
MATCH_SYNC_CRON_SCHEDULE=0 6 * * 1

# Every minute (for testing only)
MATCH_SYNC_CRON_SCHEDULE=* * * * *
```

**Cron Format:**
```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-7, 0 or 7 is Sunday)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

**Resources:**
- [Crontab Guru](https://crontab.guru/) - Interactive cron expression editor

---

### 4. RUN_ON_STARTUP
Run sync immediately when the scheduler starts (useful for testing).

**Default:** `false`

**Example:**
```env
# Run sync immediately on startup
RUN_ON_STARTUP=true
```

**When to use:**
- Testing the scheduler
- Verifying configuration
- Development environment

**When NOT to use:**
- Production environments (unless you specifically want this behavior)
- If you have many incomplete matches and want to control when the first sync runs

---

### 5. TOURNAMENT_SYNC_KEYWORDS
Keywords to search for when syncing tournaments (comma-separated for multiple keywords).

**Default:** `agawa`

**Examples:**
```env
# Single keyword
TOURNAMENT_SYNC_KEYWORDS=agawa

# Multiple keywords
TOURNAMENT_SYNC_KEYWORDS=agawa,wroclaw,katowice
```

**When to use:**
- To automatically discover and sync tournaments matching specific keywords
- For tracking tournaments from specific locations or organizations

---

### 6. TOURNAMENT_SYNC_CRON_SCHEDULE
Customize when the tournament keyword sync runs.

**Default:** `* * * * *` (every minute - for testing)

**Examples:**
```env
# Every minute (for testing)
TOURNAMENT_SYNC_CRON_SCHEDULE=* * * * *

# Every hour
TOURNAMENT_SYNC_CRON_SCHEDULE=0 * * * *

# Every 6 hours
TOURNAMENT_SYNC_CRON_SCHEDULE=0 */6 * * *

# Every day at 3 AM
TOURNAMENT_SYNC_CRON_SCHEDULE=0 3 * * *

# Every day at 9 AM and 9 PM
TOURNAMENT_SYNC_CRON_SCHEDULE=0 9,21 * * *
```

**Recommended for production:** Every 6-24 hours (tournaments don't change frequently)

**Cron Format:**
```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-7, 0 or 7 is Sunday)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

**Resources:**
- [Crontab Guru](https://crontab.guru/) - Interactive cron expression editor

---

## Complete .env Example

Create or update your `.env` file with:

```env
# ===================================
# Supabase Configuration (REQUIRED)
# ===================================
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLIC_KEY=your-anon-public-key-for-frontend
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-for-scheduler

# ===================================
# TopDarter API (for scraping)
# ===================================
TOPDARTER_API_KEY=your-topdarter-api-key

# ===================================
# Scheduler Configuration (OPTIONAL)
# ===================================
# Match results sync - Cron schedule (default: every 10 minutes)
MATCH_SYNC_CRON_SCHEDULE=*/10 * * * *

# Tournament keyword sync - Cron schedule (default: every minute for testing)
TOURNAMENT_SYNC_CRON_SCHEDULE=* * * * *

# Keywords to search for tournaments (comma-separated)
TOURNAMENT_SYNC_KEYWORDS=agawa

# Run sync on startup (default: false)
RUN_ON_STARTUP=false
```

---

## Verification

### Check if environment variables are loaded:

Create a test file `test-env.ts`:

```typescript
import 'dotenv/config';

console.log('SUPABASE_URL:', process.env.SUPABASE_URL ? '✓ Set' : '✗ Missing');
console.log('SUPABASE_SERVICE_ROLE_KEY:', process.env.SUPABASE_SERVICE_ROLE_KEY ? '✓ Set' : '✗ Missing');
console.log('MATCH_SYNC_CRON_SCHEDULE:', process.env.MATCH_SYNC_CRON_SCHEDULE || 'Using default (*/10 * * * *)');
console.log('TOURNAMENT_SYNC_CRON_SCHEDULE:', process.env.TOURNAMENT_SYNC_CRON_SCHEDULE || 'Using default (* * * * *)');
console.log('TOURNAMENT_SYNC_KEYWORDS:', process.env.TOURNAMENT_SYNC_KEYWORDS || 'agawa (default)');
console.log('RUN_ON_STARTUP:', process.env.RUN_ON_STARTUP || 'false (default)');
```

Run it:

```bash
npx tsx test-env.ts
```

Expected output:

```
SUPABASE_URL: ✓ Set
SUPABASE_SERVICE_ROLE_KEY: ✓ Set
MATCH_SYNC_CRON_SCHEDULE: */10 * * * *
TOURNAMENT_SYNC_CRON_SCHEDULE: * * * * *
TOURNAMENT_SYNC_KEYWORDS: agawa
RUN_ON_STARTUP: false
```

---

## Troubleshooting

### Environment variables not loading

**Problem:** Scheduler says "Missing required Supabase environment variables"

**Solutions:**

1. **Check .env file exists:**
   ```bash
   # Windows
   dir .env
   
   # Linux/Mac
   ls -la .env
   ```

2. **Check .env file location:**
   - Must be in the project root directory
   - Same directory as `package.json`

3. **Check variable names:**
   - Must be exactly: `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
   - No spaces around `=` sign
   - No quotes needed (unless value contains spaces)

4. **Reload environment:**
   - Restart your terminal
   - Restart the scheduler
   - Restart your IDE (if using one)

5. **Check for typos:**
   ```env
   # ✗ Wrong
   SUPABASE_UR=...
   SUPABASE_SERIVCE_ROLE_KEY=...
   
   # ✓ Correct
   SUPABASE_URL=...
   SUPABASE_SERVICE_ROLE_KEY=...
   ```

---

### Using wrong Supabase key

**Problem:** Scheduler runs but gets 401/403 errors from Supabase

**Cause:** Using `SUPABASE_PUBLIC_KEY` instead of `SUPABASE_SERVICE_ROLE_KEY`

**Solution:**

1. Go to Supabase Dashboard → Settings → API
2. Copy the **service_role** key (NOT the anon key)
3. Update `.env`:
   ```env
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   ```

**Visual Guide:**

In Supabase Dashboard API Settings, you'll see:

```
Project API keys
├── anon public    ← Don't use this for scheduler
└── service_role   ← Use this for scheduler ✓
```

---

### Testing configuration

**Quick test command:**

```bash
# Test match results sync immediately
RUN_ON_STARTUP=true npm run sync:match-results

# Test tournament keyword sync immediately
RUN_ON_STARTUP=true npm run sync:tournaments
```

This will:
1. Start the scheduler
2. Run sync immediately
3. Show any configuration errors right away

**Press Ctrl+C to stop after testing.**

---

## Security Best Practices

1. **Never commit `.env` to version control**
   - Add `.env` to `.gitignore`
   - Use `.env.example` for documentation (without real values)

2. **Rotate keys regularly**
   - Generate new service role key every 6-12 months
   - Update in Supabase Dashboard

3. **Restrict access**
   - Only deploy service role key to production server
   - Don't share via email, Slack, etc.
   - Use secure secrets management (AWS Secrets Manager, Azure Key Vault, etc.)

4. **Monitor usage**
   - Check Supabase Dashboard → Logs for unusual activity
   - Set up alerts for excessive API usage

---

## Need Help?

- Supabase Documentation: https://supabase.com/docs
- Cron Expression Editor: https://crontab.guru/
- Project Issues: Create an issue in the repository

