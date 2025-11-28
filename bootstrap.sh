#!/usr/bin/env sh
set -eu

generate_bootstrapper_key_path() {
  STAMP="$(date "+%Y%m%dT%H%M%S")"
  printf "%s/.ssh/bootstrapper_%s.pub" "$HOME" "$STAMP"
}

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

usage() {
  printf "%s\n" "Usage: $0 [--auto-install|--no-install] [--dry-run] [--verbose] [--unattended] [--ssh-pub-key PATH] [--] <git-ssh-url> [branch] [script-path] [script-args ...]"
  printf "%s\n" "  --auto-install    Automatically install missing dependencies"
  printf "%s\n" "  --no-install      Never install dependencies automatically (fail if missing)"
  printf "%s\n" "  --dry-run         Describe actions without making changes"
  printf "%s\n" "  -v, --verbose     Enable tracing and timestamped logs"
  printf "%s\n" "  --unattended      Skip all interactive confirmations (required for orphaned key fallback)"
  printf "%s\n" "  --ssh-pub-key     Path to the SSH public key (default: $DEFAULT_SSH_PUB_KEY_PATH)"
  printf "%s\n" "  -h, --help        Show this help message"
  printf "%s\n" ""
  printf "%s\n" "Examples:"
  printf "%s\n" "  $0 git@github.com:user/setup-private.git"
  printf "%s\n" "  $0 --auto-install git@github.com:user/setup-private.git main scripts/setup.sh -- --flag value"
  exit 1
}

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_line() {
  LEVEL="$1"
  shift
  printf "%s [%s] %s\n" "$(timestamp)" "$LEVEL" "$*"
}

log_info() {
  log_line "INFO" "$*"
}

log_warn() {
  log_line "WARN" "$*"
}

log_error() {
  log_line "ERROR" "$*" >&2
}

log_dryrun() {
  log_line "DRY-RUN" "$*"
}

should_skip_key_interaction() {
  if [ "$UNATTENDED" -eq 1 ] && [ "$SSH_KEY_PREEXISTING" -eq 1 ]; then
    return 0
  fi
  return 1
}

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
    log_info "SSH key pair ($PRIVATE_KEY_PATH / $SSH_PUB_KEY_PATH) already exists."
    return 0
  fi

  if [ "$PRIV_EXISTS" -eq 1 ] && [ "$PUB_EXISTS" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log_dryrun "Would derive public key $SSH_PUB_KEY_PATH from existing private key $PRIVATE_KEY_PATH."
      SSH_KEY_PREEXISTING=1
      return 0
    fi
    log_info "Deriving missing public key $SSH_PUB_KEY_PATH from $PRIVATE_KEY_PATH."
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
      log_warn "Detected orphaned bootstrapper public key; switching to $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)."
    else
      log_error "Found orphaned public key at $SSH_PUB_KEY_PATH without private key $PRIVATE_KEY_PATH. Remove it manually or rerun with --unattended to create bootstrapper_<timestamp>."
      exit 1
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would generate SSH key at $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)"
    return 0
  fi

  log_info "Generating new SSH key at $PRIVATE_KEY_PATH (public $SSH_PUB_KEY_PATH)..."
  if [ "$KEY_DIR" != "." ] && [ "$KEY_DIR" != "/" ]; then
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
  fi
  HOST_LABEL="$(derive_host_label)"
  ssh-keygen -t ed25519 -f "$PRIVATE_KEY_PATH" -N "" -C "bootstrap-$HOST_LABEL"
}

show_public_key() {
  if should_skip_key_interaction; then
    log_info "Skipping public key display in unattended mode (key already present)."
    return 0
  fi

  if [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log_dryrun "Would display SSH public key at $SSH_PUB_KEY_PATH"
    fi
    return 0
  fi

  log_info "Public SSH key (add this to GitHub from $SSH_PUB_KEY_PATH):"
  cat "$SSH_PUB_KEY_PATH"

  log_info "QR code representation:"
  if command -v qrencode >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log_dryrun "Would render QR code via qrencode"
    else
      qrencode -t ANSIUTF8 < "$SSH_PUB_KEY_PATH"
    fi
  else
    log_warn "qrencode not available; install it for QR output."
  fi
}

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

ensure_apt_updated() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log_dryrun "Would run apt-get update"
    else
      run_with_privilege apt-get update
    fi
    APT_UPDATED=1
  fi
}

install_tool_with_manager() {
  TOOL_TO_INSTALL="$1"
  MANAGER="$2"
  PACKAGE_NAME="$(package_name_for_tool "$TOOL_TO_INSTALL" "$MANAGER")" || return 1
  if [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would install $TOOL_TO_INSTALL via $MANAGER ($PACKAGE_NAME)"
    return 0
  fi
  log_info "Installing $TOOL_TO_INSTALL via $MANAGER ($PACKAGE_NAME)"
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

install_missing_tools() {
  TOOLS="$1"
  if [ -z "$TOOLS" ]; then
    return 0
  fi

  MANAGER="$(detect_pkg_manager)" || {
    log_error "Automatic installation requested, but no supported package manager was detected."
    return 1
  }

  for TOOL in $TOOLS; do
    install_tool_with_manager "$TOOL" "$MANAGER" || return 1
  done

  return 0
}

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

list_tools() {
  TOOLS_TO_PRINT="$1"
  if [ -n "$TOOLS_TO_PRINT" ]; then
    for ITEM in $TOOLS_TO_PRINT; do
      printf "  - %s\n" "$ITEM"
    done
  fi
}

fail_missing_tools() {
  if [ -n "$REQUIRED_MISSING" ]; then
    log_error "Missing required tools:"
    list_tools "$REQUIRED_MISSING"
  fi
  if [ -n "$OPTIONAL_MISSING" ]; then
    log_warn "Missing optional tools (recommended):"
    list_tools "$OPTIONAL_MISSING"
  fi
  log_error "Install the tools listed above and run this script again."
  exit 1
}

ensure_dependencies() {
  collect_missing_tools
  if [ -z "$REQUIRED_MISSING" ] && [ -z "$OPTIONAL_MISSING" ]; then
    return 0
  fi

  if [ "$INSTALL_MODE" = "prompt" ] && [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would prompt before installing: $REQUIRED_MISSING $OPTIONAL_MISSING"
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
      log_dryrun "Would abort due to missing tools: $REQUIRED_MISSING"
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
    log_warn "Optional tooling missing (QR output skipped)."
  fi
}

maybe_wait_for_confirmation() {
  MESSAGE="$1"
  if should_skip_key_interaction; then
    log_info "Skipping GitHub confirmation prompt in unattended mode (key already present)."
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would prompt: $MESSAGE"
    return 0
  fi
  printf "%s" "$MESSAGE"
  IFS= read -r _
}

ensure_git_available() {
  if ! command -v git >/dev/null 2>&1; then
    log_error "git not found. Install git manually before running this script."
    exit 1
  fi
}

configure_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    SUDO_BIN="sudo"
  else
    SUDO_BIN=""
  fi
}

derive_host_label() {
  if command -v hostname >/dev/null 2>&1; then
    hostname 2>/dev/null || printf "%s" "unknown"
  else
    printf "%s" "unknown"
  fi
}

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

clone_private_repo() {
  TARGET_DIR="$DEFAULT_TARGET_DIR"
  if [ -d "$TARGET_DIR" ]; then
    log_info "Directory $TARGET_DIR already exists — reusing."
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would clone $REPO_URL (branch $BRANCH) into $TARGET_DIR"
    return 0
  fi

  log_info "Cloning $REPO_URL (branch $BRANCH) into $TARGET_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
}

resolve_target_script_path() {
  TARGET_DIR="$DEFAULT_TARGET_DIR"
  if [ "${SCRIPT_PATH#/}" = "$SCRIPT_PATH" ]; then
    printf "%s" "$TARGET_DIR/$SCRIPT_PATH"
  else
    printf "%s" "$SCRIPT_PATH"
  fi
}

ensure_target_script_exists() {
  TARGET_SCRIPT="$(resolve_target_script_path)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log_dryrun "Would run target script $TARGET_SCRIPT"
    return 0
  fi
  if [ ! -f "$TARGET_SCRIPT" ]; then
    log_error "Target script $TARGET_SCRIPT not found."
    exit 1
  fi
}

execute_target_script() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi

  TARGET_DIR="$DEFAULT_TARGET_DIR"
  if [ ! -d "$TARGET_DIR" ]; then
    log_error "Target directory $TARGET_DIR not available."
    exit 1
  fi

  if [ "${SCRIPT_PATH#/}" = "$SCRIPT_PATH" ]; then
    cd "$TARGET_DIR"
    RUN_SCRIPT="$SCRIPT_PATH"
  else
    RUN_SCRIPT="$(resolve_target_script_path)"
  fi

  if [ -x "$RUN_SCRIPT" ]; then
    if [ -n "$SUDO_BIN" ]; then
      "$SUDO_BIN" "$RUN_SCRIPT" "$@"
    else
      "$RUN_SCRIPT" "$@"
    fi
  else
    if [ -n "$SUDO_BIN" ]; then
      "$SUDO_BIN" sh "$RUN_SCRIPT" "$@"
    else
      sh "$RUN_SCRIPT" "$@"
    fi
  fi
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
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
          log_error "--ssh-pub-key requires a path argument."
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
        log_error "Unknown option: $1"
        usage
        ;;
      *)
        break
        ;;
    esac
  done

  if [ $# -lt 1 ]; then
    usage
  fi

  REPO_URL="$1"
  shift

  if [ $# -gt 0 ]; then
    if [ "$1" = "--" ]; then
      BRANCH="$DEFAULT_BRANCH"
      shift
    else
      BRANCH="$1"
      shift
    fi
  else
    BRANCH="$DEFAULT_BRANCH"
  fi

  if [ $# -gt 0 ]; then
    if [ "$1" = "--" ]; then
      SCRIPT_PATH="$DEFAULT_SCRIPT_PATH"
      shift
    else
      SCRIPT_PATH="$1"
      shift
    fi
  else
    SCRIPT_PATH="$DEFAULT_SCRIPT_PATH"
  fi

  if [ $# -gt 0 ] && [ "$1" = "--" ]; then
    shift
  fi

  if [ -z "$SSH_PUB_KEY_PATH" ]; then
    log_error "SSH public key path cannot be empty."
    exit 1
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    set -x
  fi

  ensure_git_available
  configure_sudo
  ensure_dependencies
  ensure_ssh_key
  show_public_key
  maybe_wait_for_confirmation "Once you added the key to GitHub, press ENTER to continue..."
  clone_private_repo
  ensure_target_script_exists

  execute_target_script "$@"
}

main "$@"
