#!/usr/bin/env bash
set -euo pipefail
cd /home/mtnserver/nvme/MTN
JAVA_BIN=${JAVA_BIN:-/usr/local/java/bin/java}
LPT_MIN_RAM=${LPT_MIN_RAM:-8G}
LPT_MAX_RAM=${LPT_MAX_RAM:-12G}
exec $JAVA_BIN \
  -Xms$LPT_MIN_RAM -Xmx$LPT_MAX_RAM \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=150 \
  -XX:+ParallelRefProcEnabled \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -jar server.jar --nogui
