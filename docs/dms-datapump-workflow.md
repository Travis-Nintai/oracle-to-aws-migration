# DMS and Data Pump workflows

This doc walks through the two main ways to move the data, step by step, with the settings and pitfalls that decide whether each one works. The parameter file templates live in `datapump/` and the DMS task settings template in `dms/`. Read the template headers before running anything.

## DMS workflow

DMS moves data through a replication task that runs on a replication instance. The task has a source endpoint, a target endpoint, and settings that control how the load and the change capture behave.

### Before the task

1. Run `sql/migration_readiness.sql` on the source. Fix invalid objects. Decide what to do about tables without primary keys: add a key, exclude the table from CDC, or plan a Data Pump reload for it.
2. Put the source in ARCHIVELOG mode and turn on supplemental logging. DMS needs both to read changes from the redo stream. Minimum supplemental logging is the floor; add primary key logging so DMS can identify changed rows.
3. Create the DMS endpoints and test the connections. The source endpoint needs a user with `SELECT` on the schemas being moved and access to the redo stream; the target endpoint needs a user that can create tables and load data.
4. Size the replication instance for the load. A task that is too small does not fail, it just runs slowly, and a slow full load is how a migration misses its window.

### The task settings

The template in `dms/task-settings.json` is a starting point, not a finished configuration. The settings that most often need changing:

- `TargetTablePrepMode`: `TRUNCATE_BEFORE_LOAD` drops the target table contents before loading, which is what a fresh migration wants. `DO_NOTHING` is right when the target tables were pre-created with the exact definitions the load expects.
- `LobSettings`: limited LOB mode loads LOB columns up to a configured size and truncates past it. It is fast and it is the default for a reason, but it silently truncates. Full LOB mode loads the whole value and is slower. Choose full LOB mode when any LOB column holds data larger than the limited size, and check the readiness output for LOB columns first.
- `ValidationSettings`: table-level validation compares row counts and, for a sample of rows, values between source and target. Turn it on for the first migration of a database. It costs time and it is the cheapest way to catch a load that looked successful and was not.
- `ChangeProcessingTuning`: batch apply settings control how CDC applies changes on the target. The defaults suit a steady change rate; a source with bursts of changes needs tuning, and the symptom is apply lag that grows during the business day and never catches up.
- `Logging`: enable detailed logging for the first run of a task. Turn it down after the task is proven, not before.

### Full load, then CDC

A DMS task runs in two phases. The full load copies the existing tables, and CDC replays the changes that happened after the load started. The task keeps replaying until the target catches up, and the cutover happens when the lag is small and staying small.

Watch three things while the task runs:

- The full load progress per table. A table that stalls usually means a LOB column in limited mode, a missing index on the target, or a task that is too small.
- The CDC latency. If it grows during the day and shrinks at night, the task is undersized for the change rate. If it grows and never shrinks, something is stuck: check the task logs for errors on a specific table.
- The target row counts against the source. DMS reports them, and the validation settings check them. A table that loads with fewer rows than the source has a filter, a failed batch, or a data type the task could not move.

### DMS pitfalls

- Sequences do not replicate. DMS moves the tables, not the sequence values. After cutover, set each sequence on the target past the highest value in use, or the first insert after the move will fail on a duplicate key.
- Triggers are disabled on the target during the load and stay disabled until the task ends. If the application depends on a trigger, test it explicitly after the task finishes.
- Foreign key constraints are created after the data loads, by default. That is the right order for a load, and it means a load that fails halfway leaves constraints uncreated. Check them before cutover.
- Data type mappings are mostly automatic and occasionally wrong. `NUMBER` with no precision maps to a numeric type that can lose scale on some targets, and `TIMESTAMP WITH TIME ZONE` needs checking on the target. The schema conversion assessment, or a test load of the affected tables, is how these are found.
- A table without a primary key replicates inserts only. Updates and deletes to it are dropped by CDC. This is the single most common DMS surprise, and the readiness script flags it for a reason.
- LONG and LONG RAW columns do not move through DMS. Convert them to CLOB or BLOB on the source first, or move those tables with Data Pump.

## Data Pump workflow

Data Pump moves data through dump files, or directly over a database link. It is simpler than DMS and it needs a quiet source: nothing can change after the export starts, or the change is lost.

### Full export and import

The export template in `datapump/export_full.par` takes a full export with parallel workers and compression. Run it as a user with the `DATAPUMP_EXP_FULL_DATABASE` role.

```
expdp <USER>@<SERVICE_NAME> PARFILE=datapump/export_full.par
```

The import template in `datapump/import_full.par` loads the dump file set into the target, with schema and tablespace remapping. Run it as a user with the `DATAPUMP_IMP_FULL_DATABASE` role.

```
impdp <USER>@<SERVICE_NAME> PARFILE=datapump/import_full.par
```

Replace the placeholders in both files first: the directory object, the dump file names, and the schema and tablespace mappings. The directory object must exist on the database that runs the job, and on RDS the dump files arrive through S3 integration, not through a local file system.

### Network link import

When the dump files would be large, or the two databases can see each other, skip the files. Create a database link from the target to the source and import over it:

```
impdp <USER>@<SERVICE_NAME> NETWORK_LINK=<SOURCE_LINK> FULL=Y DIRECTORY=<DATA_PUMP_DIRECTORY> LOGFILE=network_import.log PARALLEL=4
```

The export never touches disk. The cost is the network: the whole database crosses the link, so this suits databases where the link is fast and the export would otherwise be the bottleneck. It also needs the `DATAPUMP_EXP_FULL_DATABASE` role on the source.

### Transportable tablespaces

When the database is large and the platforms match, move the data files instead of reloading the data. The steps:

1. Check the tablespace set is self-contained with `DBMS_TTS.TRANSPORT_SET_CHECK`.
2. Put the tablespaces in read-only mode.
3. Export the metadata with `TRANSPORT_TABLESPACES`.
4. Copy the data files to the target.
5. Import the metadata with `TRANSPORT_DATAFILES` pointing at the copied files.

The data files are copied, not reloaded, which is why this is the fastest method for a large database. It is also the most restrictive: same endianness, compatible character set, self-contained tablespaces, and read-only source tablespaces while the files copy.

### Data Pump pitfalls

- An export is a point-in-time snapshot. Changes after the export starts are not in the dump file set. The application must stop writing, or the changes must be caught up by DMS CDC after the import.
- A full export needs the `DATAPUMP_EXP_FULL_DATABASE` role. Without it, the export silently becomes a schema export of the exporting user's own objects, which is not the same thing and is discovered at import time.
- `VERSION` matters when the target is older than the source. An export taken at the source version cannot be imported into an older release. Set `VERSION` to the target release when the two differ.
- Import order matters for objects with dependencies. Data Pump handles most of it, but triggers and constraints are created after the data loads, and a failed import leaves them uncreated. Check the import log for errors, not just the exit code.
- Dump files and the directory object live on the database server, not the client. On RDS there is no server file system to write to, so the files arrive through S3. Plan the transfer before the export runs.

## Choosing between them

| Situation | Method |
|---|---|
| Small database, generous window | Data Pump full export and import |
| Large database, short window | DMS full load plus CDC |
| Large database, EC2 target, exact copy needed | RMAN restore |
| Large database, same platform, self-contained tablespaces | Transportable tablespaces |
| Large database, short window, and the initial load must be fast | Data Pump initial load, DMS CDC for the changes after it |

The combined approach is the most common production pattern. Its handover point is the one thing to get right: CDC must start from the point the initial load ended. Start CDC too early and rows duplicate; start it too late and changes are missed. Record the change position at the end of the initial load and set the DMS task to start from it.

## After the load, before the cutover

Whichever method moved the data, the same checks run before the application switches over. They are the cutover checklist in `cutover-checklist.md`, and the short version is:

1. Row counts match on every table that moved.
2. A checksum or aggregate matches on the largest tables, not just the count.
3. Indexes, constraints, triggers, and sequences exist on the target and are valid.
4. The application connects and its smoke tests pass against the target.
5. The first backup on the target has been taken and verified.

A load that passes its own log and fails any of these is not ready. The log says the tool finished; the checks say the data arrived.
