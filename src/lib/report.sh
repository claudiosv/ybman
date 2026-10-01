# Read-only reporting helpers (status, verify, export, JSON output).

# json_str STRING -> JSON string literal
json_str() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}

# json_or_null STRING -> JSON string, or null when empty
json_or_null() {
  if [[ -n "$1" ]]; then json_str "$1"; else printf 'null'; fi
}

# cert_end_epoch CERT -> notAfter as a Unix timestamp (GNU or BSD date)
cert_end_epoch() {
  local end
  end="$(openssl x509 -enddate -noout -in "$1")"
  end="${end#notAfter=}"
  date -u -d "$end" +%s 2>/dev/null || date -u -j -f '%b %e %T %Y %Z' "$end" +%s
}

# fmt_date EPOCH -> YYYY-MM-DD (UTC)
fmt_date() {
  date -u -d "@$1" +%F 2>/dev/null || date -u -r "$1" +%F
}

# slot_facts SERIAL SLOT -> sets F_ALGO F_SUBJECT F_END (date) F_DAYS (empty if absent)
F_ALGO="" F_SUBJECT="" F_END="" F_DAYS=""
slot_facts() {
  local serial=$1 slot=$2 cert="$TMP_DIR/$2-status.pem" info end
  F_ALGO="" F_SUBJECT="" F_END="" F_DAYS=""
  if info="$(yk "$serial" piv keys info "$slot" 2>/dev/null)"; then
    F_ALGO="$(sed -n 's/^Algorithm:[[:space:]]*//p' <<<"$info")"
  fi
  if yk "$serial" piv certificates export "$slot" "$cert" >/dev/null 2>&1; then
    F_SUBJECT="$(x509_name subject "$cert")"
    end="$(cert_end_epoch "$cert")"
    F_END="$(fmt_date "$end")"
    F_DAYS=$(((end - $(date +%s)) / 86400))
  fi
}

# piv_retries SERIAL pin|puk -> "3/3"
piv_retries() {
  local label
  label="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
  yk "$1" piv info 2>/dev/null | sed -n "s/^$label tries remaining:[[:space:]]*//p"
}

# verify_slot SERIAL SLOT DEEP  Prints a one-line verdict; returns 1 on a real problem.
# DEEP=1 also proves the PIN-protected private key works (needs YK_PIN).
verify_slot() {
  local serial=$1 slot=$2 deep=$3
  local cert="$TMP_DIR/$slot-v-cert.pem" pub="$TMP_DIR/$slot-v-pub.pem" cpub="$TMP_DIR/$slot-v-cpub.pem"
  local key=0 has_cert=0

  yk "$serial" piv keys info "$slot" >/dev/null 2>&1 && key=1
  yk "$serial" piv certificates export "$slot" "$cert" >/dev/null 2>&1 && has_cert=1
  if ((! key && ! has_cert)); then
    echo "empty"
    return 0
  fi
  if ((! key)); then
    echo "certificate without a detectable key"
    return 1
  fi
  if ((! has_cert)); then
    echo "key without certificate"
    return 0
  fi

  if ((deep)); then
    yk "$serial" piv keys export --pin "$YK_PIN" --verify "$slot" "$pub" >/dev/null 2>&1 ||
      {
        echo "key verification failed"
        return 1
      }
  else
    yk "$serial" piv keys export "$slot" "$pub" >/dev/null 2>&1 ||
      {
        echo "cannot read the public key"
        return 1
      }
  fi
  openssl x509 -in "$cert" -pubkey -noout >"$cpub" 2>/dev/null ||
    {
      echo "certificate does not parse"
      return 1
    }
  [[ "$(pubkey_fingerprint "$pub")" == "$(pubkey_fingerprint "$cpub")" ]] ||
    {
      echo "certificate does not match the key"
      return 1
    }
  if ! openssl x509 -checkend 0 -noout -in "$cert" >/dev/null; then
    echo "certificate EXPIRED"
    return 1
  fi
  echo "ok"
}

# verify_backup_dir DIR -> returns 1 if any saved cert/public key fails to parse
verify_backup_dir() {
  local f bad=0
  for f in "$1"/*-cert.pem; do
    [[ -e "$f" ]] || continue
    openssl x509 -in "$f" -noout 2>/dev/null || bad=1
  done
  for f in "$1"/*-pubkey*.pem; do
    [[ -e "$f" ]] || continue
    openssl pkey -pubin -in "$f" -noout 2>/dev/null || bad=1
  done
  return "$bad"
}

# latest_backup SERIAL -> newest backup dir for SERIAL (empty if none)
latest_backup() {
  local d last=""
  for d in "$(backup_root)/$1"-*/; do
    [[ -d "$d" ]] && last="${d%/}"
  done
  printf '%s' "$last"
}
