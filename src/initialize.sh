# TRACE would echo the PIV PIN into the terminal/log.
if [[ "${TRACE-0}" == "1" ]]; then
  echo "error: TRACE=1 is not allowed because ybman handles a PIV PIN" >&2
  exit 1
fi

enable_auto_colors
