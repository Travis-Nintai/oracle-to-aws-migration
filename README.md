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

## Scripts and templates

| File | What it does |
|---|---|
| `sql/migration_readiness.sql` | Read-only pre-migration assessment: version, character set, size, object inventory, features in use, invalid objects, tables without primary keys, LOB and LONG columns, partitioning, TDE, ARCHIVELOG mode and supplemental logging; exit 2 when a blocker is found |
| `datapump/export_full.par` | Template for a full database export with parallel workers and compression |
| `datapump/import_full.par` | Template for a full database import with schema and tablespace remapping |
| `dms/task-settings.json` | DMS replication task settings template: full load, LOB handling, logging, CDC tuning, and row-level validation |

Run the readiness check first (connect as a privileged user, e.g. `/ as sysdba`):

```
sqlplus / as sysdba @sql/migration_readiness.sql
```

Thresholds live in the `DEFINE` lines at the top of the script. A clean report means the database can be assessed, not that the migration will succeed. Read sections 7 and 8 before choosing the migration method.

Take a full export with the template (replace the placeholders first, and read the header before running it):

```
expdp <USER>@<SERVICE_NAME> PARFILE=datapump/export_full.par
```

Load it into the target:

```
impdp <USER>@<SERVICE_NAME> PARFILE=datapump/import_full.par
```

## Docs

| Doc | What it covers |
|---|---|
| `docs/migration-architecture.md` | Target options, migration methods, what the readiness check tells you, licensing notes, and what does not move unchanged |
| `docs/dms-datapump-workflow.md` | DMS and Data Pump workflows step by step, with settings and pitfalls |
| `docs/ec2-vs-rds.md` | EC2 versus RDS versus RDS Custom: control, patching, backup, high availability, performance, licensing, and cost |
| `docs/cutover-checklist.md` | The cutover sequence: weeks before, days before, the window itself, rollback decision points, and validation queries |

Start with `docs/migration-architecture.md` if the target has not been chosen yet. Start with `docs/cutover-checklist.md` if the move is already planned.

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
