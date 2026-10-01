# OpenSSL helpers for PIV public keys and certificates.

# search ARGS... : ugrep when installed, else grep.
search() {
  if command -v ugrep >/dev/null 2>&1; then ugrep --color=never "$@"; else grep --color=never "$@"; fi
}

pubkey_fingerprint() {
  openssl pkey -pubin -in "$1" -outform DER 2>/dev/null |
    openssl dgst -sha256 |
    sed -E 's/^.*= //'
}

# Hash for a new self-signed cert: SHA384 for P-384 keys, else SHA256.
hash_for_pubkey() {
  local description
  description="$(openssl pkey -pubin -in "$1" -text -noout 2>/dev/null)"
  case "$description" in
    *secp384r1* | *"P-384"* | *"384 bit"*) printf 'SHA384' ;;
    *) printf 'SHA256' ;;
  esac
}

# Hash used to sign an existing certificate.
hash_from_cert() {
  local algorithm
  algorithm="$(
    openssl x509 -in "$1" -noout -text |
      search -m1 'Signature Algorithm:' |
      sed -E 's/.*Signature Algorithm:[[:space:]]*//'
  )"
  case "$algorithm" in
    *SHA512* | *sha512*) printf 'SHA512' ;;
    *SHA384* | *sha384*) printf 'SHA384' ;;
    *SHA256* | *sha256*) printf 'SHA256' ;;
    *)
      printf 'unsupported signature algorithm: %s\n' "$algorithm" >&2
      return 1
      ;;
  esac
}

# x509_name subject|issuer CERT  (RFC2253)
x509_name() {
  openssl x509 -in "$2" -noout "-$1" -nameopt RFC2253 | sed -E "s/^$1= ?//"
}

cert_has_extensions() {
  openssl x509 -in "$1" -noout -text | search -q 'X509v3 extensions:'
}

cert_summary() {
  openssl x509 -in "$1" -noout -subject -issuer -serial -dates -fingerprint -sha256
}
