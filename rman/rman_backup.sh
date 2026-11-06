#!/bin/bash
# 사용법: rman_backup.sh 0   (Level 0, 주 1회)
#         rman_backup.sh 1   (Level 1, 매일)
export ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
export ORACLE_SID=orcl
export PATH=$ORACLE_HOME/bin:$PATH
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
LEVEL=${1:-1}
LOG=/backup/logs/rman_L${LEVEL}_$(date +%Y%m%d_%H%M).log
rman target / log="$LOG" <<RMAN
BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL ${LEVEL} DATABASE PLUS ARCHIVELOG;
DELETE NOPROMPT OBSOLETE;
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
RMAN
if grep -qE "RMAN-[0-9]+|ORA-[0-9]+" "$LOG"; then echo "BACKUP FAILED: $LOG"; exit 1; fi
echo "BACKUP OK: $LOG"
find /backup/logs -name 'rman_*.log' -mtime +30 -delete
