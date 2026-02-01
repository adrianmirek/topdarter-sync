# Fix: True Upsert Mechanism Using PostgreSQL ON CONFLICT

## Problem Identified

The batch insert was failing to insert new matches when some duplicates existed:

```
Scraped: 109 matches
Existing in DB: 108 matches
Expected: Insert 1 new match
Actual: Insert 0 matches (entire batch failed on first duplicate)
```

### Root Cause

Using `.insert()` which fails completely if **ANY** record violates the unique constraint:

```typescript
// OLD CODE - FAILS ON FIRST DUPLICATE
const { data, error } = await supabase
  .from("tournament_matches")
  .insert(matchRecords)  // ❌ Fails if ANY duplicate exists
  .select();
```

When it tries to insert all 109 matches and hits the first duplicate (match #1 already exists), the entire operation fails, and the 1 new match is never inserted.

## Solution: PostgreSQL Native Upsert

Use Supabase's `.upsert()` with `ignoreDuplicates: true`, which translates to PostgreSQL's:

```sql
INSERT INTO tournament_matches (...)
VALUES (...)
ON CONFLICT (tournament_id, nakka_match_identifier) DO NOTHING
```

This:
- ✅ Inserts new matches (the 1 new match)
- ✅ Silently skips existing matches (the 108 duplicates)
- ✅ All in ONE subrequest (stays under Cloudflare limit)

## Implementation

### Updated `upsertTournamentMatches()` Function

```typescript
// NEW CODE - TRUE UPSERT
const { data: upsertedMatches, error: upsertError } = await supabase
  .schema("nakka")
  .from("tournament_matches")
  .upsert(matchRecords, {
    onConflict: "tournament_id,nakka_match_identifier",  // Specify unique constraint
    ignoreDuplicates: true,  // DO NOTHING on conflict
  })
  .select("tournament_match_id");

// upsertedMatches contains ONLY the newly inserted matches
const insertedCount = upsertedMatches?.length || 0;

// Count total to calculate skipped
const { count: totalCount } = await supabase
  .from("tournament_matches")
  .select("tournament_match_id", { count: "exact", head: true })
  .eq("tournament_id", tournamentId);

const existingCount = totalCount || 0;
const skippedCount = existingCount - insertedCount;
```

### Key Differences

| Aspect | Old (.insert) | New (.upsert with ignoreDuplicates) |
|--------|--------------|-------------------------------------|
| Behavior on duplicate | ❌ Entire batch fails | ✅ Skips duplicate, continues |
| New matches inserted | 0 (because batch failed) | ✅ All new matches |
| Subrequests | 2 (failed insert + count query) | 2 (successful upsert + count query) |
| Result accuracy | ❌ Wrong (0 inserted, 108 skipped) | ✅ Correct (1 inserted, 108 skipped) |

## Example Scenario

### Before Fix

```
1. Scrape 109 matches
2. Try to insert all 109
3. First match already exists → ENTIRE BATCH FAILS
4. insertedCount = 0
5. Count existing = 108
6. skippedCount = 108
7. allMatchesSaved = false (108 ≠ 109)
8. Status = "in_progress" ❌ WRONG!
```

### After Fix

```
1. Scrape 109 matches
2. Upsert all 109 with ON CONFLICT DO NOTHING
3. PostgreSQL:
   - Skips 108 existing matches (silently)
   - Inserts 1 new match ✅
4. insertedCount = 1
5. Count total = 109
6. skippedCount = 108 (109 - 1)
7. allMatchesSaved = true (109 === 109)
8. Status = "matches_saved" ✅ CORRECT!
```

## Benefits

### 1. Correctness ✅
- All new matches are inserted, regardless of existing duplicates
- Accurate counts of inserted vs. skipped

### 2. Efficiency ✅
- Still uses only 2 subrequests:
  1. Batch upsert (inserts new, skips duplicates)
  2. Count total matches
- Well under Cloudflare's 50 subrequest limit

### 3. Reliability ✅
- No partial failures
- Idempotent operation (can run multiple times safely)
- Handles edge cases:
  - All matches are new → inserts all
  - All matches exist → skips all
  - Mix of new and existing → inserts new, skips existing ✅

### 4. PostgreSQL Native ✅
- Uses database's built-in ON CONFLICT clause
- Atomic operation at database level
- Optimal performance

## Subrequest Count

Total subrequests per tournament:

```
1. getTournamentStatus() → 1 subrequest
2. (If needed) saveTournament() → 1 subrequest
3. upsertTournamentMatches():
   - upsert() → 1 subrequest
   - count() → 1 subrequest
4. (If needed) update tournament status → 1 subrequest

Total: 3-5 subrequests per tournament
```

With 109 matches:
- **Before**: 109+ subrequests ❌ (hit limit at 45)
- **After**: 3-5 subrequests ✅ (well under limit)

## Files Modified

1. ✅ `src/lib/services/nakka.user.service.ts`
   - Updated `upsertTournamentMatches()` to use `.upsert()` with `ignoreDuplicates`
   - Proper calculation of inserted vs. skipped counts

2. ✅ `src/lib/services/nakka.service.ts`
   - Updated `importMatches()` to use `.upsert()` with `ignoreDuplicates`
   - Same fix for consistency

## Testing

### Test Case 1: All New Matches
```
Scraped: 109
Existing: 0
Expected: Insert 109, Skip 0, Status = matches_saved
✅ Works
```

### Test Case 2: All Existing Matches
```
Scraped: 109
Existing: 109
Expected: Insert 0, Skip 109, Status = matches_saved
✅ Works
```

### Test Case 3: Partial Existing (The Bug)
```
Scraped: 109
Existing: 108
Expected: Insert 1, Skip 108, Status = matches_saved
Before: Insert 0, Skip 108, Status = in_progress ❌
After: Insert 1, Skip 108, Status = matches_saved ✅
```

### Test Case 4: Multiple Missing Matches
```
Scraped: 109
Existing: 50
Expected: Insert 59, Skip 50, Status = matches_saved
✅ Works
```

## Expected Logs After Fix

```
[Guest] Tournament t_HPRh_2883 exists with status 'null', need to save matches
[Guest] Found 109 matches for tournament t_HPRh_2883
[Guest] Using existing tournament t_HPRh_2883 with ID 292
[Guest] Upserting matches for tournament t_HPRh_2883...
[Upsert] Starting batch upsert of 109 matches for tournament t_HPRh_2883...
[Upsert] Batch upsert completed: 1 new matches inserted
[Upsert] Total in DB: 109, Inserted: 1, Skipped: 108, Scraped: 109
[Guest] All 109 matches saved for tournament t_HPRh_2883, updating status to matches_saved ✅
[Guest] Tournament t_HPRh_2883 processing complete (ID: 292, status: matches_saved)
```

## Summary

The fix uses PostgreSQL's native `INSERT ... ON CONFLICT DO NOTHING` through Supabase's `.upsert()` method with `ignoreDuplicates: true`. This:

- ✅ Fixes the bug where new matches weren't inserted due to existing duplicates
- ✅ Maintains the 1-subrequest batch operation
- ✅ Stays well under Cloudflare's subrequest limit
- ✅ Provides accurate counts of inserted vs. skipped matches
- ✅ Works correctly for all edge cases

The solution is database-native, efficient, and correct! 🎯

