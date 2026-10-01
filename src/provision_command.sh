session_init
clack_intro "ybman provision"

yk_pick_one
device="$YK_DEVICE"

yk "$device" piv info >/dev/null 2>&1 || die "PIV is not available on YubiKey $device"
ui_note "YubiKey $device" "$(yk "$device" info 2>/dev/null | sed -n '1,8p')"

# --- inspect slots ---------------------------------------------------------
slot_classify "$device"
lines=()
actions=0
for i in "${!SLOTS[@]}"; do
  lines+=("$(printf '%-3s %-20s %s' "${SLOTS[$i]}" "${SLOT_NAMES[$i]}" "${SLOT_STATE[$i]}")")
  case "${SLOT_STATE[$i]}" in
    certificate-only) die "slot ${SLOTS[$i]} has a certificate but no detectable private key" ;;
    complete) ;;
    *) actions=$((actions + 1)) ;;
  esac
done
clack_note "PIV slots" "${lines[@]}"

if ((actions == 0)); then
  clack_outro "All four primary PIV slots are already populated."
  exit 0
fi

# --- wizard ----------------------------------------------------------------
algorithm="$(get_flag algorithm)"
valid_days="$(get_flag valid-days)"
subjects=()
for i in "${!SLOTS[@]}"; do subjects[i]=""; done

if [[ -z "$(get_flag yes)" ]]; then
  clack_log_info "New private keys are generated on the YubiKey. Existing keys are never replaced."
  other=ECCP256
  [[ "$algorithm" == ECCP256 ]] && other=ECCP384
  ui_select "Algorithm for new keys" "$algorithm" "$other"
  algorithm="$REPLY"
  ui_text "Certificate validity in days" "$valid_days" validate_positive_int
  valid_days="$REPLY"
  for i in "${!SLOTS[@]}"; do
    [[ "${SLOT_STATE[$i]}" != complete ]] || continue
    ui_text "${SLOTS[$i]} ${SLOT_NAMES[$i]} subject" "${DEFAULT_SUBJECTS[$i]}" validate_nonempty
    subjects[i]="$REPLY"
  done
else
  for i in "${!SLOTS[@]}"; do subjects[i]="${DEFAULT_SUBJECTS[$i]}"; done
fi

# --- plan ------------------------------------------------------------------
plan=("Device:    $device" "Algorithm: $algorithm" "Validity:  $valid_days days (~$((valid_days / 365)) years)" "")
for i in "${!SLOTS[@]}"; do
  case "${SLOT_STATE[$i]}" in
    complete) plan+=("${SLOTS[$i]}  leave unchanged") ;;
    key-only) plan+=("${SLOTS[$i]}  keep key, create certificate  (${subjects[$i]})") ;;
    empty) plan+=("${SLOTS[$i]}  generate $algorithm key + certificate  (${subjects[$i]})") ;;
  esac
done
clack_note "Plan" "${plan[@]}"

if [[ -z "$(get_flag yes)" ]]; then
  ui_confirm "Configure this YubiKey?" false || {
    clack_cancel "Nothing changed."
    exit 0
  }
fi

yk_ask_pin

# --- backup ----------------------------------------------------------------
backup_dir="$(new_backup_dir "$device")"
run_step "Backing up current PIV state" write_snapshot "$device" "$backup_dir" before ||
  die "backup failed"
if chuid_save "$device" "$backup_dir/chuid.bin"; then
  clack_log_success "Saved CHUID"
else
  clack_log_warn "Unable to export CHUID; it will not be restored"
fi

# --- configure -------------------------------------------------------------
for i in "${!SLOTS[@]}"; do
  [[ "${SLOT_STATE[$i]}" != complete ]] || continue
  run_step "${SLOTS[$i]} ${SLOT_NAMES[$i]}: ${subjects[$i]}" \
    provision_slot "$device" "${SLOTS[$i]}" "${SLOT_STATE[$i]}" "${subjects[$i]}" "$algorithm" "$valid_days" ||
    die "provisioning slot ${SLOTS[$i]} failed (backup: $backup_dir)"
done

if [[ -n "$CHUID_FILE" ]]; then
  run_step "Restoring original CHUID" chuid_restore || die "CHUID restore failed (original: $backup_dir/chuid.bin)"
fi

yk "$device" piv info >"$backup_dir/piv-info-after.txt"
ui_note "Final PIV state" "$(<"$backup_dir/piv-info-after.txt")"
clack_outro "Done. Backup: $backup_dir"
