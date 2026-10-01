session_init
json="$(get_flag json)"

if [[ -n "$json" ]]; then
  yk_pick_all
  dirs=()
  for serial in "${YK_SELECTED[@]}"; do
    dir="$(new_backup_dir "$serial")"
    write_snapshot "$serial" "$dir" before || die "backup of YubiKey $serial failed"
    dirs+=("$dir")
  done
  out=""
  for dir in "${dirs[@]}"; do out+="${out:+,}$(json_str "$dir")"; done
  printf '[%s]\n' "$out"
  exit 0
fi

clack_intro "ybman backup"

yk_pick_many

dirs=()
for serial in "${YK_SELECTED[@]}"; do
  dir="$(new_backup_dir "$serial")"
  run_step "Backing up YubiKey $serial" write_snapshot "$serial" "$dir" before ||
    die "backup of YubiKey $serial failed"
  dirs+=("$dir")
done

clack_note "Backups written" "${dirs[@]}"
clack_outro "Done"
