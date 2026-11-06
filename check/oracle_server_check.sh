#!/bin/bash
# Oracle 19c 설치 점검 — 설치 직후와 재부팅 후에 같은 스크립트로 확인합니다.
# 🪟 PowerShell:  vagrant ssh -c "sudo bash /vagrant/scripts/check.sh"
# 🧑‍💻 VM 안:      sudo bash /vagrant/scripts/check.sh
# shellcheck disable=SC2016
ORA_SID=orcl
ORA_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng()   { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
ora()  { su - oracle -c "$1" 2>&1; }
sql()  { local f; f=$(mktemp /tmp/check_XXXX.sql); chmod 644 "$f"
         printf 'set heading off feedback off pagesize 0 linesize 200\n%s\nexit\n' "$1" > "$f"
         ora "sqlplus -s / as sysdba @$f" | sed '/^$/d' | sed 's/^ *//;s/ *$//'; rm -f "$f"; }

echo "== Oracle 19c 점검 $(date '+%F %T') · $(hostname) =="
echo "-- 환경"
echo "  OS     : $(cat /etc/oracle-release 2>/dev/null)"
echo "  커널   : $(uname -r)"
echo "  가동   : $(uptime -p)"

echo "-- 1. 디스크"
for m in /u01 /oradata /backup; do
  if mountpoint -q "$m"; then ok "$m 마운트 ($(df -h --output=size "$m" | tail -1 | tr -d ' '))"; else ng "$m 마운트 안 됨"; fi
done

echo "-- 2. OS 설정"
grep -q '\[never\]' /sys/kernel/mm/transparent_hugepage/enabled && ok "THP 꺼짐" || ng "THP 켜져 있음"
[ "$(sysctl -n vm.hugetlb_shm_group)" = "54321" ] && ok "vm.hugetlb_shm_group=54321" || ng "vm.hugetlb_shm_group 미설정"
grep -q "$(hostname -s)" /etc/hosts && ! grep -E "^127\." /etc/hosts | grep -qw "$(hostname -s)" \
  && ok "/etc/hosts 서비스 IP 매핑" || ng "/etc/hosts 에 호스트 이름이 127.x 로 잡혀 있음"

echo "-- 3. 소프트웨어"
SZ=$(stat -c %s "$ORA_HOME/bin/oracle" 2>/dev/null || echo 0)
[ "$SZ" -gt 100000000 ] && ok "bin/oracle $((SZ/1048576))MB" || ng "bin/oracle 크기 이상 ($SZ 바이트)"
echo "  패치   : $(ora "$ORA_HOME/OPatch/opatch lspatches" | grep -E '^[0-9]+;' | head -3 | tr '\n' ' ')"

echo "-- 4. 서비스 · 리스너"
systemctl is-enabled -q oracle-db && ok "oracle-db 서비스 자동 기동 등록" || ng "oracle-db 서비스 미등록"
systemctl is-active -q oracle-db && ok "oracle-db 서비스 실행 중" || ng "oracle-db 서비스 꺼짐"
LS=$(ora "lsnrctl status")
echo "$LS" | grep -q 'Service "pdb"' && ok "리스너에 pdb 서비스 등록" || ng "리스너에 pdb 서비스 없음 (ORA-12514 원인)"

echo "-- 5. 데이터베이스"
ST=$(sql "select status from v\$instance;")
[ "$ST" = "OPEN" ] && ok "인스턴스 $ORA_SID OPEN" || ng "인스턴스 상태: ${ST:-연결 실패}"
echo "  버전   : $(sql "select version_full from v\$instance;")"
PDB=$(sql "select name||' '||open_mode from v\$pdbs where name='PDB';")
[ "$PDB" = "PDB READ WRITE" ] && ok "PDB READ WRITE" || ng "PDB 상태: ${PDB:-없음} (ORA-01109 원인)"
LM=$(sql "select log_mode from v\$database;")
[ "$LM" = "ARCHIVELOG" ] && ok "ARCHIVELOG 모드 → /backup/arch" || ng "로그 모드: $LM"
MT=$(sql "select value from v\$parameter where name='memory_target';")
[ "$MT" = "0" ] && ok "memory_target=0 (ASMM)" || ng "memory_target=$MT (AMM이면 HugePages 불가)"
echo "  SGA    : $(sql "select round(value/1048576)||'MB' from v\$parameter where name='sga_target';")"

echo "-- 6. HugePages"
read -r HT HF < <(awk '/HugePages_Total/{t=$2} /HugePages_Free/{f=$2} END{print t, f}' /proc/meminfo)
LP=$(sql "select value from v\$parameter where name='use_large_pages';")
[ "$HT" -gt 0 ] && [ "$HF" -lt "$HT" ] && ok "HugePages 사용 중 (Total $HT / Free $HF, use_large_pages=$LP)" \
  || ng "HugePages 미사용 (Total $HT / Free $HF, use_large_pages=$LP)"

echo "-- 7. 외부 접속 준비"
ss -ltn | grep -q ':1521 ' && ok "1521 포트 대기 중" || ng "1521 포트 없음"
if systemctl is-active -q firewalld; then
  firewall-cmd -q --query-port=1521/tcp && ok "방화벽 1521 허용" || ng "방화벽 1521 막힘"
fi

echo "== 결과: PASS $PASS / FAIL $FAIL =="
[ "$FAIL" -eq 0 ]
