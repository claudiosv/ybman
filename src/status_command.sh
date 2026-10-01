session_init
json="$(get_flag json)"

if [[ -n "$json" ]]; then
  yk_pick_all
else
  clack_intro "ybman status"
  yk_pick_many
fi

devices=()
for serial in "${YK_SELECTED[@]}"; do
  slots=()
  lines=("PIN tries $(piv_retries "$serial" pin)   PUK tries $(piv_retries "$serial" puk)" "")
  for i in "${!SLOTS[@]}"; do
    slot="${SLOTS[$i]}"
    slot_facts "$serial" "$slot"
    if [[ -n "$json" ]]; then
      days=null
      [[ -z "$F_DAYS" ]] || days="$F_DAYS"
      slots+=("{\"slot\":\"$slot\",\"name\":$(json_str "${SLOT_NAMES[$i]}"),\"algorithm\":$(json_or_null "$F_ALGO"),\"subject\":$(json_or_null "$F_SUBJECT"),\"not_after\":$(json_or_null "$F_END"),\"days_left\":$days}")
    elif [[ -z "$F_ALGO$F_SUBJECT" ]]; then
      lines+=("$(printf '%-3s %-20s empty' "$slot" "${SLOT_NAMES[$i]}")")
    else
      warn=""
      if [[ -n "$F_DAYS" ]]; then
        ((F_DAYS >= 0)) || warn="  EXPIRED"
        ((F_DAYS < 0 || F_DAYS >= 30)) || warn="  expires soon"
      fi
      lines+=("$(printf '%-3s %-20s %-8s %-24s %s (%s days)%s' "$slot" "${SLOT_NAMES[$i]}" "${F_ALGO:--}" "${F_SUBJECT:--}" "${F_END:--}" "${F_DAYS:--}" "$warn")")
    fi
  done
  if [[ -n "$json" ]]; then
    joined="$(
      IFS=,
      printf '%s' "${slots[*]}"
    )"
    devices+=("{\"serial\":$(json_str "$serial"),\"pin_tries\":$(json_or_null "$(piv_retries "$serial" pin)"),\"puk_tries\":$(json_or_null "$(piv_retries "$serial" puk)"),\"slots\":[$joined]}")
  else
    clack_note "YubiKey $serial" "${lines[@]}"
  fi
done

if [[ -n "$json" ]]; then
  (
    IFS=,
    printf '[%s]\n' "${devices[*]}"
  )
else
  clack_outro "Done"
fi
