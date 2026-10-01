# Per-slot operations. These run under run_step (an `if` context where errexit
# is disabled), so every command is checked explicitly.

# slot_classify SERIAL -> fills SLOT_STATE[] (complete|key-only|certificate-only|empty)
SLOT_STATE=()
slot_classify() {
  local serial=$1 i slot key cert
  SLOT_STATE=()
  for i in "${!SLOTS[@]}"; do
    slot="${SLOTS[$i]}"
    key=0 cert=0
    yk "$serial" piv keys info "$slot" >/dev/null 2>&1 && key=1
    yk "$serial" piv certificates export "$slot" "$TMP_DIR/$slot-existing.pem" >/dev/null 2>&1 && cert=1
    if ((key && cert)); then
      SLOT_STATE[i]="complete"
    elif ((key)); then
      SLOT_STATE[i]="key-only"
    elif ((cert)); then
      SLOT_STATE[i]="certificate-only"
    else
      SLOT_STATE[i]="empty"
    fi
  done
}

# provision_slot SERIAL SLOT STATE SUBJECT ALGORITHM DAYS
provision_slot() {
  local serial=$1 slot=$2 state=$3 subject=$4 algorithm=$5 days=$6
  local pub="$TMP_DIR/$slot-public.pem" ver="$TMP_DIR/$slot-verified-public.pem"
  local cert="$TMP_DIR/$slot-certificate.pem" cpub="$TMP_DIR/$slot-certificate-public.pem"
  local hash fp_orig fp_ver fp_cert

  if [[ "$state" == empty ]]; then
    yk "$serial" piv keys generate --pin "$YK_PIN" --algorithm "$algorithm" \
      --pin-policy "$PIN_POLICY" --touch-policy "$TOUCH_POLICY" "$slot" "$pub" || return 1
  else
    yk "$serial" piv keys export --pin "$YK_PIN" --verify "$slot" "$pub" || return 1
  fi

  hash="$(hash_for_pubkey "$pub")"
  chuid_mark_dirty
  yk "$serial" piv certificates generate --pin "$YK_PIN" --subject "$subject" \
    --valid-days "$days" --hash-algorithm "$hash" "$slot" "$pub" || return 1
  yk "$serial" piv certificates export "$slot" "$cert" || return 1
  yk "$serial" piv keys export --pin "$YK_PIN" --verify "$slot" "$ver" || return 1

  fp_orig="$(pubkey_fingerprint "$pub")"
  fp_ver="$(pubkey_fingerprint "$ver")"
  [[ "$fp_orig" == "$fp_ver" ]] || {
    echo "private/public-key verification failed for slot $slot" >&2
    return 1
  }
  openssl x509 -in "$cert" -pubkey -noout >"$cpub" || return 1
  fp_cert="$(pubkey_fingerprint "$cpub")"
  [[ "$fp_orig" == "$fp_cert" ]] || {
    echo "certificate public key does not match slot $slot" >&2
    return 1
  }
}

# refresh_preflight SERIAL SLOT DIR
# Requires DIR/SLOT-cert.pem from write_snapshot. Verifies the key, refuses
# CA-issued or extension-bearing certs, records subject and hash.
refresh_preflight() {
  local serial=$1 slot=$2 dir=$3
  local cert="$dir/$slot-cert.pem" pub="$dir/$slot-pubkey-verified.pem"
  local subject issuer hash

  yk "$serial" piv keys export --pin "$YK_PIN" --verify "$slot" "$pub" || return 1

  subject="$(x509_name subject "$cert")"
  issuer="$(x509_name issuer "$cert")"
  [[ "$subject" == "$issuer" ]] || {
    printf 'slot %s is not self-issued (subject: %s, issuer: %s); refusing to replace a CA-issued certificate\n' \
      "$slot" "$subject" "$issuer" >&2
    return 1
  }
  ! cert_has_extensions "$cert" || {
    echo "slot $slot certificate has X.509 extensions that ykman cannot preserve; refusing" >&2
    return 1
  }
  hash="$(hash_from_cert "$cert")" || return 1

  printf '%s\n' "$subject" >"$dir/$slot-subject.txt"
  printf '%s\n' "$hash" >"$dir/$slot-hash.txt"
  cert_summary "$cert" >"$dir/$slot-cert-old-info.txt"
}

# refresh_slot SERIAL SLOT DIR DAYS
refresh_slot() {
  local serial=$1 slot=$2 dir=$3 days=$4
  local pub="$dir/$slot-pubkey-verified.pem" pub_new="$dir/$slot-pubkey-new.pem"
  local cert_new="$dir/$slot-cert-new.pem" subject hash

  subject="$(<"$dir/$slot-subject.txt")"
  hash="$(<"$dir/$slot-hash.txt")"

  chuid_mark_dirty
  yk "$serial" piv certificates generate --pin "$YK_PIN" --subject "$subject" \
    --valid-days "$days" --hash-algorithm "$hash" "$slot" "$pub" || return 1
  yk "$serial" piv certificates export "$slot" "$cert_new" || return 1
  yk "$serial" piv keys export --pin "$YK_PIN" --verify "$slot" "$pub_new" || return 1

  [[ "$(pubkey_fingerprint "$pub")" == "$(pubkey_fingerprint "$pub_new")" ]] || {
    echo "public key changed unexpectedly in slot $slot" >&2
    return 1
  }
  cert_summary "$cert_new" >"$dir/$slot-cert-new-info.txt"
}

# restore_slot SERIAL SLOT DIR
# Re-imports DIR/SLOT-cert.pem if it belongs to the key currently in the slot.
restore_slot() {
  local serial=$1 slot=$2 dir=$3
  local cur="$TMP_DIR/$slot-restore-cur.pem" bak="$TMP_DIR/$slot-restore-bak.pem"

  yk "$serial" piv keys export "$slot" "$cur" || return 1
  openssl x509 -in "$dir/$slot-cert.pem" -pubkey -noout >"$bak" || return 1
  [[ "$(pubkey_fingerprint "$cur")" == "$(pubkey_fingerprint "$bak")" ]] || {
    echo "the backup certificate does not belong to the key now in slot $slot" >&2
    return 1
  }
  chuid_mark_dirty
  yk "$serial" piv certificates import --pin "$YK_PIN" "$slot" "$dir/$slot-cert.pem" || return 1
}
