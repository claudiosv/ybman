# Snapshot of PIV state. Shared by backup, provision and refresh.

# new_backup_dir SERIAL -> prints <root>/<serial>-<timestamp>
new_backup_dir() {
  local dir
  dir="$(backup_root)/$1-$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# write_snapshot SERIAL DIR LABEL
# Writes device-info.txt, piv-info-LABEL.txt and per-slot cert / pubkey / key-info.
# Slots without a cert/key are skipped silently. Never changes the device.
write_snapshot() {
  local serial=$1 dir=$2 label=${3:-before} slot
  yk "$serial" info >"$dir/device-info.txt"
  yk "$serial" piv info >"$dir/piv-info-$label.txt"
  for slot in "${SLOTS[@]}"; do
    yk "$serial" piv certificates export "$slot" "$dir/$slot-cert.pem" 2>/dev/null ||
      rm -f "$dir/$slot-cert.pem"
    yk "$serial" piv keys export "$slot" "$dir/$slot-pubkey.pem" 2>/dev/null ||
      rm -f "$dir/$slot-pubkey.pem"
    yk "$serial" piv keys info "$slot" >"$dir/$slot-key-info.txt" 2>/dev/null ||
      rm -f "$dir/$slot-key-info.txt"
  done
}
