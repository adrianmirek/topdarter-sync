# Fix: Add "matches_saved" Status Support

## Issue Identified

When testing the new batch insert solution, the database rejected the `"matches_saved"` status with this error:

```
"new row for relation \"tournaments\" violates check constraint \"tournaments_match_import_status_check\""
```

### Root Causes

1. **Missing CHECK constraint value**: The database CHECK constraint only allowed: `('in_progress', 'completed', 'failed')`
2. **Trigger override**: The automatic status calculation trigger was overriding `"matches_saved"` to `"in_progress"` because it didn't account for this new status

## Solution: Database Migration

Created: `supabase/migrations/20260111000000_add_matches_saved_status.sql`

### Changes Made

#### 1. Updated CHECK Constraint
```sql
ALTER TABLE nakka.tournaments
  ADD CONSTRAINT tournaments_match_import_status_check
  CHECK (match_import_status IN ('matches_saved', 'in_progress', 'completed', 'failed'));
```

Now allows the new `"matches_saved"` value.

#### 2. Updated Trigger Function
Modified `nakka.calculate_tournament_match_import_status()` to:
- **Respect `"matches_saved"` status**: If tournament has this status and no match results processing has started, keep it
- **Don't override prematurely**: Only change status when match results are actually being processed

Key logic added:
```sql
ELSIF v_current_status = 'matches_saved' 
      AND v_completed_matches = 0 
      AND v_failed_matches = 0 
      AND v_in_progress_matches = 0 THEN
  v_status := 'matches_saved';  -- Keep it!
```

## Status Flow Diagram

```
┌─────┐
│NULL │  Tournament saved, no matches yet
└──┬──┘
   │
   ▼
┌────────────────┐
│ matches_saved  │  All matches saved ✅ (NEW STATUS)
└───────┬────────┘
        │ (User starts importing match results)
        ▼
┌────────────────┐
│  in_progress   │  Match results being imported
└───────┬────────┘
        │
        ├──────────┐
        ▼          ▼
┌───────────┐  ┌──────┐
│ completed │  │failed│  Match results import done
└───────────┘  └──────┘
```

## Why Tournament 209 Had "in_progress"

The trigger was automatically calculating status based on match result statuses. When matches exist but have `NULL` for `match_result_status`, the old trigger logic set tournament to `"in_progress"`.

With the fix:
- ✅ If status is `"matches_saved"` and no results processing started → keeps `"matches_saved"`
- ✅ Only changes to `"in_progress"` when match results are actually being processed

## How to Apply the Fix

### Option 1: Local Development (Supabase CLI)

```bash
# Apply the migration
npx supabase migration up

# Or reset and apply all migrations
npx supabase db reset
```

### Option 2: Production (Supabase Dashboard)

1. Go to Supabase Dashboard → SQL Editor
2. Copy the contents of `supabase/migrations/20260111000000_add_matches_saved_status.sql`
3. Run the SQL
4. Verify: Check that tournament 291 now has status `"matches_saved"`

### Option 3: Automatic (Push to GitHub)

If you have automatic migrations enabled, just commit and push:
```bash
git add supabase/migrations/20260111000000_add_matches_saved_status.sql
git commit -m "feat: add matches_saved status to tournaments"
git push
```

## Verification

After applying the migration:

1. **Check existing tournament 291:**
   ```sql
   SELECT tournament_id, nakka_identifier, match_import_status
   FROM nakka.tournaments
   WHERE tournament_id = 291;
   ```
   Expected: `match_import_status = NULL` (because the UPDATE failed)

2. **Update it manually:**
   ```sql
   UPDATE nakka.tournaments
   SET match_import_status = 'matches_saved'
   WHERE tournament_id = 291;
   ```

3. **Test new tournament import:**
   - Search for a tournament on the website
   - Check logs: Should show "updating status to matches_saved"
   - No constraint violation error

4. **Check tournament 209:**
   ```sql
   SELECT tournament_id, nakka_identifier, match_import_status
   FROM nakka.tournaments
   WHERE tournament_id = 209;
   ```
   If it should be `"matches_saved"`, update it:
   ```sql
   UPDATE nakka.tournaments
   SET match_import_status = 'matches_saved'
   WHERE tournament_id = 209
   AND NOT EXISTS (
     SELECT 1 FROM nakka.tournament_matches
     WHERE tournament_id = 209
     AND match_result_status IS NOT NULL
   );
   ```

## Expected Behavior After Fix

### Scenario 1: New Tournament Import
```
1. Save tournament → status = NULL
2. Batch insert all matches → status = "matches_saved" ✅
3. User starts importing results → status = "in_progress"
4. All results imported → status = "completed"
```

### Scenario 2: Re-import Same Tournament
```
1. Tournament exists with status = "matches_saved"
2. Code checks status
3. Skips match upsert (optimization) ✅
4. Returns matches from DB
```

### Scenario 3: Trigger Doesn't Override
```
1. Tournament has 109 matches, all with match_result_status = NULL
2. Trigger runs
3. Sees current_status = "matches_saved"
4. Sees no results processing started
5. Keeps status = "matches_saved" ✅ (doesn't change to in_progress)
```

## Files Modified

1. ✅ `supabase/migrations/20260111000000_add_matches_saved_status.sql` (NEW)
   - Adds `"matches_saved"` to CHECK constraint
   - Updates trigger to respect this status

## Summary

The solution is complete! The migration:
- ✅ Allows `"matches_saved"` in the database
- ✅ Prevents trigger from overriding this status
- ✅ Maintains backward compatibility
- ✅ No breaking changes to existing statuses

Apply the migration and the new batch insert flow will work perfectly! 🎯

