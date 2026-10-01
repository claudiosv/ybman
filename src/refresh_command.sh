session_init
clack_intro "ybman refresh"

yk_pick_many

valid_days="$(get_flag valid-days)"
if [[ -z "$(get_flag yes)" ]]; then
  ui_text "New certificate validity in days" "$valid_days" validate_positive_int
  valid_days="$REPLY"
fi

refreshed=()
for serial in "${YK_SELECTED[@]}"; do
  clack_log_step "YubiKey $serial"
  YK_DEVICE="$serial"
  yk_ask_pin

  dir="$(new_backup_dir "$serial")"
  run_step "Backing up current PIV state" write_snapshot "$serial" "$dir" before ||
    die "backup failed"
  chuid_save "$serial" "$dir/chuid.bin" || die "unable to export CHUID; refusing to continue"

  # --- preflight ---
  active=()
  plan=()
  for slot in "${SLOTS[@]}"; do
    if [[ ! -f "$dir/$slot-cert.pem" ]]; then
      plan+=("$slot  no certificate; skipped")
      continue
    fi
    run_step "Verifying slot $slot" refresh_preflight "$serial" "$slot" "$dir" ||
      die "slot $slot on YubiKey $serial cannot be refreshed"
    active+=("$slot")
    plan+=("$slot  $(<"$dir/$slot-subject.txt")  [$(<"$dir/$slot-hash.txt")]")
  done

  if ((${#active[@]} == 0)); then
    clack_log_warn "No certificates to refresh on YubiKey $serial"
    chuid_forget
    continue
  fi

  clack_note "Refresh plan ($serial, $valid_days days, keys unchanged)" "${plan[@]}"
  if [[ -z "$(get_flag yes)" ]]; then
    ui_confirm "Replace these certificates?" false || {
      clack_log_info "Skipped YubiKey $serial"
      chuid_forget
      continue
    }
  fi

  # --- refresh ---
  for slot in "${active[@]}"; do
    run_step "Refreshing slot $slot" refresh_slot "$serial" "$slot" "$dir" "$valid_days" ||
      die "refreshing slot $slot failed (backup: $dir)"
  done
  run_step "Restoring original CHUID" chuid_restore || die "CHUID restore failed (original: $dir/chuid.bin)"
  chuid_forget
  yk "$serial" piv info >"$dir/piv-info-after.txt"

  results=()
  for slot in "${active[@]}"; do
    results+=("$slot  $(sed -n 's/^notAfter=/valid until /p' "$dir/$slot-cert-new-info.txt")")
  done
  clack_note "Refreshed $serial" "${results[@]}"
  refreshed+=("$dir")
  YK_PIN=""
done

clack_outro "Done. ${#refreshed[@]} YubiKey(s) refreshed."
