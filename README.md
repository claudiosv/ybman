# ybman

Manage the four primary PIV slots on YubiKeys from the terminal: back up their state, provision empty slots with on-device keys and self-signed certificates, and renew expiring certificates without changing the keys.

ybman is a thin, interactive wrapper around [`ykman`](https://docs.yubico.com/software/yubikey/tools/ykman/) and `openssl`. It is built with [bashly](https://bashly.dev) into a single bash file (`ybman.sh`) and uses a vendored copy of [clack.sh](src/lib/UPSTREAM.md) for the prompts.

| Slot | Purpose | Default subject |
|------|---------|-----------------|
| `9a` | PIV Authentication | `CN=MacOS login` |
| `9c` | Digital Signature | `CN=Digital Signature` |
| `9d` | Key Management | `CN=encryption` |
| `9e` | Card Authentication | `CN=Card Authentication` |

## Install

### With basher

[basher](https://github.com/basherpm/basher) is a package manager for shell scripts.

```sh
basher install claudiosv/ybman
ybman --help
```

`ybman.sh` is build output and is not committed to git. Instead, basher sources the repo's `package.sh`, which downloads the latest `ybman.sh` from the GitHub release into `bin/ybman`. This has three consequences:

- **`gh` is required** and must be authenticated (`gh auth login`) while the repository is private. If the download fails, ybman prints `could not download the latest release (gh auth login?)`.
- **Private repo:** basher clones over HTTPS, so git needs credentials for GitHub. `gh auth setup-git` configures them, or install from an SSH URL: `basher install git@github.com:claudiosv/ybman.git`.
- **Upgrading:** `basher upgrade claudiosv/ybman` re-runs `package.sh`, which downloads the latest release every time. If the download fails, the previously installed binary is kept.

When installed through basher the command is `ybman`; elsewhere in this README it is written `ybman.sh`.

### From a release

Every push to `main` that passes CI publishes a release containing `ybman.sh` and `ybman.sh.sha256`.

```sh
gh release download --repo claudiosv/ybman --pattern 'ybman.sh*' --dir /tmp/ybman
(cd /tmp/ybman && shasum -a 256 -c ybman.sh.sha256)
install -m 755 /tmp/ybman/ybman.sh ~/.local/bin/ybman
```

### From source

```sh
git clone git@github.com:claudiosv/ybman.git && cd ybman
just build        # runs `bashly generate`, writes ./ybman.sh
./ybman.sh --help
```

## Requirements

| Tool | Needed by |
|------|-----------|
| `ykman` (YubiKey Manager CLI) | all commands |
| `openssl` | `provision`, `refresh` |
| `cmp` (diffutils) | `provision`, `refresh` (CHUID restore check) |
| `ssh-keygen` | `export --type ssh` only |
| `gh` | basher install only |

bashly checks the per-command dependencies at startup and tells you which is missing. A YubiKey with PIV enabled and your PIV PIN are needed for `provision` and `refresh`.

## Usage

```
ybman.sh <command> [flags]
```

Commands have short aliases: `b`, `p`, `r`, `s`, `v`, `e`, `c`. Run `ybman.sh <command> --help` for the full text.

### Common flags

| Flag | Description |
|------|-------------|
| `--serial`, `-s` *serial* | Operate on this YubiKey only and skip the device picker |
| `--backup-root` *dir* | Where backups are written. Default `./yubikey-piv-backups`, or `$YBMAN_BACKUP_ROOT` |
| `--yes`, `-y` | Skip prompts and confirmation (`provision`, `refresh`) |
| `--valid-days`, `-d` *days* | Certificate validity, default `3650` (`provision`, `refresh`) |
| `--dry-run` | Show the plan and exit without changing the YubiKey (`provision`, `refresh`) |
| `--json` | Machine-readable output, never prompts (`backup`, `status`) |

### `backup`

Read-only snapshot of one or more YubiKeys. With several keys connected you get a multi-select; with exactly one it is used automatically.

```sh
ybman.sh backup
ybman.sh backup --serial 37614918
```

### `provision`

Fills empty PIV slots on one YubiKey.

```sh
ybman.sh provision
ybman.sh provision -s 37614918 -a ECCP256 -d 1825
ybman.sh provision --yes        # defaults for everything, no prompts
```

- `--algorithm`, `-a`: `ECCP256` or `ECCP384` (default `ECCP384`) for newly generated keys.
- Each of the four slots is classified as `complete`, `key-only`, `certificate-only` or `empty`.
  - `empty`: generate a key on the device, then a self-signed certificate.
  - `key-only`: keep the key, create a certificate.
  - `complete`: left untouched.
  - `certificate-only`: aborts, since there is no detectable private key.
- Existing keys are never replaced.
- A wizard lets you choose the algorithm, validity and subject per slot, shows a plan, and asks for confirmation before asking for the PIN.
- Every new certificate is checked against the key on the device, and the key is verified with a PIN-protected signature.

### `refresh`

Renews self-signed certificates in place, keeping the existing keys, for example before they expire.

```sh
ybman.sh refresh
ybman.sh refresh --serial 37614918 --valid-days 3650 --yes
```

For every slot that has a certificate, ybman first checks that it can do so safely and refuses otherwise:

- the key on the device is verified with the PIN,
- the certificate must be self-issued (subject equals issuer), so CA-issued certificates are never replaced,
- the certificate must have no X.509 extensions, because `ykman` cannot reproduce them,
- the subject and signature hash (SHA256/384/512) of the old certificate are reused,
- afterwards the public key in the slot must be unchanged.

Extra flags: `--expiring-within DAYS` refreshes only certificates that expire within that many days (and does not ask for the PIN when none do, which suits a scheduled job), and `--dry-run` runs the preflight checks and prints the plan.

### `status`

Read-only overview of each YubiKey: PIN/PUK retries left, and per slot the key algorithm, subject, expiry date and days left, flagged `expires soon` under 30 days.

```sh
ybman.sh status
ybman.sh status --json | jq '.[].slots[] | select(.days_left < 60)'
```

### `verify`

Checks that each slot's certificate matches the key on the device, that nothing has expired, and that the latest backup parses. Exits non-zero on any problem. `--deep` also proves each private key works, using the PIN.

### `restore`

Puts certificates from a backup back on the YubiKey, which also undoes a `refresh`. Only certificates whose public key matches the key currently in the slot are restored, and keys are never touched. The current state is backed up first.

```sh
ybman.sh restore                                    # pick a backup
ybman.sh restore yubikey-piv-backups/37614918-20261001-120933
```

### `export`

Prints or saves certificates and public keys. `--type` is `cert` (default), `pubkey` or `ssh` (authorized_keys lines, needs `ssh-keygen`); `--slot` limits it to one slot; `--out DIR` writes one file per slot instead of printing.

```sh
ybman.sh export --type ssh --slot 9a >> ~/.ssh/authorized_keys
```

### `csr`

Creates a certificate signing request for a slot, signed on the YubiKey, so a CA can issue a certificate for it. Slot 9d cannot sign. Options: `--slot` (default `9a`), `--subject`, `--out` (default `./<serial>-<slot>.csr`).

### `credentials`

Changes the PIN, PUK or management key (`--change pin|puk|management-key|all`). `all` is the first-time setup and stores a random management key on the YubiKey, protected by the PIN, which is what `provision` and `refresh` rely on. `ykman` prompts for the secrets itself.

### `doctor`

Checks that `ykman`, `openssl`, `cmp`, the smart card service and a YubiKey are available, with a fix hint for each failure.

### `completions`

```sh
source <(ybman completions)    # bash; in zsh run `autoload -U bashcompinit && bashcompinit` first
```

`provision` also takes `--pin-policy` (`default|never|once|always|match-once|match-always`) and `--touch-policy` (`default|never|always|cached`), applied to newly generated keys only.

## Backups and safety

Each run creates `<backup-root>/<serial>-<YYYYmmdd-HHMMSS>/` containing:

```
device-info.txt        ykman info
piv-info-before.txt    ykman piv info (piv-info-after.txt after changes)
<slot>-cert.pem        certificate, if present
<slot>-pubkey.pem      public key, if present
<slot>-key-info.txt    ykman piv keys info
chuid.bin              original CHUID (provision / refresh)
```

`provision` and `refresh` also leave per-slot files (`*-cert-new.pem`, `*-cert-old-info.txt`, ...) for comparing before and after.

No private keys are ever exported, since they cannot leave the YubiKey. Backups still identify your devices and certificates, so they are git-ignored here; keep them somewhere sensible.

Other safeguards:

- **CHUID:** on firmware older than 5.8, changing a certificate regenerates the card's CHUID. ybman saves it first and restores it afterwards (and attempts a restore on abnormal exit). Restoring is verified byte for byte.
- **PIN handling:** the PIN is read with a hidden prompt, kept only in memory and cleared on exit. `TRACE=1` is refused because bashly's trace would echo the PIN.
- **Cleanup:** temporary files live in a `mktemp -d` directory removed on exit. Ctrl+C aborts cleanly with status 130.
- Failures during a change abort with the path of the backup taken just before.

## Development

Needs [bashly](https://bashly.dev), [just](https://just.systems), `shfmt`, `shellharden`, `shellcheck` and [bats](https://github.com/bats-core/bats-core).

```sh
just build     # bashly generate -> ybman.sh
just fmt       # shfmt -w
just harden    # shellharden --replace
just fix       # apply shellcheck's auto-fixes (diff format)
just lint      # build, then shfmt -d, shellharden --check, shellcheck on ybman.sh
just test      # build, then bats tests
just check     # lint + test
just hooks     # install the git hooks with prek
```

Layout:

```
src/bashly.yml          command, flag and dependency definitions
src/*_command.sh        one file per command (backup, provision, refresh, status, verify, restore, export, csr, credentials, doctor, completions)
src/initialize.sh       refuses TRACE=1
src/lib/                shared helpers (common, yk, crypto, slot_ops, chuid, backup_core, report)
src/lib/clack.sh        vendored clack.sh (see UPSTREAM.md)
tests/ybman.bats        bats tests
package.sh              basher install hook
```

CI (`.github/workflows/ci.yml`) runs on every push. Pushes to `main` that pass then publish a release tagged `v<version>-build.<run number>` with `ybman.sh` and its checksum; the version comes from `src/bashly.yml`.

## License

No license has been specified yet.
