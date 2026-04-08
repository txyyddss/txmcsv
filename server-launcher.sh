#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
cd "$SCRIPT_DIR"

DEFAULT_MIN_RAM="8G"
DEFAULT_MAX_RAM="8G"

error() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
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
    error "TXMCSV_MIN_RAM must be less than or equal to TXMCSV_MAX_RAM."
  fi
}

resolve_java_bin() {
  if [[ -n "${TXMCSV_JAVA_BIN:-}" ]]; then
    printf '%s\n' "$TXMCSV_JAVA_BIN"
    return 0
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    printf '%s\n' "${JAVA_HOME}/bin/java"
    return 0
  fi

  command -v java 2>/dev/null || true
}

parse_java_major() {
  local version="$1"
  local major

  if [[ "$version" == 1.* ]]; then
    major="${version#1.}"
  else
    major="$version"
  fi

  major="${major%%[^0-9]*}"
  printf '%s\n' "$major"
}

JAVA_BIN="$(resolve_java_bin)"
[[ -n "$JAVA_BIN" ]] || error "Java was not found. Set TXMCSV_JAVA_BIN or JAVA_HOME, or install Java 21+."
[[ -x "$JAVA_BIN" ]] || error "Java binary is not executable: $JAVA_BIN"
[[ -f "server.jar" ]] || error "server.jar was not found in $SCRIPT_DIR"

TXMCSV_MIN_RAM="$(normalize_jvm_size "${TXMCSV_MIN_RAM:-$DEFAULT_MIN_RAM}")"
TXMCSV_MAX_RAM="$(normalize_jvm_size "${TXMCSV_MAX_RAM:-$DEFAULT_MAX_RAM}")"
validate_heap_range "$TXMCSV_MIN_RAM" "$TXMCSV_MAX_RAM"

JAVA_VERSION="$("$JAVA_BIN" -version 2>&1 | awk -F '"' '/version/ { print $2; exit }')"
[[ -n "$JAVA_VERSION" ]] || error "Unable to detect Java version from $JAVA_BIN"

JAVA_MAJOR="$(parse_java_major "$JAVA_VERSION")"
[[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]] || error "Unable to parse Java version: $JAVA_VERSION"
(( JAVA_MAJOR >= 21 )) || error "Java 21 or newer is required. Current detected version: $JAVA_VERSION"

printf 'Using %s (Java %s)\n' "$JAVA_BIN" "$JAVA_VERSION"

jvm_opts=(
  "--add-modules=jdk.incubator.vector"
  "-Xms${TXMCSV_MIN_RAM}"
  "-Xmx${TXMCSV_MAX_RAM}"
  "-XX:+UseG1GC"
  "-XX:+ParallelRefProcEnabled"
  "-XX:MaxGCPauseMillis=200"
  "-XX:+UnlockExperimentalVMOptions"
  "-XX:+DisableExplicitGC"
  "-XX:+AlwaysPreTouch"
  "-XX:G1NewSizePercent=30"
  "-XX:G1MaxNewSizePercent=40"
  "-XX:G1HeapRegionSize=8M"
  "-XX:G1ReservePercent=20"
  "-XX:G1HeapWastePercent=5"
  "-XX:G1MixedGCCountTarget=4"
  "-XX:InitiatingHeapOccupancyPercent=15"
  "-XX:G1MixedGCLiveThresholdPercent=90"
  "-XX:G1RSetUpdatingPauseTimePercent=5"
  "-XX:SurvivorRatio=32"
  "-XX:+PerfDisableSharedMem"
  "-XX:MaxTenuringThreshold=1"
  "-Dusing.aikars.flags=https://mcflags.emc.gs"
  "-Daikars.new.flags=true"
  "-DLeaf.library-download-repo=https://maven.aliyun.com/repository/public"
  "-Dpaper.playerconnection.keepalive=180"
  "-Dpaper.disableWorldSymlinkValidation=true"
  "-Dgale.log.warning.root=false"
  "-Dgale.log.warning.offline.mode=false"
)

extra_opts=()
if [[ -n "${TXMCSV_EXTRA_JVM_OPTS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_opts=( ${TXMCSV_EXTRA_JVM_OPTS} )
fi

exec "$JAVA_BIN" "${jvm_opts[@]}" "${extra_opts[@]}" -jar server.jar nogui
