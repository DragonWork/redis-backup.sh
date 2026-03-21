#!/usr/bin/env bash
set -euo pipefail

VERSION="v0.2"

RETENTION=24 # default, configure with "--keep N"

PROG="$(basename "$0")"

usage() {
  cat << EOF
Usage: $PROG [OPTIONS]

Options:
  --keep N        Keep N newest backups (default: $RETENTION)
  -h, --help      Show this help and exit

Examples:
  $PROG --keep 10
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep)
      [ $# -ge 2 ] || {
        echo "--keep requires a value" >&2
        exit 1
      }
      RETENTION="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$RETENTION" in
  '' | *[!0-9]*)
    echo "--keep must be a non-negative integer" >&2
    exit 1
    ;;
esac

echo "               _ _            _                _                     _     "
echo "              | (_)          | |              | |                   | |    "
echo "  _ __ ___  __| |_ ___ ______| |__   __ _  ___| | ___   _ _ __   ___| |__  "
echo " | '__/ _ \\/ _\` | / __|______| '_ \\ / _\` |/ __| |/ / | | | '_ \\ / __| '_ \\ "
echo " | | |  __/ (_| | \\__ \\      | |_) | (_| | (__|   <| |_| | |_) |\\__ \\ | | |"
echo " |_|  \\___|\\__,_|_|___/      |_.__/ \\__,_|\\___|_|\\_\\\\__,_| .__(_)___/_| |_|"
echo "                                                         | |               "
echo "                                                         |_|               "
echo ""
echo "                                                            by DragonWork"
echo ""

# required tools
for cmd in xargs awk zstd; do
  command -v "$cmd" > /dev/null 2>&1 || {
    echo "Missing dependency: $cmd" >&2
    exit 1
  }
done

for cli in redis-cli valkey-cli keydb-cli; do
  if command -v "$cli" > /dev/null 2>&1; then
    REDIS_CLI="$(realpath "$(command -v "$cli")")"
    break
  fi
done

if [ -z "$REDIS_CLI" ]; then
  echo "Missing dependency: redis-cli / valkey-cli / keydb-cli" >&2
  exit 1
fi

REDIS_CLI_NAME="$(basename "$REDIS_CLI")"
REDIS_NAME="${REDIS_CLI_NAME%-cli}"
RDB_FILE="$(
  $REDIS_CLI --raw CONFIG GET dir dbfilename \
    | awk '
    $0=="dir" {getline; dir=$0}
    $0=="dbfilename" {getline; file=$0}
    END {print dir "/" file}
  '
)"

BACKUP_DIR="/var/backups/$REDIS_NAME"
mkdir -p "$BACKUP_DIR"

echo "     ***** redis-backup.sh $VERSION (using $REDIS_CLI_NAME) for $REDIS_NAME *****"

timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
dest="$BACKUP_DIR/dump-$timestamp.rdb.zst"

echo "Starting $REDIS_NAME backup at $(date)"

# Capture current save state
lastsave_before=$($REDIS_CLI LASTSAVE)

echo "Triggering BGSAVE"
$REDIS_CLI BGSAVE > /dev/null

spinner='|/-\'
i=0
while true; do
  in_progress=$($REDIS_CLI INFO persistence | awk -F: '/rdb_bgsave_in_progress/ {print $2}' | tr -d '\r')

  if [[ "$in_progress" == "0" ]]; then
    printf "\rBGSAVE finished            \n"
    break
  fi

  printf "\rWaiting for BGSAVE... %c" "${spinner:i++%${#spinner}:1}"
  sleep 0.25
done

# Verify success
status=$($REDIS_CLI INFO persistence | awk -F: '/rdb_last_bgsave_status/ {print $2}' | tr -d '\r')

if [[ "$status" != "ok" ]]; then
  echo "[ERROR] BGSAVE failed"
  exit 1
fi

lastsave_after=$($REDIS_CLI LASTSAVE)

if [[ "$lastsave_after" -le "$lastsave_before" ]]; then
  echo "[ERROR] LASTSAVE did not advance"
  exit 1
fi

echo "BGSAVE completed successfully"
echo "Copying and compressing dump.rdb → $dest"

(umask 077 && zstd -T0 -6 -c "$RDB_FILE" > "$dest")

echo "Backup finished successfully"

# Retention: keep newest $RETENTION backups
old=$(ls -1t "$BACKUP_DIR"/dump-*.rdb.zst 2> /dev/null | tail -n +$((RETENTION + 1)))

if [ -n "$old" ]; then
  count=$(echo "$old" | wc -l)
  echo "Deleting $count old backup(s)"
  echo "$old" | xargs -r rm --
else
  echo "No old backups to delete"
fi

exit 0
