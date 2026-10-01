session_init

type="$(get_flag type)"
out="$(get_flag out)"
slot_filter="$(get_flag slot)"
[[ "$type" != ssh ]] || command -v ssh-keygen >/dev/null || die "ssh-keygen is required for --type ssh"

yk_pick_one
serial="$YK_DEVICE"
[[ -z "$out" ]] || mkdir -p "$out"

exported=0
for slot in "${SLOTS[@]}"; do
  [[ -z "$slot_filter" || "$slot_filter" == "$slot" ]] || continue
  file="$TMP_DIR/$slot-export.pem"
  case "$type" in
    cert) yk "$serial" piv certificates export "$slot" "$file" >/dev/null 2>&1 || continue ;;
    *) yk "$serial" piv keys export "$slot" "$file" >/dev/null 2>&1 || continue ;;
  esac
  suffix=pem
  if [[ "$type" == ssh ]]; then
    line="$(ssh-keygen -i -m PKCS8 -f "$file" 2>/dev/null)" || {
      clack_log_warn "slot $slot: key type has no SSH representation; skipped" >&2
      continue
    }
    printf '%s ybman-%s-%s\n' "$line" "$serial" "$slot" >"$file.ssh"
    file="$file.ssh"
    suffix=pub
  fi
  if [[ -n "$out" ]]; then
    cp "$file" "$out/$serial-$slot-$type.$suffix"
  else
    cat "$file"
  fi
  exported=$((exported + 1))
done

((exported > 0)) || die "nothing to export (no matching $type found)"
[[ -z "$out" ]] || echo "Wrote $exported file(s) to $out" >&2
