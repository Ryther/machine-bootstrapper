# machine-boostrapper
![Static Badge](https://img.shields.io/badge/version-3.5.3-blue?style=plastic)
[![ShellCheck](https://github.com/Ryther/machine-bootstrapper/actions/workflows/pipeline.yml/badge.svg?branch=main)](https://github.com/Ryther/machine-bootstrapper/actions/workflows/pipeline.yml?branch=main)

Public bootstrap for a fresh machine — prepares base environment, SSH key, clones a private repo, and runs its provisioning script.

> **Contributing?** See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, commit conventions, and tooling setup.

## 🚀 What is this

`machine-boostrapper` is a minimal, public bootstrap repository intended to:

- generate a dedicated SSH key (defaults to `~/.ssh/bootstrapper(.pub)`, configurable)
- display the public key + QR code for easy copy to GitHub
- clone a private `setup-private` repository
- execute a provisioning script from that private repo (defaults to `bootstrap.sh`, overridable per run)

This allows any fresh Linux/macOS install to become a workstation quickly while keeping sensitive configuration inside the private repo.

## 📦 Contents

- `bootstrap.sh` — the bootstrap script
- `.github/copilot-instructions.md` — instructions for AI assistance / future maintenance

## 🔧 Requirements

- `git` must already exist on the system (project policy).
- `ssh-keygen` is required; the bootstrapper can install it for you.
- `qrencode` is optional; when present it prints a QR code of the generated key.

When dependencies are missing the script asks whether it may install them. Answer “no” (or launch with `--no-install`) to see the list of commands and exit, or use `--auto-install` to approve installs up front. Pair any mode with `--unattended` when you need zero prompts, and `--dry-run` to preview the flow without making changes. Verbose mode (`--verbose`) timestamps each log line and enables POSIX tracing.

### Common install commands

| Platform | Command |
| --- | --- |
| Debian/Ubuntu | `sudo apt-get update && sudo apt-get install -y openssh-client qrencode` |
| Fedora/RHEL/CentOS | `sudo dnf install -y openssh-clients qrencode` (use `yum` on older releases) |
| Arch Linux | `sudo pacman -Sy --noconfirm openssh qrencode` |
| openSUSE | `sudo zypper install -y openssh qrencode` |
| macOS (Homebrew) | `brew install openssh qrencode` |

## 🎯 Usage

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Ryther/machine-boostrapper/main/bootstrap.sh)" \
  -- [OPTIONS] --repo <git@github.com:<your-user>/setup-private.git> [-- script-args...]
```

### Use a specific bootstrapper version

Run a specific tagged version by referencing the tag in the raw URL:

```bash
BOOTSTRAP_TAG=v3.2.0
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Ryther/machine-boostrapper/${BOOTSTRAP_TAG}/bootstrap.sh)" \
  -- --repo git@github.com:<your-user>/setup-private.git
```

You can also pin to a commit SHA:

```bash
COMMIT_SHA=0123456789abcdef...
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Ryther/machine-boostrapper/${COMMIT_SHA}/bootstrap.sh)" \
  -- --repo git@github.com:<your-user>/setup-private.git
```

### Required Parameters

- `--repo URL` — SSH URL to your private provisioning repository

### Optional Parameters

- `--branch NAME` — Branch to clone (default: `main`)
- `--provisioning-tag TAG` — Checkout a specific tag in the provisioning repository (overrides branch)
- `--script PATH` — Provisioning script path (default: `bootstrap.sh`)
- `--ssh-pub-key PATH` — SSH public key path (default: `~/.ssh/bootstrapper.pub`). The private key lives next to it (same filename without `.pub`)

### Flags

- `--auto-install` — Automatically install missing dependencies without prompting
- `--no-install` — Never install dependencies automatically (fail if missing)
- `--dry-run` — Simulate every step without modifying the machine
- `-v, --verbose` — Add timestamps to every log line and enable `set -x` tracing
- `--unattended` — Suppress all interactive confirmations; combine with `--auto-install` for fully non-interactive runs
- `-h, --help` — Show usage information

### Script Arguments

Arguments after `--` are forwarded verbatim to the provisioning script.

Our **baseline standard** assumes every `setup-private` repo exposes a root-level `bootstrap.sh`. Teams with different entry points can use `--script` to override without forking this public bootstrapper.

### Examples

Use project defaults:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/acme/machine-boostrapper/main/bootstrap.sh)" \
  -- --repo git@github.com:acme/setup-private.git
```

Custom branch, script, and arguments:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/acme/machine-boostrapper/main/bootstrap.sh)" \
  -- --auto-install --repo git@github.com:acme/setup-private.git --branch develop --script scripts/workstation.sh -- --with-gpu --timezone UTC
```

Fully unattended:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/acme/machine-boostrapper/main/bootstrap.sh)" \
  -- --unattended --auto-install --repo git@github.com:acme/setup.git
```

### SSH key naming

By default the script maintains `~/.ssh/bootstrapper` + `~/.ssh/bootstrapper.pub`. If both halves already exist they are reused as-is. When neither file exists, a new pair is generated in-place.

If the private key exists but the `.pub` is missing, the bootstrapper automatically recreates the public key (or describes it under `--dry-run`).

If an orphaned public key remains without its private counterpart, the bootstrapper stops with an error unless you opt into unattended mode (which then writes a fresh pair named `bootstrapper_<timestamp>`). This prevents accidental deletion yet still allows CI/automated runs to recover cleanly when requested.

## Flow
```mermaid
flowchart TB
A[Fresh install] --> B[Run bootstrap.sh]
B --> C{Dependencies<br/>available?}
C -->|missing| D[Install/prompt<br/>ssh-keygen, qrencode]
C -->|present| E{Bootstrapper<br/>keypair exists?}
D --> E

E -->|both missing| F[Generate new<br/>~/.ssh/bootstrapper]
E -->|only private| G[Regenerate .pub<br/>from private key]
E -->|only public<br/>orphaned| H{Unattended<br/>mode?}
H -->|yes| I[Generate timestamped<br/>bootstrapper_YYYYMMDD...]
H -->|no| J[Prompt: delete orphan<br/>or abort]
E -->|both present| K{Unattended +<br/>key pre-exists?}

F --> L[Show public key + QR]
G --> L
I --> L
J --> L
K -->|yes| M[Skip display/prompts]
K -->|no| L

L --> N[Wait for GitHub<br/>key registration]
M --> O[Clone setup-private]
N --> O
O --> P[Execute provisioning<br/>script from private repo]
P --> Q[System configured]

classDef process fill:#E0F2FE,stroke:#0F6ABF,color:#0A2C50,stroke-width:2px;
classDef decision fill:#FFF5E1,stroke:#E69100,color:#7A4100,stroke-width:2px;
classDef start fill:#DCFCE7,stroke:#15803D,color:#065F46,stroke-width:2px;
classDef finish fill:#F3E8FF,stroke:#7C3AED,color:#4C1D95,stroke-width:2px;

class B,D,F,G,I,J,L,M,N,O,P process;
class C,E,H,K decision;
class A start;
class Q finish;
```
