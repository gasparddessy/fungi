#!/usr/bin/env bash
# Confirm the remote directory with the deploy key, before rsync runs.
# Usage: ssh-key-guard.sh REMOTE_PATH
# Env: SFTP_HOST SFTP_USER SFTP_KEY SFTP_PORT
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/log.sh"
target="${1:-}"

if [ -z "$target" ]; then
	say_error "ssh-key-guard.sh requires the remote path."
	exit 1
fi

: "${SFTP_HOST:?}"
: "${SFTP_USER:?}"
: "${SFTP_KEY:?}"
port="${SFTP_PORT:-22}"

keyfile=$(mktemp)
chmod 600 "$keyfile"
trap 'rm -f "$keyfile"' EXIT
printf '%s\n' "$SFTP_KEY" >"$keyfile"

ssh_bin=${SSH_BIN:-ssh}
"$ssh_bin" \
	-i "$keyfile" \
	-p "$port" \
	-o IdentitiesOnly=yes \
	-o BatchMode=yes \
	-o StrictHostKeyChecking=accept-new \
	-o ConnectTimeout=20 \
	"${SFTP_USER}@${SFTP_HOST}" \
	bash -s -- "$target" <"$script_dir/remote-target-guard.sh"
