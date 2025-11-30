#!/usr/bin/env sh
# ==============================================================================
# machine-bootstrapper - Bootstrap Script for Fresh Machine Setup
# ==============================================================================
# Description:
#   Minimal bootstrap script to initialize a fresh Linux/macOS machine by:
#   - Generating a dedicated SSH key (default: ~/.ssh/bootstrapper)
#   - Displaying public key + QR code for GitHub registration
#   - Cloning a private provisioning repository
#   - Executing a provisioning script from the private repo
#
# Requirements:
#   - git (must be pre-installed)
#   - ssh-keygen (can be auto-installed)
#   - qrencode (optional, for QR code output)
#
# Usage:
#   sh bootstrap.sh [OPTIONS] --repo <git-ssh-url> [-- script-args]
#
# Required:
#   --repo URL        Git SSH URL of the private provisioning repository
#
# Options:
#   --branch NAME     Branch to clone (default: main)
#   --script PATH     Provisioning script path (default: bootstrap.sh)
#   --ssh-pub-key PATH  SSH public key path (default: ~/.ssh/bootstrapper.pub)
#   --sudo-script     Run provisioning script with sudo (default: no)
#   --auto-install    Automatically install missing dependencies
#   --no-install      Never install dependencies (fail if missing)
#   --dry-run         Simulate actions without making changes
#   -v, --verbose     Enable tracing and timestamped logs
#   --unattended      Skip all interactive prompts
#   -h, --help        Show usage information
#
# Examples:
#   sh bootstrap.sh --repo git@github.com:user/setup-private.git
#   sh bootstrap.sh --auto-install --repo git@github.com:user/setup.git --branch develop --script scripts/setup.sh
#   sh bootstrap.sh --unattended --auto-install --repo git@github.com:user/setup.git -- --custom-flag
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing dependencies, invalid arguments, script failure)
#
# Notes:
#   - POSIX-compliant (no bash-specific features)
#   - Idempotent (safe to re-run)
#   - Supports unattended/CI execution with --unattended flag
#
# Author: Ryher<ryther-github.fencing812@passmail.net>
# Repository: https://github.com/Ryther/machine-bootstrapper
# Version: 3.2.0
# License: See LICENSE file in repository
# ==============================================================================

set -eu

# ==============================================================================
# FUNCTION: get_script_version
# Extract script version from header comment
# ==============================================================================
get_script_version() {
  # Reads the first occurrence of '# Version: X.Y.Z' from this script file
  SCRIPT_PATH_SELF="$0"
  if [ "${SCRIPT_PATH_SELF#/}" != "$SCRIPT_PATH_SELF" ]; then
    SRC="$SCRIPT_PATH_SELF"
  else
    # If invoked via relative path, resolve to absolute for grep
    SRC="$(cd "$(dirname "$SCRIPT_PATH_SELF")" 2>/dev/null && pwd)/$(basename "$SCRIPT_PATH_SELF")"
  fi
  VER_LINE=$(grep -m1 "^# Version: " "$SRC" 2>/dev/null || true)
  printf "%s" "${VER_LINE#'# Version: '}"
}

# ==============================================================================
# FUNCTION: generate_bootstrapper_key_path
# Generate a timestamped SSH key path for orphaned key scenarios
#
# Description:
#   Creates a unique SSH public key path using current timestamp to avoid
#   conflicts when an orphaned public key exists without its private counterpart.
#   Used only in --unattended mode.
#
# Returns:
#   String: Path to timestamped public key (~/.ssh/bootstrapper_YYYYMMDDTHHMMSS.pub)
# ==============================================================================
generate_bootstrapper_key_path() {
  STAMP="$(date "+%Y%m%dT%H%M%S")"
  printf "%s/.ssh/bootstrapper_%s.pub" "$HOME" "$STAMP"
}

# ==============================================================================
# CONFIGURATION: Global defaults and state variables
# ==============================================================================
DEFAULT_BRANCH="main"
DEFAULT_TARGET_DIR="$HOME/setup-private"
DEFAULT_SCRIPT_PATH="bootstrap.sh"
DEFAULT_SSH_PUB_KEY_PATH="$HOME/.ssh/bootstrapper.pub"
REQUIRED_TOOLS="ssh-keygen"
OPTIONAL_TOOLS="qrencode"

INSTALL_MODE="prompt" # prompt|yes|no
DRY_RUN=0
VERBOSE=0
APT_UPDATED=0
SUDO_BIN=""
SSH_PUB_KEY_PATH="$DEFAULT_SSH_PUB_KEY_PATH"
UNATTENDED=0
SSH_KEY_PREEXISTING=0
SUDO_SCRIPT=0
PROVISIONING_TAG=""

# ==============================================================================
# FUNCTION: usage
# Display help message and exit
#
# Description:
#   Prints script usage information including all available flags,
#   arguments, and usage examples.
# ==============================================================================
usage() {
  printf "%s\n" "Usage: $0 [OPTIONS] --repo <git-ssh-url> [-- script-args ...]"
  printf "%s\n" ""
  printf "%s\n" "Required:"
  printf "%s\n" "  --repo URL        Git SSH URL of the private provisioning repository"
  printf "%s\n" ""
  printf "%s\n" "Options:"
  printf "%s\n" "  --branch NAME     Branch to clone (default: main)"
  printf "%s\n" "  --script PATH     Provisioning script path (default: bootstrap.sh)"
  printf "%s\n" "  --ssh-pub-key PATH  SSH public key path (default: ~/.ssh/bootstrapper.pub)"
  printf "%s\n" "  --sudo-script     Run provisioning script with sudo (default: no)"
  printf "%s\n" "  --auto-install    Automatically install missing dependencies"
  printf "%s\n" "  --no-install      Never install dependencies automatically (fail if missing)"
  printf "%s\n" "  --dry-run         Describe actions without making changes"
  printf "%s\n" "  -v, --verbose     Enable tracing and timestamped logs"
  printf "%s\n" "  --unattended      Skip all interactive confirmations"
  printf "%s\n" "  -h, --help        Show this help message"
  printf "%s\n" ""
  printf "%s\n" "Examples:"
  printf "%s\n" "  $0 --repo git@github.com:user/setup-private.git"
  printf "%s\n" "  $0 --auto-install --repo git@github.com:user/setup.git --branch develop --script scripts/setup.sh -- --flag value"
  exit 1
}

# ==============================================================================
# FUNCTION: log
# Centralized logging function with timestamp and level
#
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, DRY-RUN)
#   $@ - Log message components
#
# Description:
#   Logs messages with ISO 8601 timestamp and level prefix.
#   ERROR messages are sent to stderr.
#
# Examples:
#   log INFO "Starting bootstrap process"
#   log WARN "Optional tool missing"
#   log ERROR "Failed to generate SSH key"
#   log DRY-RUN "Would install package xyz"
# ==============================================================================
log() {
  if [ $# -lt 2 ]; then
    printf "log: missing level or message\n" >&2
    return 1
  fi

  LEVEL="$1"
  shift
  TIMESTAMP="$(date "+%Y-%m-%d %H:%M:%S")"
  MESSAGE="$*"

  case "$LEVEL" in
    ERROR)
      printf "%s [%s] %s\n" "$TIMESTAMP" "$LEVEL" "$MESSAGE" >&2
      ;;
    *)
      printf "%s [%s] %s\n" "$TIMESTAMP" "$LEVEL" "$MESSAGE"
      ;;
  esac
}

# ==============================================================================
# FUNCTION: should_skip_key_interaction
# Determine if SSH key display/prompts should be skipped
#
# Description:
#   Returns true (0) when running in unattended mode AND the SSH key
#   already existed before this script run. This avoids redundant
#   key display in CI/automation scenarios.
#
# Returns:
#   0 - Skip interaction (unattended + key pre-exists)
#   1 - Show interaction (interactive or new key)
# ==============================================================================
should_skip_key_interaction() {
  if [ "$UNATTENDED" -eq 1 ] && [ "$SSH_KEY_PREEXISTING" -eq 1 ]; then
    return 0
  fi
  return 1
}

# ==============================================================================
# FUNCTION: prompt_yes_no
# Interactive yes/no prompt for user confirmation
#
# Arguments:
#   $1 - Question to display
#
# Returns:
#   0 - User answered yes (y/Y)
#   1 - User answered no (n/N) or pressed Enter
# ==============================================================================
prompt_yes_no() {
  QUESTION="$1"
  while :; do
    printf "%s [y/N]: " "$QUESTION"
    if ! IFS= read -r ANSWER; then
      ANSWER=""
    fi
    case "$ANSWER" in
      y|Y) return 0 ;;
      n|N|"") return 1 ;;
      *) printf "%s\n" "Please answer y or n." ;;
    esac
  done
}

# ==============================================================================
# FUNCTION: ensure_ssh_key
# Generate or validate SSH keypair for bootstrapper
#
# Description:
#   Handles four scenarios:
#   1. Both keys exist: Mark as pre-existing and continue
#   2. Only private key exists: Regenerate public key from private
#   3. Only public key exists (orphaned): Prompt to delete or use timestamped key
#   4. Neither exists: Generate new ed25519 keypair
#
#   Sets SSH_KEY_PREEXISTING=1 when reusing existing keys.
#
# Returns:
#   0 - Success (key ready)
#   1 - Failure (orphaned key without resolution)
# ==============================================================================
ensure_ssh_key() {
  PRIVATE_KEY_PATH="$(private_key_from_pub "$SSH_PUB_KEY_PATH")"
  KEY_DIR="$(dirname "$PRIVATE_KEY_PATH")"

  PUB_EXISTS=0
  PRIV_EXISTS=0
  if [ -f "$SSH_PUB_KEY_PATH" ]; then
    PUB_EXISTS=1
  fi
  if [ -f "$PRIVATE_KEY_PATH" ]; then
    PRIV_EXISTS=1
  fi

  if [ "$PRIV_EXISTS" -eq 1 ] && [ "$PUB_EXISTS" -eq 1 ]; then
    SSH_KEY_PREEXISTING=1
    log INFO "SSH key pair ($PRIVATE_KEY_PATH / $SSH_PUB_KEY_PATH) already exists."
    return 0
  fi

  if [ "$PRIV_EXISTS" -eq 1 ] && [ "$PUB_EXISTS" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would derive public key $SSH_PUB_KEY_PATH from existing private key $PRIVATE_KEY_PATH."
      SSH_KEY_PREEXISTING=1
      return 0
    fi
    log INFO "Deriving missing public key $SSH_PUB_KEY_PATH from $PRIVATE_KEY_PATH."
    PUB_DIR="$(dirname "$SSH_PUB_KEY_PATH")"
    if [ "$PUB_DIR" != "." ] && [ "$PUB_DIR" != "/" ]; then
      mkdir -p "$PUB_DIR"
      chmod 700 "$PUB_DIR"
    fi
    ssh-keygen -y -f "$PRIVATE_KEY_PATH" > "$SSH_PUB_KEY_PATH"
    chmod 644 "$SSH_PUB_KEY_PATH"
    SSH_KEY_PREEXISTING=1
    return 0
  fi

  if [ "$PUB_EXISTS" -eq 1 ] && [ "$PRIV_EXISTS" -eq 0 ]; then
    if [ "$SSH_PUB_KEY_PATH" = "$DEFAULT_SSH_PUB_KEY_PATH" ] && [ "$UNATTENDED" -eq 1 ]; then
      SSH_PUB_KEY_PATH="$(generate_bootstrapper_key_path)"
      PRIVATE_KEY_PATH="$(private_key_from_pub "$SSH_PUB_KEY_PATH")"
      KEY_DIR="$(dirname "$PRIVATE_KEY_PATH")"
      log WARN "Detected orphaned bootstrapper public key; switching to $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)."
    else
      log ERROR "Found orphaned public key at $SSH_PUB_KEY_PATH without private key $PRIVATE_KEY_PATH. Remove it manually or rerun with --unattended to create bootstrapper_<timestamp>."
      exit 1
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would generate SSH key at $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)"
    return 0
  fi

  log INFO "Generating new SSH key at $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)..."
  if [ "$KEY_DIR" != "." ] && [ "$KEY_DIR" != "/" ]; then
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
  fi
  HOST_LABEL="$(derive_host_label)"
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY_PATH" -N "" -C "bootstrap-$HOST_LABEL"
}

# ==============================================================================
# FUNCTION: show_public_key
# Display SSH public key and QR code for GitHub registration
#
# Description:
#   Prints the public key content and generates a QR code (if qrencode available).
#   Skipped when running in unattended mode with pre-existing key.
# ==============================================================================
show_public_key() {
  if should_skip_key_interaction; then
    log INFO "Skipping public key display in unattended mode (key already present)."
    return 0
  fi

  if [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would display SSH public key at $SSH_PUB_KEY_PATH"
    fi
    return 0
  fi

  log INFO "Public SSH key (add this to GitHub from $SSH_PUB_KEY_PATH):"
  cat "$SSH_PUB_KEY_PATH"

  log INFO "QR code representation:"
  if command -v qrencode >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would render QR code via qrencode"
    else
      qrencode -t ANSIUTF8 < "$SSH_PUB_KEY_PATH"
    fi
  else
    log WARN "qrencode not available; install it for QR output."
  fi
}

# ==============================================================================
# FUNCTION: detect_pkg_manager
# Detect available package manager on the system
#
# Description:
#   Checks for common package managers in order of precedence:
#   apt, dnf, yum, pacman, zypper, brew
#
# Returns:
#   String: Package manager name (apt/dnf/yum/pacman/zypper/brew)
#   Exit code 1 if no supported package manager found
# ==============================================================================
detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf "%s" "apt"
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    printf "%s" "dnf"
    return 0
  fi
  if command -v yum >/dev/null 2>&1; then
    printf "%s" "yum"
    return 0
  fi
  if command -v pacman >/dev/null 2>&1; then
    printf "%s" "pacman"
    return 0
  fi
  if command -v zypper >/dev/null 2>&1; then
    printf "%s" "zypper"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    printf "%s" "brew"
    return 0
  fi
  return 1
}

# ==============================================================================
# FUNCTION: package_name_for_tool
# Map tool command name to package name for specific package manager
#
# Arguments:
#   $1 - Tool name (ssh-keygen, qrencode)
#   $2 - Package manager (apt, dnf, yum, pacman, zypper, brew)
#
# Returns:
#   String: Package name for the given tool and manager
#   Exit code 1 if tool/manager combination not supported
# ==============================================================================
package_name_for_tool() {
  TOOL="$1"
  MANAGER="$2"
  case "$MANAGER" in
    apt)
      case "$TOOL" in
        ssh-keygen) printf "%s" "openssh-client" ;;
        qrencode) printf "%s" "qrencode" ;;
        *) return 1 ;;
      esac
      ;;
    dnf|yum)
      case "$TOOL" in
        ssh-keygen) printf "%s" "openssh-clients" ;;
        qrencode) printf "%s" "qrencode" ;;
        *) return 1 ;;
      esac
      ;;
    pacman)
      case "$TOOL" in
        ssh-keygen) printf "%s" "openssh" ;;
        qrencode) printf "%s" "qrencode" ;;
        *) return 1 ;;
      esac
      ;;
    zypper)
      case "$TOOL" in
        ssh-keygen) printf "%s" "openssh" ;;
        qrencode) printf "%s" "qrencode" ;;
        *) return 1 ;;
      esac
      ;;
    brew)
      case "$TOOL" in
        ssh-keygen) printf "%s" "openssh" ;;
        qrencode) printf "%s" "qrencode" ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# ==============================================================================
# FUNCTION: ensure_apt_updated
# Run apt-get update once per script execution
#
# Description:
#   Ensures package index is updated before installing packages with apt.
#   Uses APT_UPDATED flag to avoid redundant updates.
# ==============================================================================
ensure_apt_updated() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would run apt-get update"
    else
      run_with_privilege apt-get update
    fi
    APT_UPDATED=1
  fi
}

# ==============================================================================
# FUNCTION: install_tool_with_manager
# Install a single tool using the specified package manager
#
# Arguments:
#   $1 - Tool name to install
#   $2 - Package manager to use
#
# Returns:
#   0 - Installation succeeded
#   1 - Installation failed or unsupported tool/manager
# ==============================================================================
install_tool_with_manager() {
  TOOL_TO_INSTALL="$1"
  MANAGER="$2"
  PACKAGE_NAME="$(package_name_for_tool "$TOOL_TO_INSTALL" "$MANAGER")" || return 1
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would install $TOOL_TO_INSTALL via $MANAGER ($PACKAGE_NAME)"
    return 0
  fi
  log INFO "Installing $TOOL_TO_INSTALL via $MANAGER ($PACKAGE_NAME)"
  case "$MANAGER" in
    apt)
      ensure_apt_updated
      run_with_privilege apt-get install -y "$PACKAGE_NAME"
      ;;
    dnf)
      run_with_privilege dnf install -y "$PACKAGE_NAME"
      ;;
    yum)
      run_with_privilege yum install -y "$PACKAGE_NAME"
      ;;
    pacman)
      run_with_privilege pacman -Sy --noconfirm "$PACKAGE_NAME"
      ;;
    zypper)
      run_with_privilege zypper --non-interactive install "$PACKAGE_NAME"
      ;;
    brew)
      brew install "$PACKAGE_NAME"
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# ==============================================================================
# FUNCTION: install_missing_tools
# Install multiple tools using detected package manager
#
# Arguments:
#   $1 - Space-separated list of tool names
#
# Returns:
#   0 - All tools installed successfully
#   1 - Installation failed for at least one tool
# ==============================================================================
install_missing_tools() {
  TOOLS="$1"
  if [ -z "$TOOLS" ]; then
    return 0
  fi

  MANAGER="$(detect_pkg_manager)" || {
    log ERROR "Automatic installation requested, but no supported package manager was detected."
    return 1
  }

  for TOOL in $TOOLS; do
    install_tool_with_manager "$TOOL" "$MANAGER" || return 1
  done

  return 0
}

# ==============================================================================
# FUNCTION: collect_missing_tools
# Identify missing required and optional tools
#
# Description:
#   Checks for presence of tools defined in REQUIRED_TOOLS and OPTIONAL_TOOLS.
#   Populates REQUIRED_MISSING and OPTIONAL_MISSING global variables.
# ==============================================================================
collect_missing_tools() {
  REQUIRED_MISSING=""
  OPTIONAL_MISSING=""

  for REQUIRED in $REQUIRED_TOOLS; do
    if ! command -v "$REQUIRED" >/dev/null 2>&1; then
      if [ -z "$REQUIRED_MISSING" ]; then
        REQUIRED_MISSING="$REQUIRED"
      else
        REQUIRED_MISSING="$REQUIRED_MISSING $REQUIRED"
      fi
    fi
  done

  for OPTIONAL in $OPTIONAL_TOOLS; do
    if ! command -v "$OPTIONAL" >/dev/null 2>&1; then
      if [ -z "$OPTIONAL_MISSING" ]; then
        OPTIONAL_MISSING="$OPTIONAL"
      else
        OPTIONAL_MISSING="$OPTIONAL_MISSING $OPTIONAL"
      fi
    fi
  done
}

# ==============================================================================
# FUNCTION: list_tools
# Print formatted list of tools
#
# Arguments:
#   $1 - Space-separated list of tool names
# ==============================================================================
list_tools() {
  TOOLS_TO_PRINT="$1"
  if [ -n "$TOOLS_TO_PRINT" ]; then
    for ITEM in $TOOLS_TO_PRINT; do
      printf "  - %s\n" "$ITEM"
    done
  fi
}

# ==============================================================================
# FUNCTION: fail_missing_tools
# Display missing tools error message and exit
#
# Description:
#   Lists missing required and optional tools, then exits with code 1.
# ==============================================================================
fail_missing_tools() {
  if [ -n "$REQUIRED_MISSING" ]; then
    log ERROR "Missing required tools:"
    list_tools "$REQUIRED_MISSING"
  fi
  if [ -n "$OPTIONAL_MISSING" ]; then
    log WARN "Missing optional tools (recommended):"
    list_tools "$OPTIONAL_MISSING"
  fi
  log ERROR "Install the tools listed above and run this script again."
  exit 1
}

# ==============================================================================
# FUNCTION: ensure_dependencies
# Check and optionally install missing dependencies
#
# Description:
#   Main dependency resolution function. Behavior depends on INSTALL_MODE:
#   - prompt: Ask user before installing
#   - yes: Auto-install without prompting
#   - no: Fail if any tools are missing
# ==============================================================================
ensure_dependencies() {
  collect_missing_tools
  if [ -z "$REQUIRED_MISSING" ] && [ -z "$OPTIONAL_MISSING" ]; then
    return 0
  fi

  if [ "$INSTALL_MODE" = "prompt" ] && [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would prompt before installing: $REQUIRED_MISSING $OPTIONAL_MISSING"
    return 0
  fi

  if [ "$INSTALL_MODE" = "prompt" ]; then
    if prompt_yes_no "Allow this script to install missing packages automatically?"; then
      INSTALL_MODE="yes"
    else
      fail_missing_tools
    fi
  fi

  if [ "$INSTALL_MODE" = "no" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would abort due to missing tools: $REQUIRED_MISSING"
    fi
    fail_missing_tools
  fi

  install_targets="$REQUIRED_MISSING"
  if [ -n "$OPTIONAL_MISSING" ]; then
    if [ -n "$install_targets" ]; then
      install_targets="$install_targets $OPTIONAL_MISSING"
    else
      install_targets="$OPTIONAL_MISSING"
    fi
  fi

  if [ -n "$install_targets" ]; then
    install_missing_tools "$install_targets" || fail_missing_tools
  fi

  collect_missing_tools
  if [ -n "$REQUIRED_MISSING" ]; then
    fail_missing_tools
  fi

  if [ -n "$OPTIONAL_MISSING" ]; then
    log WARN "Optional tooling missing (QR output skipped)."
  fi
}

# ==============================================================================
# FUNCTION: maybe_wait_for_confirmation
# Prompt user to press Enter before continuing
#
# Arguments:
#   $1 - Prompt message to display
#
# Description:
#   Skipped in unattended mode with pre-existing key or dry-run mode.
# ==============================================================================
maybe_wait_for_confirmation() {
  MESSAGE="$1"
  if should_skip_key_interaction; then
    log INFO "Skipping GitHub confirmation prompt in unattended mode (key already present)."
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would prompt: $MESSAGE"
    return 0
  fi
  printf "%s" "$MESSAGE"
  IFS= read -r _
}

# ==============================================================================
# FUNCTION: ensure_git_available
# Verify git is installed (required dependency)
#
# Description:
#   Checks for git availability. Exits with error if not found.
#   Git must be manually installed before running this script.
# ==============================================================================
ensure_git_available() {
  if ! command -v git >/dev/null 2>&1; then
    log ERROR "git not found. Install git manually before running this script."
    exit 1
  fi
}

# ==============================================================================
# FUNCTION: configure_sudo
# Detect and configure sudo for privilege escalation
#
# Description:
#   Sets SUDO_BIN to "sudo" if available, otherwise empty string.
# ==============================================================================
configure_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    SUDO_BIN="sudo"
  else
    SUDO_BIN=""
  fi
}

# ==============================================================================
# FUNCTION: derive_host_label
# Get hostname for SSH key comment
#
# Returns:
#   String: System hostname or "unknown" if unavailable
# ==============================================================================
derive_host_label() {
  if command -v hostname >/dev/null 2>&1; then
    hostname 2>/dev/null || printf "%s" "unknown"
  else
    printf "%s" "unknown"
  fi
}

# ==============================================================================
# FUNCTION: private_key_from_pub
# Derive private key path from public key path
#
# Arguments:
#   $1 - Public key path (e.g., ~/.ssh/bootstrapper.pub)
#
# Returns:
#   String: Private key path (e.g., ~/.ssh/bootstrapper)
# ==============================================================================
private_key_from_pub() {
  PUB_PATH="$1"
  case "$PUB_PATH" in
    *.pub)
      printf "%s" "${PUB_PATH%.pub}"
      ;;
    *)
      printf "%s" "$PUB_PATH"
      ;;
  esac
}

# ==============================================================================
# FUNCTION: clone_or_update_repo
# Clone or update the private provisioning repository
#
# Description:
#   If TARGET_DIR doesn't exist: clones REPO_URL (branch BRANCH) using shallow clone.
#   If TARGET_DIR exists: updates to latest version from remote (git pull).
#   Always ensures the repository is at the latest version before script execution.
# ==============================================================================
clone_or_update_repo() {
  TARGET_DIR="$DEFAULT_TARGET_DIR"
  PRIVATE_KEY_PATH="$(private_key_from_pub "$SSH_PUB_KEY_PATH")"

  if [ -d "$TARGET_DIR" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log DRY-RUN "Would update existing repository at $TARGET_DIR"
      return 0
    fi

    log INFO "Repository $TARGET_DIR already exists — updating to latest version..."

    # Change to repo directory and update
    cd "$TARGET_DIR"

    # Check if it's a valid git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      log ERROR "Directory $TARGET_DIR exists but is not a git repository."
      exit 1
    fi

    # Fetch latest and tags
    GIT_SSH_COMMAND="ssh -i $PRIVATE_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
      git fetch --tags origin "$BRANCH"

    if [ -n "$PROVISIONING_TAG" ]; then
      # Checkout specific tag (detached HEAD)
      git checkout -f "$PROVISIONING_TAG"
    else
      # Reset to remote branch (hard reset to ensure clean state)
      git reset --hard "origin/$BRANCH"
    fi

    log INFO "Repository updated to latest version."
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would clone $REPO_URL (branch $BRANCH) into $TARGET_DIR"
    return 0
  fi

  if [ -n "$PROVISIONING_TAG" ]; then
    log INFO "Cloning $REPO_URL (tag $PROVISIONING_TAG) into $TARGET_DIR"
    GIT_SSH_COMMAND="ssh -i $PRIVATE_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
      git clone --depth 1 "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    git fetch --tags
    git checkout -f "$PROVISIONING_TAG"
  else
    log INFO "Cloning $REPO_URL (branch $BRANCH) into $TARGET_DIR"
    GIT_SSH_COMMAND="ssh -i $PRIVATE_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
      git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
}

# ==============================================================================
# FUNCTION: resolve_target_script_path
# Convert script path to absolute path
#
# Description:
#   If SCRIPT_PATH is relative, prepends DEFAULT_TARGET_DIR.
#   If absolute, returns as-is.
#
# Returns:
#   String: Absolute path to target script
# ==============================================================================
resolve_target_script_path() {
  TARGET_DIR="$DEFAULT_TARGET_DIR"
  if [ "${SCRIPT_PATH#/}" = "$SCRIPT_PATH" ]; then
    printf "%s" "$TARGET_DIR/$SCRIPT_PATH"
  else
    printf "%s" "$SCRIPT_PATH"
  fi
}

# ==============================================================================
# FUNCTION: ensure_target_script_exists
# Verify target provisioning script exists
#
# Description:
#   Checks for existence of the script to be executed from the private repo.
#   Exits with error if not found (unless in dry-run mode).
# ==============================================================================
ensure_target_script_exists() {
  TARGET_SCRIPT="$(resolve_target_script_path)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY-RUN "Would run target script $TARGET_SCRIPT"
    return 0
  fi
  if [ ! -f "$TARGET_SCRIPT" ]; then
    log ERROR "Target script $TARGET_SCRIPT not found."
    exit 1
  fi
}

# ==============================================================================
# FUNCTION: execute_target_script
# Execute the provisioning script from the private repository
#
# Arguments:
#   $@ - Arguments to forward to the provisioning script
#
# Description:
#   Resolves script path to absolute, changes to target directory, then executes.
#   Runs with sudo only if --sudo-script flag was set.
#   In dry-run mode: prompts to execute provisioning script with --dry-run flag
#   (auto-accepts in unattended mode).
#   Attempts to execute script directly if executable, otherwise uses sh.
# ==============================================================================
execute_target_script() {
  TARGET_DIR="$DEFAULT_TARGET_DIR"
  if [ ! -d "$TARGET_DIR" ]; then
    log ERROR "Target directory $TARGET_DIR not available."
    exit 1
  fi

  # Always resolve to absolute path for consistent execution
  RUN_SCRIPT="$(resolve_target_script_path)"

  # Change to target directory (some scripts may expect to run from their own directory)
  cd "$TARGET_DIR"

  # Handle dry-run mode: ask if provisioning script should be executed with --dry-run
  if [ "$DRY_RUN" -eq 1 ]; then
    RUN_PROVISIONING=0
    if [ "$UNATTENDED" -eq 1 ]; then
      log INFO "Dry-run mode: automatically executing provisioning script with --dry-run flag (unattended)."
      RUN_PROVISIONING=1
    else
      if prompt_yes_no "Dry-run mode: execute provisioning script with --dry-run flag?"; then
        RUN_PROVISIONING=1
      else
        log INFO "Skipping provisioning script execution in dry-run mode."
        return 0
      fi
    fi

    if [ "$RUN_PROVISIONING" -eq 1 ]; then
      log INFO "Executing provisioning script in dry-run mode: $RUN_SCRIPT --dry-run"
      if [ "$SUDO_SCRIPT" -eq 1 ]; then
        log INFO "Running with sudo privilege"
      fi

      if [ -x "$RUN_SCRIPT" ]; then
        if [ "$SUDO_SCRIPT" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
          "$SUDO_BIN" "$RUN_SCRIPT" --dry-run "$@"
        else
          "$RUN_SCRIPT" --dry-run "$@"
        fi
      else
        if [ "$SUDO_SCRIPT" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
          "$SUDO_BIN" sh "$RUN_SCRIPT" --dry-run "$@"
        else
          sh "$RUN_SCRIPT" --dry-run "$@"
        fi
      fi
    fi
    return 0
  fi

  # Normal execution (not dry-run)
  log INFO "Executing provisioning script: $RUN_SCRIPT"
  if [ "$SUDO_SCRIPT" -eq 1 ]; then
    log INFO "Running with sudo privilege"
  fi

  if [ -x "$RUN_SCRIPT" ]; then
    if [ "$SUDO_SCRIPT" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
      "$SUDO_BIN" "$RUN_SCRIPT" "$@"
    else
      "$RUN_SCRIPT" "$@"
    fi
  else
    if [ "$SUDO_SCRIPT" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
      "$SUDO_BIN" sh "$RUN_SCRIPT" "$@"
    else
      sh "$RUN_SCRIPT" "$@"
    fi
  fi
}

# ==============================================================================
# FUNCTION: main
# Main entry point - parse arguments and orchestrate bootstrap process
#
# Arguments:
#   $@ - Command-line arguments
#
# Description:
#   1. Parse command-line flags and arguments
#   2. Validate git availability
#   3. Configure sudo
#   4. Ensure dependencies (ssh-keygen, qrencode)
#   5. Generate/validate SSH keypair
#   6. Display public key and wait for GitHub registration
#   7. Clone private provisioning repository
#   8. Execute target provisioning script with forwarded arguments
# ==============================================================================
main() {
  REPO_URL=""
  BRANCH="$DEFAULT_BRANCH"
  SCRIPT_PATH="$DEFAULT_SCRIPT_PATH"

  while [ $# -gt 0 ]; do
    case "$1" in
      --repo)
        if [ $# -lt 2 ]; then
          log ERROR "--repo requires a URL argument."
          usage
        fi
        REPO_URL="$2"
        shift 2
        ;;
      --repo=*)
        REPO_URL="${1#*=}"
        shift
        ;;
      --branch)
        if [ $# -lt 2 ]; then
          log ERROR "--branch requires a branch name argument."
          usage
        fi
        BRANCH="$2"
        shift 2
        ;;
      --branch=*)
        BRANCH="${1#*=}"
        shift
        ;;
      --script)
        if [ $# -lt 2 ]; then
          log ERROR "--script requires a path argument."
          usage
        fi
        SCRIPT_PATH="$2"
        shift 2
        ;;
      --script=*)
        SCRIPT_PATH="${1#*=}"
        shift
        ;;
      --provisioning-tag)
        if [ $# -lt 2 ]; then
          log ERROR "--provisioning-tag requires a tag name argument."
          usage
        fi
        PROVISIONING_TAG="$2"
        shift 2
        ;;
      --provisioning-tag=*)
        PROVISIONING_TAG="${1#*=}"
        shift
        ;;
      --sudo-script)
        SUDO_SCRIPT=1
        shift
        ;;
      --auto-install)
        INSTALL_MODE="yes"
        shift
        ;;
      --no-install)
        INSTALL_MODE="no"
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      --unattended)
        UNATTENDED=1
        shift
        ;;
      --ssh-pub-key)
        if [ $# -lt 2 ]; then
          log ERROR "--ssh-pub-key requires a path argument."
          usage
        fi
        SSH_PUB_KEY_PATH="$2"
        shift 2
        ;;
      --ssh-pub-key=*)
        SSH_PUB_KEY_PATH="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        ;;
      --)
        shift
        break
        ;;
      --*)
        log ERROR "Unknown option: $1"
        usage
        ;;
      *)
        log ERROR "Unexpected argument: $1"
        log ERROR "Use --repo to specify the repository URL."
        usage
        ;;
    esac
  done

  # Validate required parameters
  if [ -z "$REPO_URL" ]; then
    log ERROR "Missing required parameter: --repo"
    usage
  fi

  if [ -z "$SSH_PUB_KEY_PATH" ]; then
    log ERROR "SSH public key path cannot be empty."
    exit 1
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    set -x
  fi

  ensure_git_available
  configure_sudo
  ensure_dependencies
  ensure_ssh_key
  # Show running version
  log INFO "Bootstrapper version: $(get_script_version)"
  show_public_key
  maybe_wait_for_confirmation "Once you added the key to GitHub, press ENTER to continue..."
  clone_or_update_repo
  ensure_target_script_exists

  execute_target_script "$@"
}

main "$@"
