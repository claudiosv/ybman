session_init
clack_intro "ybman refresh"

yk_pick_many

valid_days="$(get_flag valid-days)"
within="$(get_flag expiring-within)"
dry_run="$(get_flag dry-run)"
if [[ -z "$(get_flag yes)" ]]; then
  ui_text "New certificate validity in days" "$valid_days" validate_positive_int
  valid_days="$REPLY"
fi

refreshed=()
for serial in "${YK_SELECTED[@]}"; do
  clack_log_step "YubiKey $serial"
  YK_DEVICE="$serial"

  if [[ -n "$dry_run" ]]; then
    dir="$(mktemp -d "$TMP_DIR/dry.XXXXXX")"
  else
    dir="$(new_backup_dir "$serial")"
  fi
  run_step "Backing up current PIV state" write_snapshot "$serial" "$dir" before ||
    die "backup failed"
  chuid_save "$serial" "$dir/chuid.bin" || die "unable to export CHUID; refusing to continue"

  # --- pick slots (no PIN needed yet) ---
  candidates=()
  plan=()
  for slot in "${SLOTS[@]}"; do
    if [[ ! -f "$dir/$slot-cert.pem" ]]; then
      plan+=("$slot  no certificate; skipped")
    elif [[ -n "$within" ]] && openssl x509 -checkend "$((within * 86400))" -noout -in "$dir/$slot-cert.pem" >/dev/null; then
      plan+=("$slot  not expiring within $within days; skipped")
    else
      candidates+=("$slot")
    fi
  done

  active=()
  if ((${#candidates[@]} > 0)); then
    yk_ask_pin
    # --- preflight ---
    for slot in "${candidates[@]}"; do
      run_step "Verifying slot $slot" refresh_preflight "$serial" "$slot" "$dir" ||
        die "slot $slot on YubiKey $serial cannot be refreshed"
      active+=("$slot")
      plan+=("$slot  $(<"$dir/$slot-subject.txt")  [$(<"$dir/$slot-hash.txt")]")
    done
  fi

  if ((${#active[@]} == 0)); then
    clack_log_warn "No certificates to refresh on YubiKey $serial"
    chuid_forget
    continue
  fi

  clack_note "Refresh plan ($serial, $valid_days days, keys unchanged)" "${plan[@]}"
  if [[ -n "$dry_run" ]]; then
    clack_log_info "Dry run: nothing was changed."
    chuid_forget
    YK_PIN=""
    continue
  fi
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
