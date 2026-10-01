# Shared constants, UI wrappers and session cleanup.

set -eo pipefail

SLOTS=(9a 9c 9d 9e)
SLOT_NAMES=("PIV Authentication" "Digital Signature" "Key Management" "Card Authentication")
DEFAULT_SUBJECTS=("CN=MacOS login" "CN=Digital Signature" "CN=encryption" "CN=Card Authentication")
CHUID_OBJECT="5fc102"

YK_DEVICE=""
PIN_POLICY="default"
TOUCH_POLICY="default"
YK_PIN=""
TMP_DIR=""

# ---------------------------------------------------------------------------
# Session: temp dir + EXIT trap. Every command calls session_init first.
# ---------------------------------------------------------------------------

session_init() {
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ybman.XXXXXX")"
  trap session_cleanup EXIT
}

session_cleanup() {
  local status=$?
  trap - EXIT
  chuid_restore_on_exit
  YK_PIN=""
  [[ -z "$TMP_DIR" ]] || rm -rf "$TMP_DIR"
  exit "$status"
}

# ---------------------------------------------------------------------------
# UI wrappers around clack. Prompt helpers return their answer in $REPLY and
# abort cleanly on Ctrl+C.
# ---------------------------------------------------------------------------

die() {
  clack_log_error "$*"
  clack_cancel "Aborted."
  exit 1
}

ui_cancel() {
  clack_cancel "Cancelled."
  exit 130
}

# ui_text MESSAGE [DEFAULT] [VALIDATOR_FN]
ui_text() {
  REPLY="$(clack_text "$1" "" "${2:-}" "${3:-}")" || ui_cancel
}

# ui_password MESSAGE  (rejects empty input)
ui_password() {
  while true; do
    REPLY="$(clack_password "$1")" || ui_cancel
    [[ -n "$REPLY" ]] && return 0
    clack_log_warn "Input cannot be empty."
  done
}

# ui_select MESSAGE OPTION...   (OPTION is "value|label|hint|disabled" or plain)
ui_select() {
  REPLY="$(clack_select "$@")" || ui_cancel
}

# ui_multiselect ARRAY_VAR MESSAGE OPTION...  (at least one choice required)
ui_multiselect() {
  local var=$1 n
  while true; do
    clack_multiselect "$@" || ui_cancel
    eval "n=\${#${var}[@]}"
    ((n > 0)) && return 0
    clack_log_warn "Select at least one (space toggles, a selects all)."
  done
}

# ui_confirm MESSAGE [true|false]  -> status 0 for yes, 1 for no
ui_confirm() {
  local answer
  answer="$(clack_confirm "$1" "${2:-true}")" || true
  [[ -n "$answer" ]] || ui_cancel
  [[ "$answer" == true ]]
}

# run_step MESSAGE CMD...  Runs CMD under a spinner; output is shown only on failure.
run_step() {
  local msg=$1
  shift
  local log="$TMP_DIR/step.log"

  clack_spinner_start "$msg"
  if "$@" >"$log" 2>&1; then
    clack_spinner_stop "$msg"
  else
    clack_spinner_error "$msg - failed"
    [[ ! -s "$log" ]] || clack_log_error "$(tail -n 8 "$log")"
    return 1
  fi
}

validate_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || printf 'Must be a positive integer'
}

validate_nonempty() {
  [[ -n "$1" ]] || printf 'Cannot be empty'
}

# get_flag NAME -> value of --NAME (empty if unset). Keeps `args[--x]` keys out of
# the source, since shfmt would parse them as arithmetic.
get_flag() {
  local key="--$1"
  printf '%s' "${args[$key]:-}"
}

backup_root() {
  local root
  root="$(get_flag backup-root)"
  printf '%s' "${root:-$YBMAN_BACKUP_ROOT}"
}

# ui_note TITLE MULTILINE_TEXT
ui_note() {
  local title=$1 line lines=()
  while IFS= read -r line; do lines+=("$line"); done <<<"$2"
  clack_note "$title" "${lines[@]}"
}
