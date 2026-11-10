# EC2 versus RDS for Oracle

The target decision is usually framed as a feature comparison. It is better framed as a question about who does the work: on EC2 you do it, on RDS AWS does it, and on RDS Custom the two of you split it. This doc compares the three on the points that change a DBA's week.

## The comparison

### Control and access

On EC2 you have the operating system. You SSH in, you read the alert log from the file system, you run your own agents, you install the patch you want on the day you want it. On RDS you have none of that: the database is reached through SQL only, the alert log comes through the console or an API, and the engine version is one AWS offers. RDS Custom restores OS access, which is its whole reason to exist, but the service still owns the instance lifecycle, so the access is for running your tools, not for replacing the platform.

If the workload needs something that lives on the OS, a monitoring agent, a backup agent, a script that calls out to the file system, RDS is the wrong target. That is usually the deciding factor, and it is decided in an afternoon of listing what the current database does outside SQL.

### Patching and upgrades

On EC2, patching is your calendar: download the patch, test it, apply it, roll back if it breaks something. On RDS, AWS applies engine patches on a schedule you approve, and major version upgrades run through the console with a pre-check. On RDS Custom, you patch the engine yourself, inside the window the service gives you, and the service patches the host.

The practical difference is not who clicks the button. It is that RDS patching is tested by AWS against the managed platform, and EC2 patching is tested by you against your build. If the team has a patch testing discipline, EC2 is fine. If patching has been the thing that slips, RDS removes the slip.

### Backup and recovery

On EC2, backups are yours: RMAN scripts, retention, testing restores, all of it. The companion repo oracle-rman-backup-recovery covers that work. On RDS, automated backups run daily with a retention you set, and point-in-time restore replays to a time you choose. On RDS Custom, automated backups work the same way, and you can also run RMAN yourself on the host.

RDS backups are simpler and they are also less flexible: you cannot take an RMAN backup of an RDS instance and restore it somewhere else, and you cannot restore an RMAN backup into RDS. That matters when the recovery plan involves moving a database out of RDS, or when a compliance requirement names RMAN specifically. Check the requirement before the first test migration, not during the audit after it.

### High availability

On EC2, high availability is Data Guard you build and operate: a standby, redo transport, a broker configuration, and a tested switchover. The companion repo oracle-dataguard-ha-dr covers that work. On RDS, high availability is Multi-AZ: a standby in another availability zone, synchronous replication, automatic failover. It is a standby, not a cluster, and failover is measured in a minute or two, not seconds.

A RAC source moving to RDS loses the cluster. If the workload depends on RAC for scale-out or for instance-level fault tolerance, that loss has to be planned for, either by accepting the Multi-AZ model or by choosing EC2 and rebuilding the cluster there.

### Performance and monitoring

The database performs the same on all three, given the same instance size and storage. What changes is what you can see. On EC2 you have everything: AWR, ASH, the alert log, OS metrics, your own scripts. On RDS, AWR and ASH are not available, because the Diagnostics Pack is not part of the managed service. Performance Insights and Enhanced Monitoring replace them, and they are good tools, but they are not AWR reports, and a team that troubleshoots from AWR will need to learn the new workflow before the first incident, not during it.

Storage performance is also worth naming. On EC2 you choose the EBS volume type and size, and you can provision IOPS. On RDS you choose the storage type and size in the console, and the service provisions it. The numbers are comparable; the difference is that on RDS you cannot put the redo logs on a separate volume from the data files, which is a layout choice some workloads depend on.

### Licensing

EC2 and RDS Custom are bring your own license. RDS for Oracle offers license included or bring your own. License included is the simpler choice for a database without an existing Oracle license position, and it is priced into the hourly rate. Bring your own license suits a database already covered by a license, and it is cheaper per hour when the license exists.

The counting changes with the target. On EC2, Oracle licensing counts vCPUs under the core factor table. On RDS, the license included rate already accounts for it. If the license position is the reason for the move, get the counting confirmed in writing before the migration, because it is the one decision that is expensive to revisit.

### Cost

EC2 looks cheaper on the hourly rate and costs more in DBA time: patching, backups, monitoring, and high availability are all work the team does. RDS looks more expensive per hour and costs less in DBA time. The honest comparison prices both, and it prices the risk of the work not getting done. A database that has not been patched in a year because nobody owned it is not cheap, whatever the instance costs.

RDS Custom sits between the two on price and on work. Use it when a named requirement needs the OS, not as a hedge against deciding.

## When to choose which

Choose EC2 when the database needs OS access, a feature RDS does not support, a specific patch level, or a cluster. Choose RDS when the workload fits the managed model and the team wants the operational work to shrink. Choose RDS Custom when the workload needs the OS but the team still wants managed backups and failover.

The choice is per database, not per estate. A portfolio of ten databases can reasonably hold all three targets, and usually does once the assessment is honest about what each database actually needs.

## What changes in the DBA's week

On EC2, nothing changes except the location. The same scripts, the same patch process, the same backup jobs, the same on-call pattern. The migration is a move, not a new job.

On RDS, the operating system work goes away and the database work stays. Patching, backups, and failover become service behavior to monitor rather than jobs to run. Performance work moves from AWR to Performance Insights. The DBA's week gets shorter on operations and longer on the things only a DBA can do: schema design, SQL tuning, and capacity planning.

On RDS Custom, the OS work stays and the backup and failover work shrinks. It is the smallest change of the three for a team that already runs its own builds, which is why it suits a first migration: the database moves, the habits mostly do not.

## Before deciding

Run the readiness check first, then answer these questions for the database in question:

1. Does anything outside SQL run on the database host today?
2. Does the workload use a feature or option the managed service does not offer?
3. Is the license position bring your own, or license included?
4. Does the recovery plan require RMAN backups that can leave the platform?
5. Does the team troubleshoot from AWR, and if so, who learns Performance Insights before cutover?
6. Is RAC doing work that Multi-AZ cannot replace?

If any answer is uncomfortable, that is the decision. The target that fits the answers is the right one, even when it is not the one the team hoped for.
