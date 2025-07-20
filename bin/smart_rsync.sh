#!/usr/bin/env bash
# Smart, user-friendly rsync wrapper for Synology-to-UNAS data-only transfers

set -euo pipefail

# Functions
ensure_dir() {
    local dir_name="$1"
    mkdir -p "$dir_name"
}

log_file_exists() {
    local log_file="$1"
    if [[ ! -f "$log_file" ]]; then
        echo "⚠️ Log file missing."
        return 1
    fi
    return 0
}

is_process_running() {
    local pid_file="$1"
    if [[ ! -f "$pid_file" ]]; then
      echo "⚠️ No recorded PID found at $pid_file"
      return 1
    fi
    local pid=$(cat "$pid_file")
    if ! ps -p "$pid" > /dev/null 2>&1; then
      echo "⚠️ Rsync PID found ($pid) but process not active."
      return 1
    fi
    return 0
}

# Replace rest of your code with function calls and restructured switch case...


# ─── CONFIGURABLE PATHS ───────────────────────────────────────────────────────
SRC="/volume1"
DEST="root@192.168.2.202:/var/nfs/shared/SynologyArchive/volume1"
SSH_OPTS="-o StrictHostKeyChecking=no"

LOG_DIR="/root/syno_rsync_logs"
LOG_FILE="${LOG_DIR}/rsync_$(date +%F_%H-%M).log"
PID_FILE="${LOG_DIR}/rsync.pid"

EXCLUDES=(
  --exclude='@*'
  --exclude='.snapshot/'
  --exclude='@eaDir/'
  )

RSYNC_OPTS=(
  -aPhS
  --append-verify
  --delete
  "${EXCLUDES[@]}"
  )

# ─── ENSURE LOG LOCATION ──────────────────────────────────────────────────────
ensure_dir "$LOG_DIR"
#mkdir -p "$LOG_DIR"

# ─── FLAGS ─────────────────────────────────────────────────────────────────────
case "${1:-}" in

        --probe)
            echo "🔍 Probing system setup..."
            echo "Source: $SRC"
            echo "Destination: $DEST"
            echo "Mounted Filesystems:"
            mount | grep -E "($SRC|${DEST%%:*})" || echo "  (none detected)"
            echo "Live Data Size:"
            du -sh "$SRC"
            echo "Disk Allocated:"
            df -h "$SRC"
            echo "Hidden/System Directories:"
            find "$SRC" -maxdepth 1 -type d \( -name '@*' -o -name '.snapshot*' \) -printf "  %f\n"
            echo "SSH Access:"
            ssh -o BatchMode=yes $SSH_OPTS "${DEST%%:*}" "echo ✅" || echo "❌ SSH failed"d

            echo "Suggested Command:"
            echo "smart_rsync.sh --sync"
            exit 0
            ;;

          --dry-run)
            echo "🔧 Running dry-run (preview only)..."
            rsync "${RSYNC_OPTS[@]}" -n --stats -e "ssh $SSH_OPTS" "$SRC/" "$DEST/"
            exit 0
            ;;

          --sync)
            echo "🚀 Starting real rsync… log: $LOG_FILE"
            nohup rsync "${RSYNC_OPTS[@]}" \
              -e "ssh $SSH_OPTS" \
              "$SRC/" "$DEST/" > "$LOG_FILE" 2>&1 &

            echo $! > "$PID_FILE"
            echo "✅ PID saved to $PID_FILE"
            echo "Monitor with:"
            echo "  tail -F $LOG_FILE"
            exit 0
            ;;

          --kill)
            if [[ -f "$PID_FILE" ]]; then
              PID=$(cat "$PID_FILE")
              if kill "$PID" 2>/dev/null; then
                echo "🛑 Killed rsync process $PID"
                rm -f "$PID_FILE"
              else
                echo "⚠️ Failed to kill process $PID—it may have finished already."
              fi
            else
              echo "⚠️ No recorded PID found at $PID_FILE"
            fi
            exit 0
            ;;

          --pid)
            if [[ -f "$PID_FILE" ]]; then
              PID=$(cat "$PID_FILE")
              if is_process_running "$PID_FILE"; then
                echo "📌 Rsync is running with PID: $PID"
              else
                echo "⚠️ PID $PID recorded, but no rsync process found. May have exited."
              fi
            else
              echo "⚠️ No PID file found. Has --sync been started?"
            fi
            exit 0
            ;;

          --status)
            if [[ -f "$PID_FILE" ]]; then
              PID=$(cat "$PID_FILE")
              if is_process_running "$PID_FILE"; then
                echo "✅ Rsync process $PID is running."
                echo "Latest progress:"
                LOG=$(ls -1t "$LOG_DIR"/rsync_*.log 2>/dev/null | head -n 1)
                if [[ -f "$LOG" ]]; then
                  tail -n 5 "$LOG"
                else
                  echo "⚠️ Log file not found."
                fi
              else
                echo "⚠️ Rsync PID found ($PID) but process not active."
                echo "It may have completed or failed. Check latest log:"
                LOG=$(ls -1t "$LOG_DIR"/rsync_*.log 2>/dev/null | head -n 1)
                [[ -f "$LOG" ]] && tail -n 5 "$LOG" || echo "⚠️ Log missing."
              fi
            else
              echo "⚠️ No PID recorded. Has --sync been started?"
            fi
            exit 0
            ;;

          --last-log)
            if [[ -f "$LOG_FILE" ]]; then
              echo "📄 Last 5 lines of $LOG_FILE:"
              tail -n 5 "$LOG_FILE"
            else
              echo "⚠️ No current log file found. You may not have run --sync yet."
            fi
            exit 0
            ;;

          *)
            echo "Usage:"
            echo "  smart_rsync.sh --probe     # Scan environment & suggest command"
            echo "  smart_rsync.sh --dry-run   # Show what would be transferred"
            echo "  smart_rsync.sh --sync      # Execute real transfer"
            echo "  smart_rsync.sh --kill      # Abort running rsync (if PID was saved)"
            exit 1
            ;;

      esac



