# Our own shell sources; vendored clack.sh and the generated ybman.sh are excluded.
srcs := `fd -e sh . src --exclude clack.sh | sort | tr '\n' ' '`

# Build the single-file CLI from src/ with bashly.
build:
    bashly generate

fmt:
    shfmt -w {{srcs}}

# Apply shellcheck's auto-fixes (only fixable findings produce a diff).
fix:
    shellcheck -s bash -f diff {{srcs}} | git apply --allow-empty

harden:
    shellharden --replace {{srcs}}

# Build from the local checkout and install it (no download). PREFIX defaults to ~/.local.
install prefix=env("PREFIX", home_directory() / ".local"): build
    install -d {{prefix}}/bin
    install -m 755 ybman.sh {{prefix}}/bin/ybman
    @echo "installed {{prefix}}/bin/ybman"

# Build and register this checkout with basher (symlinks ./ybman.sh as `ybman`; no download).
# If basher already has claudiosv/ybman installed: basher uninstall claudiosv/ybman
link: build
    basher link . claudiosv/ybman

# Read-only checks (same as the pre-commit hooks).
lint: build
    shfmt -d {{srcs}}
    shellharden --check {{srcs}}
    shellcheck -S warning -e SC2034,SC2206 ybman.sh

test: build
    bats tests

check: lint test

hooks:
    prek install
