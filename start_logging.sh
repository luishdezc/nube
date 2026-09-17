
set -e
exec "$(dirname "$0")/scripts/send-logs.sh" "$@"
