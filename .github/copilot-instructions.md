# machine-boostrapper — Copilot instructions

## Purpose
This repository contains a minimal bootstrap script to initialise a fresh Linux/macOS machine:
- generate a dedicated SSH key (defaults to `~/.ssh/bootstrapper`, configurable via `--ssh-pub-key`),
- display public key + QR code for easy copy to GitHub,
- clone a private provisioning repository (setup-private),
- run a provisioning script from the private repo to setup the full environment.

## Requirements
- `git` must already exist on the system (project policy).
- `ssh-keygen` must be available (the script can install it with `--auto-install` or prompt).
- `qrencode` is optional for QR code output (the script can install it or print plain public key).
- A private Git repository accessible via SSH.

## Script behaviour
- If `~/.ssh/bootstrapper` (private key) and `~/.ssh/bootstrapper.pub` do not exist → generate ed25519 keypair without passphrase.
- If private key exists but public key is missing → regenerate public key from private key.
- If public key exists but private key is missing (orphaned key):
  - In interactive mode: prompt user to delete orphaned key or abort.
  - In `--unattended` mode: generate new timestamped keypair (`bootstrapper_<timestamp>`) to avoid data loss.
- Display public key and QR code (skipped in `--unattended` mode when key pre-exists).
- Wait for user confirmation after GitHub key registration (skipped in `--unattended` mode when key pre-exists).
- Clone private repo into `~/setup-private` (shallow clone, single branch).
- Execute the provisioning script from the private repo with the given parameters.

## Principles
- **POSIX-shell compliant**: No bash-only features; script runs with `sh`.
- **Minimal dependencies**: Only `git`, `ssh-keygen`, and optionally `qrencode`.
- **No hardcoded paths**: Uses standard `$HOME`-based paths; SSH key path is configurable.
- **Idempotent**: Re-running should not break the system; existing keys are reused.
- **Separation of concerns**: Bootstrap script focuses on SSH key + repo cloning; full provisioning lives in private repo.
- **Safe defaults with overrides**: Flags allow customization (`--auto-install`, `--dry-run`, `--verbose`, `--unattended`, `--ssh-pub-key`).

## Flags and options
- `--auto-install` / `--no-install` — Allow or refuse automatic dependency installation.
- `--dry-run` — Simulate steps without modifying the system.
- `-v, --verbose` — Enable timestamps and POSIX tracing (`set -x`).
- `--unattended` — Skip all interactive prompts; suppress key display when key pre-exists; handle orphaned keys automatically.
- `--ssh-pub-key PATH` — Override SSH public key location (default: `~/.ssh/bootstrapper.pub`).

## How to use
On a fresh machine with git installed:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/<user>/machine-boostrapper/main/bootstrap.sh)" \
  -- [--auto-install] <git@github.com:user/setup-private.git> [branch] [script-path] [-- script-args...]
```

**Example with unattended mode:**
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/<user>/machine-boostrapper/main/bootstrap.sh)" \
  -- --auto-install --unattended git@github.com:user/setup-private.git main bootstrap.sh
```

## Development workflow

### Commit conventions
This project uses **Conventional Commits** with GitHub issue references (enforced via GitHub Rulesets):

```
<type>(<scope>): [gh-<issue>] <description>
```

**Allowed types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `devcontainer`, `conf`

**Examples:**
- `feat(bootstrap): [gh-1] add SSH key generation with QR code`
- `fix(deps): [gh-15] resolve path handling for spaces`
- `docs(readme): [gh-7] update installation instructions`

Use **Python-based commitizen-tools** (`pip install commitizen`) for interactive commit creation:
```bash
cz commit
```

Configuration lives in `_test/.cz.yaml` (copy to project root if needed for development).

### Branch naming conventions
Branch names must follow this pattern (enforced via GitHub Rulesets):

```
<type>/gh-<issue>_<description>
```

**Examples:**
- `feat/gh-1_add-ssh-key-generation`
- `fix/gh-15_resolve-path-handling`
- `docs/gh-7_update-installation-guide`

### Docker-based tooling
To avoid version mismatches and local installation complexity, contributors can use Docker aliases for development tools. See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed Docker alias setup:

```bash
# Commitizen via Docker
alias cz='docker run --rm -it -v "$PWD:/app" -w /app commitizen/commitizen:4.10.0'

# ShellCheck via Docker
alias shellcheck='docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:v0.11.0'
```

### GitHub Rulesets
Repository uses GitHub Rulesets to enforce:
1. **Commit message format** on `main` branch: `^(feat|fix|...)(\(.+\))?: \[gh-\d+\] .+$`
2. **Branch naming convention** on feature branches: `^(feat|fix|...)/gh-\d+_.+$`
3. **PR requirement**: Direct pushes to `main` are blocked; all changes must go through pull requests.
4. **Status checks**: ShellCheck CI must pass before merging.

Ruleset JSON files are in `_test/`:
- `github-ruleset-commit-message.json` — Commit message enforcement only
- `github-ruleset-branch-naming.json` — Branch naming enforcement
- `github-ruleset-full.json` — Complete ruleset with PR + status checks

### CI/CD workflows
- **ShellCheck** (`.github/workflows/shellcheck.yml`): Runs on every push/PR to validate POSIX shell compliance.
- **Release** (`.github/workflows/release.yml`): Auto-bumps version and creates GitHub release when PR merges to `main` (uses commitizen to determine version bump from conventional commits).

## Testing
```bash
# Syntax check
bash -n bootstrap.sh

# ShellCheck
shellcheck -s sh -S style bootstrap.sh

# Dry-run test
./bootstrap.sh --dry-run git@github.com:user/setup-private.git
```

## Contributing
See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed contribution guidelines, Docker-based tooling setup, and PR workflow.

IMPORTANT: Always remember to update this file to be consistent with the repository.
