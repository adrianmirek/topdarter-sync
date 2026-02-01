# Updated Tournament Processing Logic

## Summary of Changes

Updated the `retrieveTournamentsMatchesByKeywordAndNickNameForGuest()` function to correctly handle tournament status checking according to requirements.

## Decision Flow

```
┌─────────────────────────────────┐
│ Check Tournament in Database    │
└────────────┬────────────────────┘
             │
             ├─────────────────────────────────────────┐
             │                                         │
             ▼                                         ▼
    ┌─────────────────┐                      ┌────────────────┐
    │ Tournament      │                      │ Tournament     │
    │ Doesn't Exist   │                      │ Exists         │
    └────────┬────────┘                      └────────┬───────┘
             │                                        │
             │                                        │ Get Status
             │                                        │
             │                                        ├──────────────────────┐
             │                                        │                      │
             │                                        ▼                      ▼
             │                               ┌────────────────┐    ┌─────────────────┐
             │                               │ matches_saved  │    │ NULL / failed / │
             │                               │ OR             │    │ in_progress     │
             │                               │ completed      │    └────────┬────────┘
             │                               └────────┬───────┘             │
             │                                        │                     │
             │                                        ▼                     │
             │                               ┌─────────────────┐            │
             │                               │ SKIP PROCESSING │            │
             │                               │ Retrieve from DB│            │
             │                               └─────────────────┘            │
             │                                                              │
             └──────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
                               ┌──────────────────────────┐
                               │ CONTINUE PROCESSING       │
                               │ Scrape & Save Matches     │
                               └──────────┬────────────────┘
                                          │
                        ┌─────────────────┴──────────────────┐
                        │                                    │
                        ▼                                    ▼
           ┌────────────────────────┐        ┌──────────────────────────┐
           │ Tournament doesn't     │        │ Tournament exists        │
           │ exist:                 │        │ (NULL/failed/in_progress)│
           │ 1. Save tournament     │        │ 1. Use existing ID       │
           │ 2. Upsert matches      │        │ 2. Upsert matches        │
           └────────────────────────┘        └──────────────────────────┘
```

## Detailed Logic

### Step 1: Get Tournament Status

```typescript
const tournamentInfo = await getTournamentStatus(supabase, tournament.nakka_identifier);
// Returns: { tournamentId, status } or null
```

### Step 2: Decision Based on Status

#### ✅ SKIP Processing (Retrieve Only)

**Condition:** Tournament exists AND status is `'matches_saved'` OR `'completed'`

```typescript
if (tournamentInfo && 
    (tournamentInfo.status === 'matches_saved' || tournamentInfo.status === 'completed')) {
  // Skip scraping and match saving
  // Just retrieve matches from DB
}
```

**Why?** All matches are already in the database. No need to scrape or save again.

#### 🔄 CONTINUE Processing (Scrape & Save)

**Conditions:**
- Tournament doesn't exist (`tournamentInfo === null`)
- Tournament exists with status = `NULL`
- Tournament exists with status = `'failed'`
- Tournament exists with status = `'in_progress'`

```typescript
else {
  // Need to process matches
}
```

**Why?** Matches aren't fully saved yet or need to be retried.

### Step 3: Processing Flow

#### Case A: Tournament Doesn't Exist
```typescript
if (!tournamentInfo) {
  // 1. Save tournament first
  const savedTournament = await saveTournament(supabase, tournament);
  savedTournamentId = savedTournament.tournamentId;
  
  // 2. Upsert matches
  await upsertTournamentMatches(...);
}
```

#### Case B: Tournament Exists (NULL/failed/in_progress)
```typescript
else {
  // 1. Use existing tournament ID
  savedTournamentId = tournamentInfo.tournamentId;
  
  // 2. Upsert matches (will skip duplicates)
  await upsertTournamentMatches(...);
}
```

### Step 4: Update Status Based on Result

```typescript
if (upsertResult.allMatchesSaved) {
  newStatus = "matches_saved"; // ✅ All matches in DB
} else if (upsertResult.insertedCount > 0 || upsertResult.skippedCount > 0) {
  newStatus = "in_progress"; // ⚠️ Partial save
} else {
  newStatus = null; // ❌ Nothing saved
}
```

## Examples

### Example 1: Brand New Tournament
```
Input: Tournament "t_HPRh_2883" doesn't exist in DB

Flow:
1. getTournamentStatus() → null (doesn't exist)
2. Continue processing (not skipped)
3. scrapeTournamentMatches() → 109 matches
4. saveTournament() → tournament_id = 291
5. upsertTournamentMatches() → all 109 inserted
6. Update status → "matches_saved" ✅

Result: Tournament saved with all 109 matches
```

### Example 2: Tournament with Failed Status
```
Input: Tournament "t_ABC_123" exists with status = "failed"

Flow:
1. getTournamentStatus() → { tournamentId: 42, status: "failed" }
2. Continue processing (status is "failed", not "matches_saved" or "completed")
3. scrapeTournamentMatches() → 50 matches
4. Use existing tournament_id = 42
5. upsertTournamentMatches() → retry inserting matches
6. Update status → "matches_saved" ✅

Result: Failed tournament retried and fixed
```

### Example 3: Tournament Already Completed
```
Input: Tournament "t_XYZ_789" exists with status = "completed"

Flow:
1. getTournamentStatus() → { tournamentId: 100, status: "completed" }
2. SKIP processing (status is "completed")
3. getTournamentMatchesFromDB() → retrieve from database
4. Return matches to user

Result: No scraping, just DB retrieval (optimization) ✅
```

### Example 4: Tournament with NULL Status
```
Input: Tournament "t_DEF_456" exists with status = NULL

Flow:
1. getTournamentStatus() → { tournamentId: 50, status: null }
2. Continue processing (status is NULL)
3. scrapeTournamentMatches() → 75 matches
4. Use existing tournament_id = 50
5. upsertTournamentMatches() → insert matches
6. Update status → "matches_saved" ✅

Result: Tournament had no matches, now has all 75
```

## Key Benefits

### 1. Smart Skipping
- ✅ Don't re-scrape tournaments that are fully saved
- ✅ Don't re-scrape tournaments that are completed
- 🚀 Faster response for repeat searches

### 2. Intelligent Retry
- ✅ Retry failed tournaments automatically
- ✅ Continue partial saves (in_progress)
- ✅ Fill in missing matches for NULL status

### 3. Efficient Processing
- ✅ Reuse existing tournament records
- ✅ Batch insert prevents duplicate constraint errors
- ✅ One database query to get both existence and status

## Status Transitions

```
NULL (no matches)
  ↓
matches_saved (all matches saved)
  ↓
in_progress (match results being imported)
  ↓
completed (all match results imported)

OR

NULL/matches_saved/in_progress
  ↓
failed (error during processing)
  ↓
NULL/matches_saved/in_progress (retry)
```

## Files Modified

1. ✅ `src/lib/services/nakka.user.service.ts`
   - Replaced `checkTournamentExists()` with `getTournamentStatus()`
   - Updated decision logic in `retrieveTournamentsMatchesByKeywordAndNickNameForGuest()`
   - Improved logging messages

## Testing Scenarios

### Test 1: New Tournament
- ✅ Should save tournament + all matches
- ✅ Status should become "matches_saved"

### Test 2: Tournament with matches_saved
- ✅ Should skip scraping
- ✅ Should retrieve from DB only

### Test 3: Tournament with completed
- ✅ Should skip scraping
- ✅ Should retrieve from DB only

### Test 4: Tournament with NULL
- ✅ Should scrape and save matches
- ✅ Should reuse tournament record

### Test 5: Tournament with failed
- ✅ Should retry scraping
- ✅ Should update status on success

The logic is now complete and matches your requirements perfectly! 🎯

