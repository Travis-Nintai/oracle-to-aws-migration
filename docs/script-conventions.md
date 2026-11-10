# Script conventions

Every script in this repo follows the same shape so it is predictable to run and safe to schedule:

- Header comment: purpose, usage, and exit codes for SQL scripts. Nothing else in the header.
- Thresholds as `DEFINE` variables at the top of SQL scripts, with defaults noted in the comment.
- No hard-coded hostnames, SIDs, service names, credentials, or paths. Examples use placeholders like `$ORACLE_SID`, `<SERVICE_NAME>`, `<DB_NAME>`, `<SOURCE_SCHEMA>`, and `<AWS_REGION>`.
- SQL scripts are read-only. Data Pump parameter files and DMS task settings are a different category: an export writes dump files, an import creates objects and loads data, and a DMS task writes to the target. Every template file says so in its header, and nothing here runs a load without a validation step first. Test migrations on a lab copy.
- Data Pump parameter files accept `#` comment lines. Data Pump treats everything after a `#` on a line as a comment, so short explanations can sit in the `.par` files themselves.
- Exit code 0 on success; non-zero on failure or threshold breach, documented per script.
- Output is plain text, readable in a terminal and greppable in logs.

New scripts should add a usage example to the README.
