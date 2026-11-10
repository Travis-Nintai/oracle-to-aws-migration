# Migration architecture

A move to AWS is three decisions, made in order: which AWS target the database runs on, how the data gets there, and how the cutover happens. This doc covers the first two. The cutover itself lives in `cutover-checklist.md`.

## The target decision

There are three places an Oracle database can live on AWS, and they differ in who does the DBA work, not in the SQL the application runs.

### EC2 with a self-managed Oracle install

The database runs on an EC2 instance you build and own, usually on Amazon Linux or RHEL, with storage on EBS. You install Oracle, you patch it, you back it up, you set up Data Guard yourself. It is the closest thing to the on-premises database, which is both the advantage and the cost: everything you could do before still works, and everything you had to do before still needs doing.

Choose EC2 when the database needs something RDS does not offer: a feature or option the managed service does not support, OS-level access for scripts and agents, a specific patch level, or a configuration RDS does not allow. It is also the right target when the migration is a lift of an existing build, including its file layout and operating system habits.

### RDS for Oracle

The database runs as a managed service. AWS provisions the instance, patches the engine on a schedule you approve, takes automated backups, and handles Multi-AZ failover. You keep the database work: schemas, SQL, performance, users. You lose the operating system: no SSH, no SYSDBA, no file system, no installing your own agents.

Choose RDS when the database fits the managed model and the team wants the operational work to shrink. It is the right default for most single-instance workloads that do not need OS access. Check the current RDS documentation before committing: supported versions, editions, and options change, and a feature the source uses may not be available in the managed service.

### RDS Custom for Oracle

RDS Custom is the middle option. It looks like RDS, with automated backups and Multi-AZ, but it gives you OS access and lets you manage the engine patching yourself. It exists for databases that need the operating system but still want the managed backup and failover behavior.

Choose RDS Custom when the workload needs OS access, a custom patch level, or a third-party tool that has to run on the host, and the team still wants RDS to own backups and failover. It costs more operational attention than plain RDS, so use it for a named reason, not as a default.

### How the three compare

| Question | EC2 | RDS for Oracle | RDS Custom for Oracle |
|---|---|---|---|
| Who patches the engine | You | AWS, on your schedule | You |
| OS access | Full | None | Full |
| SYSDBA | Yes | No (master user instead) | Yes, limited by the service |
| Backups | Your RMAN or scripts | Automated, with point-in-time restore | Automated, with point-in-time restore |
| High availability | Data Guard you build | Multi-AZ standby | Multi-AZ standby |
| Licensing | Bring your own license | License included or bring your own | Bring your own license |
| Best for | Anything RDS cannot run | Standard single-instance workloads | Workloads that need the OS |

The full comparison, including what changes in daily DBA work on each target, is in `ec2-vs-rds.md`.

## The migration method decision

The method follows the downtime the business allows and the size of the database. There are four realistic options for Oracle to Oracle on AWS.

### Data Pump

Export from the source with `expdp`, import into the target with `impdp`, or import directly over a database link with `NETWORK_LINK` and no dump files at all. Data Pump is the simplest method and the easiest to reason about: the export is a point-in-time snapshot, the import is a load, and the cutover is the gap between the snapshot and the switch.

Use Data Pump when the downtime window can hold the full export and import, or when the database is small enough that the window is comfortable. It is also the right tool for schema-level moves, for refreshing a target from a source, and for the initial load in a combined approach.

Data Pump has two limits that matter. It does not capture changes made after the export starts, so the application must stop writing while the export runs, or the changes must be caught up another way. And a full export of a large database takes as long as it takes, which is why the method suits small and medium databases and planned windows.

### AWS Database Migration Service (DMS)

DMS runs a replication task between a source endpoint and a target endpoint. A full load copies the existing data, then change data capture (CDC) replays the changes from the redo stream until the target catches up. The application keeps running on the source while the load happens, and the cutover is the short pause while the last changes replicate and the application points at the target.

Use DMS when the downtime window cannot hold a full export and import. It is the standard choice for large databases and for moves where the application has to stay up until the last moment.

DMS needs two things from the source: ARCHIVELOG mode and supplemental logging, so it can read the redo stream. CDC reads through LogMiner by default, or through the Binary Reader for lower overhead on busy sources. DMS also needs a primary key on every table it replicates changes for, which is why the readiness script flags tables without one. Tables without a key can still move in the full load, but updates and deletes to them do not replicate.

### RMAN restore to EC2

Take an RMAN backup of the source and restore it on an EC2 target. This works only for the EC2 target, because RDS does not accept an RMAN restore of an Oracle database. It is fast for large databases, because RMAN copies blocks rather than rows, and it preserves the database exactly, including the character set and internal structures.

Use RMAN restore when the target is EC2, the database is large, and the downtime window can hold a restore plus a recover to the cutover point. It needs the same platform endianness and a compatible version on both sides.

### Transportable tablespaces

Export only the metadata with Data Pump, copy the data files, and plug the tablespaces into the target. This is the fastest way to move a large amount of data, because the data files are copied, not reloaded. It needs the same endianness on both sides, a compatible character set, and a self-contained set of tablespaces.

Use transportable tablespaces when the database is large, the platform matches, and the tablespace set is self-contained. A full transportable export moves the whole database this way. It is a specialist method: fast when it applies, inapplicable when it does not.

### Combining methods

The most common production pattern is a combination: Data Pump or RMAN for the initial load, DMS change data capture for the changes after it. The initial load is fast and complete, and CDC closes the gap. If you combine methods, plan the handover point explicitly: the CDC start position must be the point the initial load ended, or rows will be missed or duplicated.

## What the readiness script tells you

Run `sql/migration_readiness.sql` on the source before choosing a method. Each section answers a question the method decision depends on.

- Version and edition: whether the target supports the source version, and whether the edition matches.
- Character set: whether the target can use the same character set, or the data needs conversion.
- Size: whether a full export and import fits the downtime window.
- Object inventory: how much there is to move, and whether anything unusual is in the list.
- Features in use: options that need the same edition or license on the target.
- Invalid objects: things that will fail at import time if not fixed first.
- Tables without primary keys: tables DMS cannot replicate changes for.
- LOB and LONG columns: data types that need DMS settings or conversion.
- Partitioning: an Enterprise Edition option that needs the same edition on the target.
- TDE: encrypted tablespaces that move only with their master key.
- ARCHIVELOG mode and supplemental logging: whether DMS with CDC is possible at all.

A clean verdict means the database can be assessed, not that the migration will succeed. The verdict is the start of the plan, not the plan itself.

## Licensing notes

Licensing is part of the architecture decision, not an afterthought, and it changes with the target.

- RDS for Oracle offers license included or bring your own license. License included is simpler and suits databases without an existing Oracle license position. Bring your own license suits databases already covered by one. The choice is made per instance and is hard to change later, so decide it before the first test migration.
- EC2 and RDS Custom are bring your own license. The license position from the source carries over, but the counting changes: on EC2 you count vCPUs, and the Oracle core factor table applies.
- The Diagnostics Pack and Tuning Pack, which provide AWR and ASH, are not available on RDS for Oracle. Performance work there uses Performance Insights and Enhanced Monitoring instead. If the team relies on AWR reports, plan the replacement before the move, not after.
- Transparent Data Encryption on RDS uses a key managed by the service. On EC2 and RDS Custom you manage the wallet yourself. Either way, the master key must be available on the target before encrypted data can be read.
- Partitioning, Advanced Compression, and other Enterprise Edition options need the same edition on the target. The feature list from the readiness script is the checklist for this.

## What does not move unchanged

Some things in an on-premises Oracle database have no equivalent on the managed targets, and the plan has to name them.

- Oracle RAC has no RDS equivalent. High availability on RDS is Multi-AZ, which is a standby, not a cluster. A RAC source moving to RDS becomes a single instance with a standby.
- ASM has no RDS equivalent. Storage on RDS is managed by the service.
- Operating system scripts, agents, and cron jobs do not move to RDS. Anything the database does through the OS, including `DBMS_SCHEDULER` jobs that call external executables, needs a new home.
- External tables and `UTL_FILE` directories that point at local files need rework. On RDS, the replacement is usually S3 integration.
- Database links to systems that are not reachable from the VPC need network work first. A migration plan that assumes connectivity will discover the gap during the first test load.

## Illustrative readiness output

The output below is illustrative lab output, not captured results. It shows the shape of a clean report on a small fictional lab database.

```
=== 1. Instance and version ===
INSTANCE         VERSION            HOST
---------------- ------------------ ------------------------
ORCLLAB          19.0.0.0.0         db.example.local

=== 3. Database size ===
  TOTAL GB DATAFILES
---------- ----------
     42.50         6

=== 11. ARCHIVELOG mode and supplemental logging ===
DATABASE         LOG MODE     FORCE LOG  FLASHBACK  MIN LOG  PK LOG   UI LOG
---------------- ------------ ---------- ---------- -------- -------- --------
ORCLLAB          ARCHIVELOG   YES        NO         YES      YES      YES

=== Verdict ===
Done. Exit code: 0 (0 = ready to plan the move, 2 = a blocker found)
```

A clean report on a real database will be longer, with object counts and feature lists. The verdict is what matters first; the sections are what the plan is built from.
