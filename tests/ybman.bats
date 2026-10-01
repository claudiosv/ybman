#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  # one P-256 key with a self-signed cert in slot 9a, valid 400 days
  openssl ecparam -name prime256v1 -genkey -noout -out "$STUB/key.pem"
  openssl pkey -in "$STUB/key.pem" -pubout -out "$STUB/pub.pem"
  openssl req -new -x509 -key "$STUB/key.pem" -sha256 -subj "/CN=stub" -days 400 -out "$STUB/cert.pem"
  cat >"$STUB/ykman" <<'STUB_EOF'
#!/usr/bin/env bash
echo "$*" >>"$(dirname "$0")/calls"
dir="$(dirname "$0")"
last="${*: -1}"
case "$*" in
  "list --serials") echo 111 ;;
  *"piv info"*) printf 'PIN tries remaining:      3/3\nPUK tries remaining:      3/3\n' ;;
  *"piv keys info 9a"*) printf 'Algorithm:              ECCP256\n' ;;
  *"piv certificates export 9a"*) cp "$dir/${STUB_CERT:-cert.pem}" "$last" ;;
  *"piv keys export 9a"*) cp "$dir/pub.pem" "$last" ;;
  *"piv objects export"*) echo chuid >"$last" ;;
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

@test "status --json reports slot 9a and empty slots" {
  run "$ROOT/ybman.sh" status --serial 111 --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"serial":"111"'* ]]
  [[ "$output" == *'"slot":"9a"'*'"subject":"CN=stub"'* ]]
  [[ "$output" == *'"slot":"9c"'*'"subject":null'* ]]
  [[ "$output" == *'"pin_tries":"3/3"'* ]]
}

@test "verify passes when the certificate matches the key" {
  run "$ROOT/ybman.sh" verify --serial 111 --backup-root "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
}

@test "verify fails when the certificate belongs to another key" {
  openssl ecparam -name prime256v1 -genkey -noout -out "$STUB/other.pem"
  openssl req -new -x509 -key "$STUB/other.pem" -sha256 -subj "/CN=other" -days 400 -out "$STUB/other-cert.pem"
  STUB_CERT=other-cert.pem run "$ROOT/ybman.sh" verify --serial 111 --backup-root "$BATS_TEST_TMPDIR/out"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match"* ]]
}

@test "export --type cert prints the certificate" {
  run "$ROOT/ybman.sh" export --serial 111 --type cert
  [ "$status" -eq 0 ]
  [[ "$output" == *"BEGIN CERTIFICATE"* ]]
}

@test "export --type ssh prints an authorized_keys line" {
  command -v ssh-keygen >/dev/null
  run "$ROOT/ybman.sh" export --serial 111 --type ssh --slot 9a
  [ "$status" -eq 0 ]
  [[ "$output" == "ecdsa-sha2-nistp256 "*" ybman-111-9a" ]]
}

@test "provision --dry-run changes nothing" {
  run "$ROOT/ybman.sh" provision --serial 111 --yes --dry-run --pin-policy once --touch-policy cached
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run"* ]]
  ! grep -q 'generate\|import' "$STUB/calls"
}

@test "refresh --expiring-within skips certificates that are not close to expiry" {
  run "$ROOT/ybman.sh" refresh --serial 111 --yes --expiring-within 30 --backup-root "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No certificates to refresh"* ]]
  ! grep -q 'generate' "$STUB/calls"
}

@test "restore refuses a missing backup directory" {
  run "$ROOT/ybman.sh" restore "$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "completions prints a completion function" {
  run "$ROOT/ybman.sh" completions
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _ybman"* ]]
}

@test "doctor reports a healthy setup with the stub" {
  run "$ROOT/ybman.sh" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 YubiKey(s) detected"* ]]
}
