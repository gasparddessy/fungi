#!/usr/bin/env bash
# Password fallback. Prefer SFTP_KEY. This uses rsync over SSH on SFTP_PORT
# (default 22), which is the same SSH service o2switch uses for SFTP.
# SamKirkland/FTP-Deploy-Action v4 speaks FTP/FTPS only, so it is not used.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$script_dir/log.sh"
# shellcheck disable=SC1091
source "$script_dir/rsync-flags.sh"

: "${SFTP_HOST:?}"
: "${SFTP_USER:?}"
: "${SFTP_PASSWORD:?}"
: "${THEME_PATH:?}"
port="${SFTP_PORT:-22}"
deploy_plugin="${DEPLOY_PLUGIN:-false}"

# These values are interpolated into an ssh command line. Reject anything
# that is not a hostname, account name, or port before opening a connection.
if ! printf '%s' "$SFTP_HOST" | grep -Eq '^[A-Za-z0-9.-]+$'; then
	say_error "SFTP_HOST must be a hostname or IP, without a scheme or path."
	exit 1
fi
if ! printf '%s' "$SFTP_USER" | grep -Eq '^[A-Za-z0-9._-]+$'; then
	say_error "SFTP_USER contains characters that are not allowed."
	exit 1
fi
if ! printf '%s' "$port" | grep -Eq '^[0-9]+$' || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
	say_error "SFTP_PORT must be a TCP port from 1 to 65535."
	exit 1
fi

if ! command -v sshpass >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
	sudo DEBIAN_FRONTEND=noninteractive apt-get update
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y sshpass rsync
fi

theme_path=$(bash "$script_dir/validate-deploy-target.sh" theme "$THEME_PATH")

export SSHPASS="$SFTP_PASSWORD"

ssh_cmd=(
	sshpass -e ssh
	-p "$port"
	-o IdentitiesOnly=yes
	-o PreferredAuthentications=password
	-o PubkeyAuthentication=no
	-o StrictHostKeyChecking=accept-new
	-o ConnectTimeout=20
)

echo "Checking remote theme directory before sync."
"${ssh_cmd[@]}" "${SFTP_USER}@${SFTP_HOST}" bash -s -- "$theme_path" <"$script_dir/remote-target-guard.sh"

repo_root=$(cd "$script_dir/../.." && pwd)

rsync_into() {
	local source_dir="$1"
	local remote_path="$2"
	# shellcheck disable=SC2086
	sshpass -e rsync $RSYNC_DELETE_FLAGS \
		--exclude node_modules/ \
		--exclude .git/ \
		--exclude .github/ \
		-e "ssh -p ${port} -o IdentitiesOnly=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20" \
		"${source_dir%/}/" \
		"${SFTP_USER}@${SFTP_HOST}:${remote_path}"
}

echo "Syncing child theme to ${theme_path}"
rsync_into "$repo_root/themes/refungi-child" "$theme_path"

if [ "$deploy_plugin" = "true" ]; then
	plugin_path=$(bash "$script_dir/validate-deploy-target.sh" plugin "${PLUGIN_PATH:-}")
	echo "Checking remote plugin directory before sync."
	"${ssh_cmd[@]}" "${SFTP_USER}@${SFTP_HOST}" bash -s -- "$plugin_path" <"$script_dir/remote-target-guard.sh"
	echo "Syncing custom plugin to ${plugin_path}"
	rsync_into "$repo_root/plugins/refungi-custom" "$plugin_path"
else
	echo "SFTP_REMOTE_PLUGIN_PATH is unset. Custom plugin was not synced."
fi

unset SSHPASS
