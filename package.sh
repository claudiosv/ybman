# basher has no install hook and ybman.sh is build output (not in git), so
# fetch it from the latest GitHub release when basher sources this file.
# Needs `gh` auth while the repo is private. Idempotent: skipped once present.
BINS=bin/ybman

if [ ! -x "${BASH_SOURCE[0]%/*}/bin/ybman" ]; then
  (
    dir="${BASH_SOURCE[0]%/*}/bin"
    mkdir -p "$dir" &&
      env -u GH_TOKEN -u GITHUB_TOKEN gh release download \
        --repo claudiosv/ybman --pattern ybman.sh --output "$dir/ybman" --clobber &&
      chmod +x "$dir/ybman"
  ) || echo "ybman: could not download the latest release (gh auth login?)" >&2
fi
