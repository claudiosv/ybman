session_init
clack_intro "ybman doctor"

problems=0
# check LABEL OK(0|1) HINT
check() {
  if (($2)); then
    clack_log_success "$1"
  else
    clack_log_error "$1 - $3"
    problems=1
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

if have ykman; then
  check "ykman $(ykman --version 2>/dev/null | sed -n 's/.*version: *//p')" 1
else
  check "ykman" 0 "install YubiKey Manager CLI (brew install ykman / apt install yubikey-manager)"
fi
for tool in openssl cmp; do
  if have "$tool"; then check "$tool" 1; else check "$tool" 0 "install it (cmp is in diffutils)"; fi
done
if have ugrep; then
  check "ugrep" 1
elif have grep; then
  clack_log_info "ugrep not found, using grep"
fi
have ssh-keygen || clack_log_warn "ssh-keygen not found: 'export --type ssh' will not work"

if have ykman; then
  listing="$(ykman list 2>&1 || true)"
  if [[ "$listing" == *"PC/SC not available"* ]]; then
    check "PC/SC smart card service" 0 "install and start pcscd (Linux: apt install pcscd && systemctl enable --now pcscd.socket)"
  else
    check "PC/SC smart card service" 1
  fi
  count="$(ykman list --serials 2>/dev/null | grep -c . || true)"
  if ((count > 0)); then
    check "$count YubiKey(s) detected" 1
  else
    check "YubiKey detected" 0 "plug one in; on Linux check udev rules (yubikey-manager docs); another app (scdaemon, gpg-agent) may be holding the card"
  fi
fi

((problems == 0)) || die "problems found"
clack_outro "Everything looks fine"
