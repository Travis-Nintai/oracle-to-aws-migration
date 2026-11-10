-- ============================================================================
-- migration_readiness.sql
--
-- Purpose:
--   Answers the first question of any Oracle to AWS migration: what are
--   we actually moving? Reports the version and edition, character set,
--   database size, object inventory, features in use, and the conditions
--   that most often break a migration: invalid objects, tables without
--   primary keys (DMS change data capture cannot replicate updates or
--   deletes for those), LOB and LONG columns, partitioning, Transparent
--   Data Encryption, and whether the database is in ARCHIVELOG mode
--   with supplemental logging for DMS.
--
-- Usage:
--   sqlplus / as sysdba @migration_readiness.sql
--
--   To change the thresholds, edit the DEFINE lines below. The invalid
--   object threshold default is 0. Tables without primary keys and LOB
--   or LONG columns are reported as findings, not failures, because
--   they are common and usually handled by the migration method rather
--   than fixed first.
--
-- Exit code:
--   0 - ARCHIVELOG mode is on, invalid objects are within threshold,
--       and an open TDE wallet covers any encrypted tablespaces
--   2 - any of those checks fails
--
-- Notes:
--   Read-only. Object inventory excludes Oracle-maintained schemas, so
--   the counts reflect application objects. The feature list comes from
--   DBA_FEATURE_USAGE_STATISTICS; some rows are populated from AWR
--   data, which requires the Diagnostics Pack license, so treat the
--   list as an indicator of what to check, not an audit. The script
--   runs against one database: for a container database, connect to
--   each PDB in turn and run it there, because object inventory is
--   per container. See docs/migration-architecture.md for how to read
--   each section.
--   Reviewed; not executed against a live Oracle instance.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Thresholds. Edit to match local migration requirements.
-- ----------------------------------------------------------------------------
DEFINE max_invalid_objects = 0

PROMPT
PROMPT === 1. Instance and version ===
COLUMN instance_name  FORMAT A16 HEADING 'INSTANCE'
COLUMN db_version     FORMAT A18 HEADING 'VERSION'
COLUMN host_name      FORMAT A24 HEADING 'HOST'
COLUMN startup_time   FORMAT A20 HEADING 'STARTED'
COLUMN instance_status FORMAT A10 HEADING 'STATUS'

SELECT instance_name,
       version         AS db_version,
       host_name,
       startup_time,
       status          AS instance_status
  FROM v$instance;

PROMPT
PROMPT === 2. Character set and national language settings ===
PROMPT (Character set mismatches are a common migration failure. The
PROMPT  target must use the same database character set, or the data
PROMPT  must be converted, which Data Pump does not do silently.)
COLUMN nls_parameter FORMAT A28 HEADING 'PARAMETER'
COLUMN nls_value     FORMAT A40 HEADING 'VALUE'

SELECT parameter AS nls_parameter,
       value     AS nls_value
  FROM nls_database_parameters
 WHERE parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET',
                     'NLS_LANGUAGE', 'NLS_TERRITORY',
                     'NLS_SORT', 'NLS_LENGTH_SEMANTICS')
 ORDER BY parameter;

PROMPT
PROMPT === 3. Database size ===
COLUMN total_gb   FORMAT 999,990.00 HEADING 'TOTAL GB'
COLUMN datafiles  FORMAT 99990 HEADING 'DATAFILES'

SELECT ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS total_gb,
       COUNT(*)                                  AS datafiles
  FROM dba_data_files;

PROMPT (Largest tablespaces first.)
COLUMN tablespace_name FORMAT A30 HEADING 'TABLESPACE'
COLUMN tablespace_mb   FORMAT 999,999,990 HEADING 'MB'

SELECT tablespace_name,
       ROUND(SUM(bytes) / 1024 / 1024) AS tablespace_mb
  FROM dba_data_files
 GROUP BY tablespace_name
 ORDER BY 2 DESC;

PROMPT
PROMPT === 4. Object inventory by type ===
PROMPT (Application schemas only; Oracle-maintained schemas excluded.
PROMPT  Top 25 owner and type combinations by count.)
COLUMN obj_owner FORMAT A24 HEADING 'OWNER'
COLUMN obj_type  FORMAT A24 HEADING 'OBJECT TYPE'
COLUMN obj_count FORMAT 999,990 HEADING 'COUNT'

SELECT *
  FROM (SELECT owner       AS obj_owner,
               object_type AS obj_type,
               COUNT(*)    AS obj_count
          FROM dba_objects
         WHERE owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP',
                             'APPQOSSYS', 'AUDSYS', 'CTXSYS', 'DVSYS',
                             'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS',
                             'ORDSYS', 'WMSYS', 'XDB', 'GSMADMIN_INTERNAL',
                             'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC',
                             'AUDIT_ADMIN', 'DBSFWUSER', 'GGSYS',
                             'REMOTE_SCHEDULER_AGENT', 'XS$NULL')
         GROUP BY owner, object_type
         ORDER BY COUNT(*) DESC)
 WHERE ROWNUM <= 25;

PROMPT
PROMPT === 5. Features and options in use ===
PROMPT (Rows marked in use. Check each one against the target: some
PROMPT  options need Enterprise Edition, a separate license, or an
PROMPT  RDS feature check before the move.)
COLUMN feature_name    FORMAT A48 HEADING 'FEATURE'
COLUMN currently_used  FORMAT A6  HEADING 'IN USE'
COLUMN detected_usages FORMAT 999,990 HEADING 'TIMES SEEN'
COLUMN last_used       FORMAT A12 HEADING 'LAST USED'

SELECT *
  FROM (SELECT name           AS feature_name,
               currently_used,
               detected_usages,
               TO_CHAR(last_usage_date, 'YYYY-MM-DD') AS last_used
          FROM dba_feature_usage_statistics
         WHERE currently_used = 'TRUE'
         ORDER BY last_usage_date DESC NULLS LAST)
 WHERE ROWNUM <= 15;

PROMPT
PROMPT === 6. Invalid objects ===
PROMPT (Invalid objects fail at import time or, worse, at first use on
PROMPT  the target. Recompile and fix them before the migration, not
PROMPT  during the cutover window.)
COLUMN inv_owner FORMAT A24 HEADING 'OWNER'
COLUMN inv_type  FORMAT A24 HEADING 'OBJECT TYPE'
COLUMN inv_count FORMAT 999,990 HEADING 'COUNT'

SELECT owner       AS inv_owner,
       object_type AS inv_type,
       COUNT(*)    AS inv_count
  FROM dba_objects
 WHERE status = 'INVALID'
   AND owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP',
                     'APPQOSSYS', 'AUDSYS', 'CTXSYS', 'DVSYS',
                     'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS',
                     'ORDSYS', 'WMSYS', 'XDB', 'GSMADMIN_INTERNAL',
                     'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC',
                     'AUDIT_ADMIN', 'DBSFWUSER', 'GGSYS',
                     'REMOTE_SCHEDULER_AGENT', 'XS$NULL')
 GROUP BY owner, object_type
 ORDER BY 3 DESC;

PROMPT
PROMPT === 7. Tables without a primary key ===
PROMPT (DMS change data capture cannot replicate UPDATE or DELETE for
PROMPT  a table with no primary key; it can only insert. Either add a
PROMPT  key, exclude the table from CDC, or plan a Data Pump reload for
PROMPT  it. First 50 shown.)
COLUMN nopk_owner FORMAT A24 HEADING 'OWNER'
COLUMN nopk_table FORMAT A34 HEADING 'TABLE'

SELECT *
  FROM (SELECT owner      AS nopk_owner,
               table_name AS nopk_table
          FROM dba_tables t
         WHERE NOT EXISTS (SELECT 1
                             FROM dba_constraints c
                            WHERE c.owner = t.owner
                              AND c.table_name = t.table_name
                              AND c.constraint_type = 'P')
           AND owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP',
                             'APPQOSSYS', 'AUDSYS', 'CTXSYS', 'DVSYS',
                             'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS',
                             'ORDSYS', 'WMSYS', 'XDB', 'GSMADMIN_INTERNAL',
                             'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC',
                             'AUDIT_ADMIN', 'DBSFWUSER', 'GGSYS',
                             'REMOTE_SCHEDULER_AGENT', 'XS$NULL')
         ORDER BY owner, table_name)
 WHERE ROWNUM <= 50;

PROMPT
PROMPT === 8. LOB and LONG columns ===
PROMPT (LOB handling is a DMS setting, not a default: limited LOB mode
PROMPT  truncates past the configured size, full LOB mode moves the
PROMPT  whole value but is slower. LONG columns need conversion before
PROMPT  DMS will move them. First 50 shown.)
COLUMN lob_owner  FORMAT A24 HEADING 'OWNER'
COLUMN lob_table  FORMAT A30 HEADING 'TABLE'
COLUMN lob_column FORMAT A30 HEADING 'COLUMN'
COLUMN lob_type   FORMAT A10 HEADING 'TYPE'

SELECT *
  FROM (SELECT owner       AS lob_owner,
               table_name AS lob_table,
               column_name AS lob_column,
               data_type  AS lob_type
          FROM dba_tab_columns
         WHERE data_type IN ('BLOB', 'CLOB', 'NCLOB', 'BFILE',
                             'LONG', 'LONG RAW')
           AND owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP',
                             'APPQOSSYS', 'AUDSYS', 'CTXSYS', 'DVSYS',
                             'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS',
                             'ORDSYS', 'WMSYS', 'XDB', 'GSMADMIN_INTERNAL',
                             'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC',
                             'AUDIT_ADMIN', 'DBSFWUSER', 'GGSYS',
                             'REMOTE_SCHEDULER_AGENT', 'XS$NULL')
         ORDER BY owner, table_name, column_name)
 WHERE ROWNUM <= 50;

PROMPT
PROMPT === 9. Partitioning usage ===
PROMPT (Partitioning is an Enterprise Edition option on the source and
PROMPT  needs the same edition on the target. Counts here are tables;
PROMPT  partitioned indexes follow their tables.)
COLUMN part_owner FORMAT A24 HEADING 'OWNER'
COLUMN part_count FORMAT 999,990 HEADING 'PARTITIONED TABLES'

SELECT table_owner AS part_owner,
       COUNT(*)    AS part_count
  FROM dba_part_tables
 GROUP BY table_owner
 ORDER BY 2 DESC;

PROMPT
PROMPT === 10. Transparent Data Encryption ===
PROMPT (Encrypted tablespaces move only with their master key. On RDS
PROMPT  the key is managed by the service, so plan the key handover
PROMPT  before cutover, not during it.)
COLUMN wallet_type   FORMAT A20 HEADING 'WALLET TYPE'
COLUMN wallet_status FORMAT A16 HEADING 'STATUS'

SELECT wallet_type,
       status AS wallet_status
  FROM v$encryption_wallet;

PROMPT (Encrypted tablespaces; empty means none.)
COLUMN enc_tablespace FORMAT A30 HEADING 'TABLESPACE'
COLUMN enc_status     FORMAT A10 HEADING 'ENCRYPTED'

SELECT tablespace_name AS enc_tablespace,
       encrypted       AS enc_status
  FROM dba_tablespaces
 WHERE encrypted = 'YES'
 ORDER BY tablespace_name;

PROMPT
PROMPT === 11. ARCHIVELOG mode and supplemental logging ===
PROMPT (DMS change data capture reads the redo stream, so it needs
PROMPT  ARCHIVELOG mode and supplemental logging on. A database in
PROMPT  NOARCHIVELOG mode can still move by Data Pump, but not by DMS
PROMPT  with CDC.)
COLUMN db_name       FORMAT A16 HEADING 'DATABASE'
COLUMN log_mode      FORMAT A12 HEADING 'LOG MODE'
COLUMN force_logging FORMAT A10 HEADING 'FORCE LOG'
COLUMN flashback_on  FORMAT A10 HEADING 'FLASHBACK'
COLUMN log_data_min  FORMAT A8  HEADING 'MIN LOG'
COLUMN log_data_pk   FORMAT A8  HEADING 'PK LOG'
COLUMN log_data_ui   FORMAT A8  HEADING 'UI LOG'

SELECT name                       AS db_name,
       log_mode,
       force_logging,
       flashback_on,
       supplemental_log_data_min  AS log_data_min,
       supplemental_log_data_pk   AS log_data_pk,
       supplemental_log_data_ui   AS log_data_ui
  FROM v$database;

PROMPT
PROMPT === Verdict ===

COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE
         WHEN (SELECT log_mode FROM v$database) <> 'ARCHIVELOG' THEN 2
         WHEN (SELECT COUNT(*)
                 FROM dba_objects
                WHERE status = 'INVALID'
                  AND owner NOT IN ('SYS', 'SYSTEM', 'OUTLN', 'DBSNMP',
                                    'APPQOSSYS', 'AUDSYS', 'CTXSYS', 'DVSYS',
                                    'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS',
                                    'ORDSYS', 'WMSYS', 'XDB', 'GSMADMIN_INTERNAL',
                                    'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC',
                                    'AUDIT_ADMIN', 'DBSFWUSER', 'GGSYS',
                                    'REMOTE_SCHEDULER_AGENT', 'XS$NULL'))
              > &max_invalid_objects THEN 2
         WHEN EXISTS (SELECT 1
                        FROM dba_tablespaces
                       WHERE encrypted = 'YES')
              AND NOT EXISTS (SELECT 1
                                FROM v$encryption_wallet
                               WHERE status = 'OPEN') THEN 2
         ELSE 0
       END AS exit_code
  FROM dual;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = ready to plan the move, 2 = a blocker found)
PROMPT A clean report means the database can be assessed, not that the
PROMPT migration will succeed. Read sections 7 and 8 before choosing
PROMPT the migration method, and see docs/migration-architecture.md.
EXIT &v_exit_code
