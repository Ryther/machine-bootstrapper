# machine-boostrapper — Copilot instructions

## Purpose
This repository contains a minimal bootstrap script to initialise a fresh Linux machine:
- generate an SSH key (if missing),
- display public key + QR for easy copy to GitHub,
- clone a private provisioning repository (setup-private),
- run a script from the private repo to setup the full environment.

## Requirements
- git must already exist on the system.
- ssh-keygen must be available (the script asks if it should install it).
- optionally qrencode for QR output (the script asks if it should install it; if absent, prints public key plain).
- a private Git repository accessible via SSH.

## Script behaviour
- If ~/.ssh/id_ed25519 does not exist → create ed25519 keypair without passphrase.
- Print public key and QR code (or plain key if qrencode missing).
- Wait for user confirmation (ENTER) after GitHub key registration.
- Clone private repo into ~/setup-private (shallow clone, single branch).
- Execute the provisioning script from the private repo with the given parameters, with root privileges if possible.

## Principles
- Script must be POSIX-shell compliant (no bash-only features).
- Minimal external dependencies.
- No hardcoded user names or paths except standard HOME-based.
- Idempotent: re-running should not break system.
- Separation of concerns: bootstrap only; further provisioning in private repo.

## How to use
On a fresh machine with git installed:
→ `sh -c "$(curl -fsSL https://raw.githubusercontent.com/<user>/machine-boostrapper/bootstrap.sh)" -- <git@github.com:user/setup-private.git> [branch] [script-location-in-private-repo] [script-args...]`

IMPORTANT: Always remember to update this file to be consistent with the repository.
