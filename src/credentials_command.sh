session_init
clack_intro "ybman credentials"

yk_pick_one
serial="$YK_DEVICE"

change="$(get_flag change)"
if [[ -z "$change" ]]; then
  ui_select "What do you want to change?" \
    "all|Set up a new YubiKey|PIN, PUK and a PIN-protected management key" \
    "pin|PIN|6-8 characters, default is 123456" \
    "puk|PUK|used to unblock the PIN, default is 12345678" \
    "management-key|Management key|stored on the YubiKey, protected by the PIN"
  change="$REPLY"
fi

# ykman prompts for the secrets itself, so these run attached to the terminal.
clack_log_info "ykman will ask for the current and new values."
if [[ "$change" == all || "$change" == pin ]]; then
  yk "$serial" piv access change-pin || die "changing the PIN failed"
fi
if [[ "$change" == all || "$change" == puk ]]; then
  yk "$serial" piv access change-puk || die "changing the PUK failed"
fi
if [[ "$change" == all || "$change" == management-key ]]; then
  yk "$serial" piv access change-management-key --algorithm aes256 --protect ||
    die "changing the management key failed"
fi
clack_outro "Done"
