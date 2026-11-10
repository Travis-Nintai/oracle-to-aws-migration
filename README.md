# Oracle to AWS Migration

A migration fails slowly, in the planning, not on cutover day. This repo is about the work that happens before the move: assessing the source database honestly, choosing the AWS target that fits the workload instead of the one that sounds simplest, moving the data with DMS or Data Pump, and cutting over from a checklist instead of improvising under a maintenance window.

It covers the migration work a senior Oracle DBA owns end to end. The pre-migration assessment, the choice between EC2, RDS for Oracle, and RDS Custom for Oracle, the two main ways to move the data, and the cutover and rollback steps that decide whether the move ends in a working database or in a restore. The companion backup repo, oracle-rman-backup-recovery, covers the recovery side that the cutover checklist depends on: a migration is not finished until the first backup on the target has been taken and verified.

## Who it is for

Oracle DBAs who are about to move a database to AWS and want repeatable checks and runbooks instead of discovering a character set mismatch or a missing primary key during the cutover window. The material assumes you know your way around SQL*Plus, Data Pump, and AWS at the level of a DBA planning a move, not a cloud architect designing a landing zone.

## Layout

```
oracle-to-aws-migration/
├── sql/       -- SQL*Plus read-only checks (migration readiness)
├── datapump/  -- Data Pump parameter file templates (export, import)
├── dms/       -- DMS replication task settings template
└── docs/      -- architecture, workflows, target comparison, cutover checklist
```

## Assumptions

- Oracle 11g or later on the source. The readiness check reads `V$INSTANCE`, `V$DATABASE`, `DBA_DATA_FILES`, `DBA_OBJECTS`, `DBA_FEATURE_USAGE_STATISTICS`, and related catalog views. Some of those views need a privileged account.
- The target is AWS: EC2 with a self-managed Oracle install, RDS for Oracle, or RDS Custom for Oracle. The docs compare the three and say which tradeoffs each one makes.
- Database names, hosts, and paths in examples are fictional lab values. Point the scripts at your own environment.
- The examples assume a single-instance source database. A RAC source adds clusterware, SCAN, and shared storage steps that are not covered here.

## Safety notes

- The SQL scripts are read-only. The Data Pump and DMS templates are not: an export writes dump files, an import creates objects and loads data, and a DMS task writes to the target. Read every template before running it, replace the placeholders, and never test a migration against a database you care about until the workflow has been walked through on a lab copy.
- A migration is not a backup. Keep the source database and its backups until the target has run in production long enough to prove itself, and until the first verified backup on the target exists. The cutover checklist states this plainly.
- Never commit credentials, hostnames, or environment-specific connection details alongside these scripts. See `docs/script-conventions.md`.

## Testing

The SQL, Data Pump parameter files, and DMS task settings in this repo are syntax and logic reviewed against the documented data dictionary, Data Pump, and DMS references. They have not been executed against a live Oracle instance or a live AWS account in this environment, and the headers say so. Sample output in the docs is labeled illustrative lab output, not captured results.

## What this demonstrates

Migration ownership, not just tool familiarity: source assessment, target selection with licensing and operational tradeoffs stated honestly, data movement with DMS and Data Pump, and a cutover with validation and rollback, the work that decides whether a move ends in a working database or in an explanation.

## Background

Recreated from standard DBA practice for a personal lab portfolio, generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
