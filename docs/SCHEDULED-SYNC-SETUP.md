# Scheduled Syncing Setup (GitHub Actions)

Since Cloudflare Pages free plan doesn't support cron triggers, this project uses **GitHub Actions** to trigger scheduled syncs.

## How It Works

1. **GitHub Actions workflow** (`.github/workflows/scheduled-sync.yml`) runs on schedule
2. It calls your deployed API endpoints:
   - `/api/sync/tournaments` - every 15 minutes
   - `/api/sync/match-results` - every 10 minutes
3. The API endpoints perform the actual syncing logic

## Setup Instructions

### 1. Generate a Sync API Key

Generate a secure random key:

```bash
# On Windows (PowerShell)
$key = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | % {[char]$_})
echo $key

# On Linux/Mac
openssl rand -base64 32
```

### 2. Add to Cloudflare Environment Variables

In your Cloudflare Pages dashboard:
- Go to **Settings → Environment Variables**
- Add `SYNC_API_KEY` with the generated key (for both Production and Preview)

### 3. Add GitHub Repository Secrets

In your GitHub repository:
- Go to **Settings → Secrets and variables → Actions**
- Click **New repository secret**
- Add these secrets:
  - `APP_URL`: Your deployed app URL (e.g., `https://darterassistant.pages.dev`)
  - `SYNC_API_KEY`: The same key you added to Cloudflare

### 4. Test the Workflow

#### Manual Test:
1. Go to **Actions** tab in GitHub
2. Select **Scheduled Data Sync** workflow
3. Click **Run workflow** → **Run workflow**
4. Check the logs to verify it ran successfully

#### Automatic Schedule:
- Runs automatically based on cron schedule
- Tournament sync: every 15 minutes
- Match results sync: every 10 minutes

## API Endpoints

### POST /api/sync/tournaments
Triggers tournament keyword sync.

**Headers:**
```
Authorization: Bearer YOUR_SYNC_API_KEY
Content-Type: application/json
```

**Response:**
```json
{
  "timestamp": "2026-02-26T10:00:00.000Z",
  "keywords_found": 3,
  "success": 3,
  "failed": 0,
  "results": [...]
}
```

### POST /api/sync/match-results
Triggers match results sync.

**Headers:**
```
Authorization: Bearer YOUR_SYNC_API_KEY
Content-Type: application/json
```

**Response:**
```json
{
  "timestamp": "2026-02-26T10:00:00.000Z",
  "matches_found": 15,
  "success": 15,
  "failed": 0,
  "results": [...]
}
```

## Monitoring

### View Sync Logs:
1. Go to **Actions** tab in GitHub
2. Click on a workflow run
3. Expand job steps to see detailed logs

### Check Sync Status:
- Each run shows success/failure count
- Failed syncs include error details
- Cloudflare Functions logs also available in Pages dashboard

## Alternative Options

If GitHub Actions doesn't meet your needs:

1. **Local Scheduler** - Keep using `npm run sync:tournaments` and `npm run sync:match-results` on a server
2. **External Cron Service** - Use services like:
   - [cron-job.org](https://cron-job.org) (free tier available)
   - [EasyCron](https://www.easycron.com) (free tier available)
   - AWS EventBridge (free tier available)
3. **Upgrade to Cloudflare Workers** - Paid plan with native cron support

## Troubleshooting

### "Invalid API key" error:
- Verify `SYNC_API_KEY` matches in both GitHub Secrets and Cloudflare Environment Variables
- Check there are no extra spaces or newlines

### "Sync service not configured" error:
- Ensure `SYNC_API_KEY` is set in Cloudflare Environment Variables
- Redeploy after adding environment variables

### Workflow not running:
- GitHub Actions free tier has minute precision, not second
- Workflows may be delayed by a few minutes during high load
- Check the Actions tab for any disabled workflows

### No matches/keywords to sync:
- This is normal if everything is already up to date
- Check database to verify keywords exist in `nakka.keyword` table
