#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  cat >"$STUB/ykman" <<'STUB_EOF'
#!/usr/bin/env bash
case "$*" in
  "list --serials") echo 111 ;;
  *"info"*) echo "Device type: YubiKey Stub" ;;
  *) exit 1 ;;
esac
STUB_EOF
  chmod +x "$STUB/ykman"
  PATH="$STUB:$PATH"
}

@test "--help lists the three commands" {
  run "$ROOT/ybman.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *backup* && "$output" == *provision* && "$output" == *refresh* ]]
}

@test "provision rejects an unknown algorithm" {
  run "$ROOT/ybman.sh" provision --algorithm RSA1024
  [ "$status" -ne 0 ]
}

@test "TRACE=1 is refused" {
  TRACE=1 run "$ROOT/ybman.sh" backup --serial 111
  [ "$status" -ne 0 ]
  [[ "$output" == *TRACE* ]]
}

@test "backup writes a snapshot directory" {
  run "$ROOT/ybman.sh" backup --serial 111 --backup-root "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  dir="$(printf '%s\n' "$BATS_TEST_TMPDIR"/out/111-* | head -n1)"
  [ -f "$dir/device-info.txt" ]
  [ -f "$dir/piv-info-before.txt" ]
}

@test "backup rejects a serial that is not connected" {
  run "$ROOT/ybman.sh" backup --serial 999 --backup-root "$BATS_TEST_TMPDIR/out"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not connected"* ]]
}

@test "crypto helpers: fingerprint is stable and hash follows curve" {
  command -v openssl >/dev/null
  openssl ecparam -name secp384r1 -genkey -noout -out "$BATS_TEST_TMPDIR/k.pem"
  openssl pkey -in "$BATS_TEST_TMPDIR/k.pem" -pubout -out "$BATS_TEST_TMPDIR/p.pem"
  source "$ROOT/src/lib/crypto.sh"
  [ "$(hash_for_pubkey "$BATS_TEST_TMPDIR/p.pem")" = SHA384 ]
  [ "$(pubkey_fingerprint "$BATS_TEST_TMPDIR/p.pem")" = "$(pubkey_fingerprint "$BATS_TEST_TMPDIR/p.pem")" ]
  openssl req -new -x509 -key "$BATS_TEST_TMPDIR/k.pem" -sha384 -subj "/CN=t" -days 5 -out "$BATS_TEST_TMPDIR/c.pem"
  [ "$(hash_from_cert "$BATS_TEST_TMPDIR/c.pem")" = SHA384 ]
  [ "$(x509_name subject "$BATS_TEST_TMPDIR/c.pem")" = "CN=t" ]
}
