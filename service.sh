#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
PROJECT_DIR="$SCRIPT_DIR"
SERVICE_NAME="txmcsv"
UNIT_NAME="${SERVICE_NAME}.service"
UNIT_FILE="/etc/systemd/system/${UNIT_NAME}"
ENV_FILE="/etc/default/${SERVICE_NAME}"
TEMPLATE_FILE="${PROJECT_DIR}/txmcsv.service.template"
LAUNCHER_FILE="${PROJECT_DIR}/server-launcher.sh"

error() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  bash ./service.sh install [--user USER] [--group GROUP]
  bash ./service.sh uninstall
  bash ./service.sh start
  bash ./service.sh stop
  bash ./service.sh restart
  bash ./service.sh status
  bash ./service.sh logs [journalctl arguments...]
  bash ./service.sh enable
  bash ./service.sh disable
  bash ./service.sh memory <min_ram> <max_ram>

Examples:
  sudo bash ./service.sh install
  sudo bash ./service.sh install --user minecraft --group minecraft
  sudo bash ./service.sh memory 6G 8G
  bash ./service.sh logs -f
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "This command must be run as root."
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

normalize_jvm_size() {
  local size="${1^^}"
  if [[ ! "$size" =~ ^[1-9][0-9]*[KMGTP]$ ]]; then
    error "Invalid JVM heap size: $1"
  fi

  printf '%s\n' "$size"
}

size_to_bytes() {
  local size="$1"
  local value="${size%?}"
  local unit="${size: -1}"
  local multiplier=1

  case "$unit" in
    K) multiplier=$((1024)) ;;
    M) multiplier=$((1024 ** 2)) ;;
    G) multiplier=$((1024 ** 3)) ;;
    T) multiplier=$((1024 ** 4)) ;;
    P) multiplier=$((1024 ** 5)) ;;
    *) error "Unsupported JVM heap unit: $size" ;;
  esac

  printf '%s\n' "$(( value * multiplier ))"
}

validate_heap_range() {
  local min_ram="$1"
  local max_ram="$2"

  if (( "$(size_to_bytes "$min_ram")" > "$(size_to_bytes "$max_ram")" )); then
    error "Minimum heap must be less than or equal to maximum heap."
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}

quote_for_unit() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

default_runtime_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi

  id -un
}

default_runtime_group() {
  local runtime_user="$1"
  id -gn "$runtime_user"
}

ensure_runtime_identity() {
  local runtime_user="$1"
  local runtime_group="$2"

  id -u "$runtime_user" >/dev/null 2>&1 || error "User does not exist: $runtime_user"
  getent group "$runtime_group" >/dev/null 2>&1 || error "Group does not exist: $runtime_group"
}

ensure_project_files() {
  [[ -f "$TEMPLATE_FILE" ]] || error "Missing template file: $TEMPLATE_FILE"
  [[ -f "$LAUNCHER_FILE" ]] || error "Missing launcher file: $LAUNCHER_FILE"
}

ensure_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    return 0
  fi

  cat >"$ENV_FILE" <<'EOF'
# TXMCSV service environment
TXMCSV_MIN_RAM=8G
TXMCSV_MAX_RAM=8G
#TXMCSV_JAVA_BIN=/usr/bin/java
#TXMCSV_EXTRA_JVM_OPTS=
EOF
  chmod 0644 "$ENV_FILE"
}

update_env_value() {
  local key="$1"
  local value="$2"
  local tmp_file
  local found=0

  ensure_env_file
  tmp_file="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value" >>"$tmp_file"
      found=1
    else
      printf '%s\n' "$line" >>"$tmp_file"
    fi
  done <"$ENV_FILE"

  if [[ "$found" -eq 0 ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$tmp_file"
  fi

  install -m 0644 "$tmp_file" "$ENV_FILE"
  rm -f "$tmp_file"
}

render_unit_file() {
  local runtime_user="$1"
  local runtime_group="$2"
  local tmp_file

  tmp_file="$(mktemp)"

  sed \
    -e "s|__WORKING_DIRECTORY__|$(escape_sed_replacement "$(quote_for_unit "$PROJECT_DIR")")|g" \
    -e "s|__EXEC_START__|$(escape_sed_replacement "$(quote_for_unit "$LAUNCHER_FILE")")|g" \
    -e "s|__ENV_FILE__|$(escape_sed_replacement "$ENV_FILE")|g" \
    -e "s|__USER__|$(escape_sed_replacement "$runtime_user")|g" \
    -e "s|__GROUP__|$(escape_sed_replacement "$runtime_group")|g" \
    "$TEMPLATE_FILE" >"$tmp_file"

  install -m 0644 "$tmp_file" "$UNIT_FILE"
  rm -f "$tmp_file"
}

cmd_install() {
  local runtime_user
  local runtime_group
  local group_explicit=0

  require_root
  require_command systemctl
  require_command install
  require_command sed
  require_command getent
  ensure_project_files

  runtime_user="$(default_runtime_user)"
  runtime_group=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        [[ $# -ge 2 ]] || error "Missing value for --user"
        runtime_user="$2"
        shift 2
        ;;
      --group)
        [[ $# -ge 2 ]] || error "Missing value for --group"
        runtime_group="$2"
        group_explicit=1
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown install option: $1"
        ;;
    esac
  done

  if [[ "$group_explicit" -eq 0 ]]; then
    runtime_group="$(default_runtime_group "$runtime_user")"
  fi

  ensure_runtime_identity "$runtime_user" "$runtime_group"
  chmod 0755 "$LAUNCHER_FILE" "$PROJECT_DIR/service.sh"
  ensure_env_file
  render_unit_file "$runtime_user" "$runtime_group"

  systemctl daemon-reload
  systemctl enable "$UNIT_NAME"

  printf 'Installed %s\n' "$UNIT_NAME"
  printf 'Working directory: %s\n' "$PROJECT_DIR"
  printf 'Run user/group: %s:%s\n' "$runtime_user" "$runtime_group"
  printf 'Environment file: %s\n' "$ENV_FILE"
}

cmd_uninstall() {
  require_root
  require_command systemctl

  systemctl stop "$UNIT_NAME" >/dev/null 2>&1 || true
  systemctl disable "$UNIT_NAME" >/dev/null 2>&1 || true

  rm -f "$UNIT_FILE" "$ENV_FILE"

  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true

  printf 'Removed %s and %s\n' "$UNIT_FILE" "$ENV_FILE"
}

cmd_systemctl() {
  local action="$1"
  shift || true

  systemctl "$action" "$UNIT_NAME" "$@"
}

cmd_status() {
  systemctl status "$UNIT_NAME" --no-pager
}

cmd_logs() {
  if [[ $# -gt 0 ]]; then
    journalctl -u "$UNIT_NAME" "$@"
    return 0
  fi

  journalctl -u "$UNIT_NAME" -n 200 -e
}

cmd_memory() {
  local min_ram
  local max_ram

  require_root
  require_command systemctl
  require_command install
  [[ $# -eq 2 ]] || error "Usage: bash ./service.sh memory <min_ram> <max_ram>"

  min_ram="$(normalize_jvm_size "$1")"
  max_ram="$(normalize_jvm_size "$2")"
  validate_heap_range "$min_ram" "$max_ram"

  update_env_value "TXMCSV_MIN_RAM" "$min_ram"
  update_env_value "TXMCSV_MAX_RAM" "$max_ram"

  if systemctl is-active --quiet "$UNIT_NAME"; then
    systemctl restart "$UNIT_NAME"
    printf 'Updated heap to %s/%s and restarted %s\n' "$min_ram" "$max_ram" "$UNIT_NAME"
  else
    printf 'Updated heap to %s/%s in %s\n' "$min_ram" "$max_ram" "$ENV_FILE"
  fi
}

main() {
  local command="${1:-}"
  [[ -n "$command" ]] || {
    usage
    exit 1
  }
  shift || true

  case "$command" in
    install)
      cmd_install "$@"
      ;;
    uninstall)
      cmd_uninstall
      ;;
    start|stop|restart|enable|disable)
      require_root
      require_command systemctl
      cmd_systemctl "$command" "$@"
      ;;
    status)
      require_command systemctl
      cmd_status
      ;;
    logs)
      require_command journalctl
      cmd_logs "$@"
      ;;
    memory)
      cmd_memory "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      error "Unknown command: $command"
      ;;
  esac
}

main "$@"
