# Our own shell sources; vendored clack.sh and the generated ybman.sh are excluded.
srcs := `fd -e sh . src --exclude clack.sh | sort | tr '\n' ' '`

# Build the single-file CLI from src/ with bashly.
build:
    bashly generate

fmt:
    shfmt -w {{srcs}}

harden:
    shellharden --replace {{srcs}}

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
