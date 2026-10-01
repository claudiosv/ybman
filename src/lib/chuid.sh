# CHUID save/restore. On firmware < 5.8, changing a certificate regenerates the
# CHUID; we restore the original afterwards (and on abnormal exit).

CHUID_FILE=""
CHUID_SERIAL=""
CHUID_DIRTY=0

# chuid_save SERIAL FILE -> 0 if saved
chuid_save() {
  if yk "$1" piv objects export "$CHUID_OBJECT" "$2" >/dev/null 2>&1; then
    CHUID_SERIAL="$1"
    CHUID_FILE="$2"
    return 0
  fi
  return 1
}

# Call right before the first certificate change.
chuid_mark_dirty() { CHUID_DIRTY=1; }

# chuid_restore: import saved CHUID and verify it round-trips.
chuid_restore() {
  [[ -n "$CHUID_FILE" ]] || return 0
  local check="$TMP_DIR/chuid-after.bin"
  yk "$CHUID_SERIAL" piv objects import --pin "$YK_PIN" "$CHUID_OBJECT" "$CHUID_FILE"
  yk "$CHUID_SERIAL" piv objects export "$CHUID_OBJECT" "$check"
  cmp -s "$CHUID_FILE" "$check" || return 1
  CHUID_DIRTY=0
}

chuid_restore_on_exit() {
  ((CHUID_DIRTY)) && [[ -n "$CHUID_FILE" && -n "$YK_PIN" ]] || return 0
  clack_log_warn "Attempting to restore original CHUID on YubiKey $CHUID_SERIAL..."
  yk "$CHUID_SERIAL" piv objects import --pin "$YK_PIN" "$CHUID_OBJECT" "$CHUID_FILE" \
    >/dev/null 2>&1 || true
}

chuid_forget() {
  CHUID_FILE=""
  CHUID_SERIAL=""
  CHUID_DIRTY=0
}
