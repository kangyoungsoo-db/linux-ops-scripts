#!/bin/bash
# 사용법: setup_disk.sh <이름> <GB>   예) setup_disk.sh oradata 60
# 같은 크기의 빈 디스크를 정확히 1개 찾아 vg_<이름>/lv_<이름> → xfs → /<이름> 에 마운트.
# 이미 되어 있으면 아무것도 바꾸지 않습니다.
set -euo pipefail
NAME="$1"; GB="$2"; MNT="/$NAME"; VG="vg_$NAME"; LV="lv_$NAME"
BYTES=$(( GB * 1024 * 1024 * 1024 ))

if mountpoint -q "$MNT"; then echo "$MNT 이미 마운트됨"; exit 0; fi

if ! vgs "$VG" >/dev/null 2>&1; then
  mapfile -t DEVS < <(lsblk -b -dn -o NAME,SIZE,TYPE | awk -v s="$BYTES" '$2==s && $3=="disk"{print "/dev/"$1}')
  if [ "${#DEVS[@]}" -ne 1 ]; then
    echo "${GB}GB 디스크를 정확히 1개 찾지 못했습니다 (찾은 것: ${DEVS[*]:-없음}). Vagrantfile의 DISKS 크기를 확인하세요." >&2
    lsblk >&2; exit 1
  fi
  DEV="${DEVS[0]}"
  if blkid "$DEV" >/dev/null 2>&1; then echo "$DEV 에 이미 다른 데이터가 있습니다. 중단합니다." >&2; exit 1; fi
  pvcreate -q "$DEV"; vgcreate -q "$VG" "$DEV"
fi
lvs "$VG/$LV" >/dev/null 2>&1 || lvcreate -q -y -l 100%FREE -n "$LV" "$VG"   # 100%FREE: 크기 반올림 문제 방지
blkid "/dev/$VG/$LV" >/dev/null 2>&1 || mkfs.xfs -q "/dev/$VG/$LV"
mkdir -p "$MNT"
grep -q "[[:space:]]${MNT}[[:space:]]" /etc/fstab || echo "/dev/mapper/$VG-$LV  $MNT  xfs  defaults  0 0" >> /etc/fstab
mount "$MNT"
# 새 파일 시스템은 SELinux 라벨이 없음(unlabeled_t) → 정책 기본 라벨로 (2026-10-28 실측: systemd가 dbstart 실행 거부)
if command -v selinuxenabled >/dev/null && selinuxenabled; then restorecon -R "$MNT"; fi
echo "CHANGED: $MNT ← /dev/$VG/$LV"
