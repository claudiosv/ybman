session_init
clack_intro "ybman restore"

dir="${args[backup_dir]:-}"
if [[ -z "$dir" ]]; then
  options=()
  for d in "$(backup_root)"/*/; do
    [[ -d "$d" ]] || continue
    d="${d%/}"
    compgen -G "$d/*-cert.pem" >/dev/null || continue
    options=("$d|$(basename "$d")" "${options[@]}")
  done
  ((${#options[@]} > 0)) || die "no backups with certificates under $(backup_root)"
  ui_select "Restore certificates from which backup?" "${options[@]}"
  dir="$REPLY"
fi
[[ -d "$dir" ]] || die "backup directory not found: $dir"

serial="$(basename "$dir")"
serial="${serial%%-*}"
yk_list
yk_has_serial "$serial" || die "YubiKey $serial (from the backup name) is not connected"

# --- plan ------------------------------------------------------------------
slots=()
plan=("Device:  $serial" "Backup:  $dir" "")
for slot in "${SLOTS[@]}"; do
  if [[ -f "$dir/$slot-cert.pem" ]]; then
    slots+=("$slot")
    plan+=("$slot  restore  $(x509_name subject "$dir/$slot-cert.pem")")
  else
    plan+=("$slot  not in backup; unchanged")
  fi
done
((${#slots[@]} > 0)) || die "the backup has no certificates"
clack_note "Plan" "${plan[@]}"

if [[ -z "$(get_flag yes)" ]]; then
  ui_confirm "Replace these certificates?" false || {
    clack_cancel "Nothing changed."
    exit 0
  }
fi
YK_DEVICE="$serial"
yk_ask_pin

# --- snapshot, restore -----------------------------------------------------
snap="$(new_backup_dir "$serial")"
run_step "Backing up current PIV state" write_snapshot "$serial" "$snap" before || die "backup failed"
chuid_save "$serial" "$snap/chuid.bin" || clack_log_warn "Unable to export CHUID; it will not be restored"

for slot in "${slots[@]}"; do
  run_step "Restoring slot $slot" restore_slot "$serial" "$slot" "$dir" ||
    die "restoring slot $slot failed (current state saved in $snap)"
done
if [[ -n "$CHUID_FILE" ]]; then
  run_step "Restoring original CHUID" chuid_restore || die "CHUID restore failed (original: $snap/chuid.bin)"
fi
clack_outro "Done. Previous state saved in $snap"
