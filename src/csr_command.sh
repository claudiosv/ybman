session_init
clack_intro "ybman csr"

yk_pick_one
serial="$YK_DEVICE"
slot="$(get_flag slot)"

yk "$serial" piv keys info "$slot" >/dev/null 2>&1 || die "slot $slot has no key"
pub="$TMP_DIR/$slot-csr-pub.pem"
yk "$serial" piv keys export "$slot" "$pub" || die "cannot read the public key of slot $slot"

subject="$(get_flag subject)"
if [[ -z "$subject" ]]; then
  default_subject=""
  if yk "$serial" piv certificates export "$slot" "$TMP_DIR/$slot-csr-cert.pem" >/dev/null 2>&1; then
    default_subject="$(x509_name subject "$TMP_DIR/$slot-csr-cert.pem")"
  fi
  for i in "${!SLOTS[@]}"; do
    [[ "${SLOTS[$i]}" != "$slot" ]] || default_subject="${default_subject:-${DEFAULT_SUBJECTS[$i]}}"
  done
  ui_text "Subject for the request" "$default_subject" validate_nonempty
  subject="$REPLY"
fi

out="$(get_flag out)"
out="${out:-./$serial-$slot.csr}"
hash="$(hash_for_pubkey "$pub")"

clack_log_info "Signing happens on the YubiKey; touch it if it blinks. Slot 9d (key management) cannot sign."
yk_ask_pin
run_step "Creating CSR for slot $slot" \
  yk "$serial" piv certificates request --pin "$YK_PIN" --subject "$subject" \
  --hash-algorithm "$hash" "$slot" "$pub" "$out" || die "CSR creation failed"
clack_outro "Wrote $out"
