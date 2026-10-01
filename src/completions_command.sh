cat <<'COMPLETION_EOF'
# source <(ybman completions)
_ybman() {
  local cur=${COMP_WORDS[COMP_CWORD]} words
  if ((COMP_CWORD == 1)); then
    words="$("${COMP_WORDS[0]}" --help 2>/dev/null | grep -E '^  [a-z]+ +[A-Z]' | awk '{print $1}')"
  elif [[ "$cur" == -* ]]; then
    words="$("${COMP_WORDS[0]}" "${COMP_WORDS[1]}" --help 2>/dev/null | grep -oE -- '--[a-z-]+' | sort -u)"
  fi
  COMPREPLY=($(compgen -W "$words" -- "$cur"))
}
complete -F _ybman ybman ybman.sh
COMPLETION_EOF
