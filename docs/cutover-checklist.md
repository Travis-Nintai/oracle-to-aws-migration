# Cutover checklist

A cutover is a sequence, not a moment. This checklist is ordered: each section depends on the one before it, and the rollback decision points are marked where they belong, before the step that makes rollback hard.

## Weeks before cutover

- [ ] Run `sql/migration_readiness.sql` on the source and clear the blockers. Record the verdict and the findings that shaped the method choice.
- [ ] Choose the target and the migration method, and write down why. See `migration-architecture.md` and `ec2-vs-rds.md`.
- [ ] Run a full test migration to a disposable target. Time every phase: export or full load, import or CDC catch-up, validation. The test migration is where the window estimate comes from, not a guess.
- [ ] Validate the test target: row counts, aggregates on the largest tables, index and constraint status, trigger status, sequence values. Fix what the test found and run the test again if the fix changed the method.
- [ ] Confirm the network path: the application tier can reach the target, the target can reach the source for CDC or network link, and the ports are open. A migration plan that assumes connectivity discovers the gap during the first test load.
- [ ] Confirm the license position for the target, in writing where the counting changed.
- [ ] Write the rollback plan and the point of no return. Rollback before the application switches is a config change. Rollback after writes land on the target is a second migration.
- [ ] Tell the application owners the window, the expected downtime, and what they need to do. A cutover nobody else knows about is a surprise, not a plan.

## Days before cutover

- [ ] Run a fresh test migration if anything changed on the source since the last one: new objects, new data volumes, a patch.
- [ ] Freeze schema changes on the source. Nothing new is created after this point without the migration plan knowing about it.
- [ ] Confirm the cutover team and the communication channel. Everyone who can stop the cutover is in the channel before it starts.
- [ ] Prepare the connection string change: where it lives, who applies it, and how it is verified. A cutover that depends on finding the config file during the window is already late.
- [ ] Stage the DMS task or the Data Pump files. The task is created and tested, or the dump files are transferred and their checksums verified. Nothing large moves during the window.
- [ ] Take a fresh backup of the source and verify it. The source is the rollback target, and a rollback needs a source that can be restored.
- [ ] Confirm the first backup on the target is scheduled and will run after cutover. A migrated database with no backup is a database with no recovery.

## During the cutover window

1. Stop the application writes to the source. Confirm they have stopped: check for active sessions and recent changes, not just the application log. Writes that continue during the load are the most common cutover failure.
2. Wait for DMS CDC to catch up, or finish the Data Pump export. Record the final change position. The cutover starts from a known point, not from a feeling that the load is done.
3. Run the final load or the final CDC catch-up. For DMS, confirm the lag is zero and staying zero. For Data Pump, confirm the import log shows no errors.
4. Validate the target before the application moves:
   - Row counts match on every table that moved.
   - An aggregate, such as a sum or a checksum, matches on the largest tables, not just the count.
   - Indexes, constraints, and triggers exist on the target and are valid.
   - Sequences are set past the highest value in use on the source.
   - Invalid objects on the target are zero.
5. Point the application at the target and run the smoke tests: log in, read, write, and run the most important transaction end to end. The smoke test is the cutover decision, not a formality after it.
6. Watch the first hour of production traffic on the target: active sessions, wait events, error logs. A migration that looks right at cutover and degrades under load is a migration that was not tested under load.

### Rollback decision points

- Before step 5, rollback is a config change: point the application back at the source. The source is untouched and the target can be discarded or kept for another attempt.
- After step 5, writes land on the target. Rolling back means moving those writes back to the source, which is a second migration, not a config change. Decide the point of no return before the window starts, and do not cross it on a feeling.
- If validation in step 4 fails and cannot be fixed inside the window, roll back. A cutover that proceeds on a failed validation is a cutover that will be rolled back later, under worse conditions.

## After cutover

- [ ] Take the first backup on the target and verify it restores. The migration is not finished until this exists. See the companion repo oracle-rman-backup-recovery for the validation workflow.
- [ ] Turn on the monitoring that belongs on the target: the checks from oracle-dba-toolkit for an EC2 target, Performance Insights and CloudWatch alarms for an RDS target.
- [ ] Confirm scheduled jobs, backups, and maintenance windows are running on the target, not still pointed at the source.
- [ ] Keep the source running, read-only if possible, until the retention period agreed in the plan expires. Then decommission it deliberately, with a record of what was kept and what was dropped.
- [ ] Write the migration record: what moved, how long each phase took, what went wrong, and what the next migration should do differently. The test migration estimate and the real timings side by side are the most useful part.

## Validation queries

Run these against the source and the target and compare the results. Replace `<SCHEMA_NAME>` with the schema being moved. The queries are read-only.

Count rows per table:

```sql
SELECT owner, table_name, num_rows
  FROM dba_tables
 WHERE owner = '<SCHEMA_NAME>'
 ORDER BY table_name;
```

Note that `NUM_ROWS` comes from the last statistics gathering, not a live count. For a live count on the tables that matter, count them directly:

```sql
SELECT COUNT(*) FROM <SCHEMA_NAME>.<TABLE_NAME>;
```

Compare an aggregate on the largest tables, which catches data differences a row count cannot:

```sql
SELECT COUNT(*), SUM(<NUMERIC_COLUMN>)
  FROM <SCHEMA_NAME>.<TABLE_NAME>;
```

Check for invalid objects on the target:

```sql
SELECT owner, object_type, COUNT(*)
  FROM dba_objects
 WHERE status = 'INVALID'
   AND owner = '<SCHEMA_NAME>'
 GROUP BY owner, object_type;
```

Check that sequences on the target sit past the highest value in use. For each sequence, compare `LAST_NUMBER` on the target with the maximum key value in the table it feeds.
