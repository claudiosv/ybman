# YubiKey discovery and selection.

YK_SERIALS=()

yk_list() {
  YK_SERIALS=()
  local serial
  while IFS= read -r serial; do
    [[ -z "$serial" ]] || YK_SERIALS+=("$serial")
  done < <(ykman list --serials 2>/dev/null)
  ((${#YK_SERIALS[@]} > 0)) || die "no YubiKeys found"
}

# yk_field SERIAL "Device type" -> value from `ykman info`
yk_field() {
  ykman --device "$1" info 2>/dev/null |
    sed -n "s/^$2:[[:space:]]*//p" | sed -n '1p'
}

# yk_option SERIAL -> "serial|label|hint" for clack select
yk_option() {
  local type fw
  type="$(yk_field "$1" "Device type")"
  fw="$(yk_field "$1" "Firmware version")"
  printf '%s|%s|%s' "$1" "${type:-Unknown YubiKey}" "serial $1, firmware ${fw:-unknown}"
}

# yk_pick_one -> sets YK_DEVICE (honours --serial)
yk_pick_one() {
  yk_list
  if [[ -n "$(get_flag serial)" ]]; then
    yk_has_serial "$(get_flag serial)" || die "YubiKey $(get_flag serial) not connected"
    YK_DEVICE="$(get_flag serial)"
    return
  fi
  local options=() s
  for s in "${YK_SERIALS[@]}"; do options+=("$(yk_option "$s")"); done
  ui_select "Select a YubiKey" "${options[@]}"
  YK_DEVICE="$REPLY"
}

# yk_pick_many -> sets YK_SELECTED (array; honours --serial)
yk_pick_many() {
  yk_list
  YK_SELECTED=()
  if [[ -n "$(get_flag serial)" ]]; then
    yk_has_serial "$(get_flag serial)" || die "YubiKey $(get_flag serial) not connected"
    YK_SELECTED=("$(get_flag serial)")
    return
  fi
  if ((${#YK_SERIALS[@]} == 1)); then
    YK_SELECTED=("${YK_SERIALS[0]}")
    clack_log_info "Using the only connected YubiKey: $(yk_option "${YK_SERIALS[0]}" | cut -d'|' -f2,3 | tr '|' ' ')"
    return
  fi
  local options=() s
  for s in "${YK_SERIALS[@]}"; do options+=("$(yk_option "$s")"); done
  ui_multiselect YK_SELECTED "Select YubiKeys (space toggles, a selects all)" "${options[@]}"
}

yk_has_serial() {
  local s
  for s in "${YK_SERIALS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

# yk SERIAL ykman-args...
yk() {
  local serial=$1
  shift
  ykman --device "$serial" "$@"
}

yk_ask_pin() {
  ui_password "PIV PIN"
  YK_PIN="$REPLY"
}
