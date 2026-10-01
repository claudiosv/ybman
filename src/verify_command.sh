session_init
clack_intro "ybman verify"

yk_pick_many

deep="$(get_flag deep)"
deep_n=0
[[ -z "$deep" ]] || deep_n=1
[[ -z "$deep" ]] || yk_ask_pin

failed=0
for serial in "${YK_SELECTED[@]}"; do
  lines=()
  for i in "${!SLOTS[@]}"; do
    if verdict="$(verify_slot "$serial" "${SLOTS[$i]}" "$deep_n" 2>&1)"; then mark="ok "; else
      mark="BAD"
      failed=1
    fi
    lines+=("$(printf '%s %-3s %-20s %s' "$mark" "${SLOTS[$i]}" "${SLOT_NAMES[$i]}" "$verdict")")
  done
  backup="$(latest_backup "$serial")"
  if [[ -z "$backup" ]]; then
    lines+=("" "no backup found under $(backup_root)")
  elif verify_backup_dir "$backup"; then
    lines+=("" "latest backup parses: $backup")
  else
    lines+=("" "BAD latest backup has unreadable files: $backup")
    failed=1
  fi
  clack_note "YubiKey $serial" "${lines[@]}"
done

if ((failed)); then
  die "verification found problems"
fi
clack_outro "All good"
