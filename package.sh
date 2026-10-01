# ybman.sh is build output (not in git). In a local checkout that has been
# built (`just link`) expose it as bin/ybman, so no download happens.
# Otherwise (a plain `basher install`) fetch the latest GitHub release whenever
# basher sources this file (install and upgrade). That needs `gh` auth while the
# repo is private; the old binary is kept on failure.
BINS=bin/ybman

if [ -f "${BASH_SOURCE[0]%/*}/ybman.sh" ]; then
  mkdir -p "${BASH_SOURCE[0]%/*}/bin" &&
    ln -sf ../ybman.sh "${BASH_SOURCE[0]%/*}/bin/ybman"
else
  (
    dir="${BASH_SOURCE[0]%/*}/bin"
    mkdir -p "$dir" &&
      env -u GH_TOKEN -u GITHUB_TOKEN gh release download \
        --repo claudiosv/ybman --pattern ybman.sh --output "$dir/ybman.new" --clobber &&
      chmod +x "$dir/ybman.new" &&
      mv "$dir/ybman.new" "$dir/ybman"
  ) || echo "ybman: could not download the latest release (gh auth login?)" >&2
fi
