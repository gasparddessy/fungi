#!/usr/bin/env bash
# Local and CI checks for the deploy guards. No network and no real secrets.
set -euo pipefail

# Keep intentional failures from showing up as GitHub Actions error annotations.
export REFUGI_SUPPRESS_ANNOTATIONS=1

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
cd "$repo_root"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for script in \
	.github/scripts/log.sh \
	.github/scripts/validate-deploy-target.sh \
	.github/scripts/remote-target-guard.sh \
	.github/scripts/deploy-preflight.sh \
	.github/scripts/ssh-key-guard.sh \
	.github/scripts/sftp-password-deploy.sh \
	.github/scripts/ftp-password-deploy.sh \
	.github/scripts/rsync-flags.sh
do
	bash -n "$script"
done

validate="$script_dir/validate-deploy-target.sh"
guard="$script_dir/remote-target-guard.sh"
preflight="$script_dir/deploy-preflight.sh"

pass=0
expect_ok() {
	local kind="$1" input="$2" expected="$3" got
	if ! got=$(bash "$validate" "$kind" "$input"); then
		fail "expected ${kind} path to be accepted: ${input}"
	fi
	[ "$got" = "$expected" ] || fail "path normalize mismatch for [${input}]: got [${got}] want [${expected}]"
	pass=$((pass + 1))
}

expect_bad() {
	local kind="$1" input="$2"
	if bash "$validate" "$kind" "$input" >/dev/null 2>&1; then
		fail "expected ${kind} path to be rejected: ${input}"
	fi
	pass=$((pass + 1))
}

expect_ok theme "public_html/wp-content/themes/refungi-child" "public_html/wp-content/themes/refungi-child/"
expect_ok theme "/home/crch2121/public_html/wp-content/themes/refungi-child/" "/home/crch2121/public_html/wp-content/themes/refungi-child/"
expect_ok theme "./public_html/wp-content/themes/refungi-child" "public_html/wp-content/themes/refungi-child/"
expect_ok theme "wp-content/themes/refungi-child" "wp-content/themes/refungi-child/"
expect_ok plugin "public_html/wp-content/plugins/refungi-custom/" "public_html/wp-content/plugins/refungi-custom/"
expect_ok plugin "/home/crch2121/public_html/wp-content/plugins/refungi-custom" "/home/crch2121/public_html/wp-content/plugins/refungi-custom/"

expect_bad theme ""
expect_bad theme "/"
expect_bad theme "public_html"
expect_bad theme "public_html/"
expect_bad theme "public_html/wp-content"
expect_bad theme "public_html/wp-content/themes"
expect_bad theme "public_html/wp-content/themes/"
expect_bad theme "public_html/wp-content/themes/bridge"
expect_bad theme "public_html/wp-content/themes/bridge/"
expect_bad theme "public_html/wp-content/themes/bridge-child"
expect_bad theme "public_html/wp-content/themes/bridge-child/"
expect_bad theme "public_html/wp-content/themes/refungi-child/extra"
expect_bad theme "public_html/wp-content/themes/refungi-child-old"
expect_bad theme "public_html/wp-content/themes/refungi-child/../../public_html"
expect_bad theme "public_html//wp-content/themes/refungi-child"
expect_bad theme "public_html/wp-content/themes/refungi-child;rm"
expect_bad theme "public_html/wp content/themes/refungi-child"
expect_bad theme "public_html/wp-content/plugins/refungi-custom"
expect_bad plugin ""
expect_bad plugin "public_html/wp-content/plugins"
expect_bad plugin "public_html/wp-content/plugins/woocommerce"
expect_bad plugin "public_html/wp-content/plugins/refungi-custom/extra"
expect_bad plugin "public_html/wp-content/themes/refungi-child"
expect_bad plugin "/"
expect_bad theme "public_html/wp-content/themes/refungi-child/../../../"

tmp=$(mktemp -d)
ftp_pid=""
cleanup() {
	if [ -n "${ftp_pid:-}" ]; then
		kill "$ftp_pid" 2>/dev/null || true
		wait "$ftp_pid" 2>/dev/null || true
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/site/public_html/wp-content/themes" "$tmp/site/public_html/wp-content/plugins"
bash "$guard" "$tmp/site/public_html/wp-content/themes/refungi-child" >/dev/null
[ -d "$tmp/site/public_html/wp-content/themes/refungi-child" ] || fail "guard did not create the child theme directory"
bash "$guard" "$tmp/site/public_html/wp-content/themes/refungi-child/" >/dev/null
bash "$guard" "$tmp/site/public_html/wp-content/plugins/refungi-custom" >/dev/null
[ -d "$tmp/site/public_html/wp-content/plugins/refungi-custom" ] || fail "guard did not create the plugin directory"
pass=$((pass + 4))

marker="$tmp/site/public_html/wp-content/themes/bridge/keep.txt"
mkdir -p "$tmp/site/public_html/wp-content/themes/bridge"
echo keep >"$marker"
rm -rf "$tmp/site/public_html/wp-content/themes/refungi-child"
ln -s bridge "$tmp/site/public_html/wp-content/themes/refungi-child"
if bash "$guard" "$tmp/site/public_html/wp-content/themes/refungi-child" >/dev/null 2>&1; then
	fail "guard followed a symlink into another theme"
fi
[ "$(cat "$marker")" = "keep" ] || fail "symlink target was modified"
pass=$((pass + 1))

mkdir -p "$tmp/bare/public_html/wp-content"
if bash "$guard" "$tmp/bare/public_html/wp-content/themes/refungi-child" >/dev/null 2>&1; then
	fail "guard created a missing themes directory"
fi
[ ! -e "$tmp/bare/public_html/wp-content/themes" ] || fail "guard created wp-content/themes"
pass=$((pass + 1))

if bash "$guard" "$tmp/site/public_html" >/dev/null 2>&1; then
	fail "guard accepted the site root"
fi
if bash "$guard" "$tmp/site/public_html/wp-content/themes/bridge-child" >/dev/null 2>&1; then
	fail "guard accepted the existing child theme"
fi
pass=$((pass + 2))

# Preflight: missing secrets name themselves and do not write outputs.
out="$tmp/missing-output"
: >"$out"
set +e
missing_err=$(
	env -u SFTP_HOST -u SFTP_PORT -u SFTP_USER -u SFTP_PASSWORD -u SFTP_KEY \
		-u SFTP_REMOTE_THEME_PATH -u SFTP_REMOTE_PLUGIN_PATH \
		GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY= \
		bash "$preflight" 2>&1
)
missing_status=$?
set -e
[ "$missing_status" -ne 0 ] || fail "preflight succeeded with no secrets"
printf '%s' "$missing_err" | grep -q "SFTP_HOST" || fail "missing-secret error did not name SFTP_HOST"
printf '%s' "$missing_err" | grep -q "SFTP_KEY or SFTP_PASSWORD" || fail "missing-secret error did not name auth secrets"
[ ! -s "$out" ] || fail "preflight wrote outputs after a missing-secret failure"
pass=$((pass + 1))

command -v ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen is required to test key preflight"
ssh-keygen -t ed25519 -N "" -f "$tmp/id_ok" -q -C "refungi-test"
good_key=$(cat "$tmp/id_ok")
key_sample=$(sed -n '2p' "$tmp/id_ok")
[ -n "$key_sample" ] || fail "could not sample the test key"

run_preflight() {
	env \
		SFTP_HOST="${1}" \
		SFTP_PORT="${2}" \
		SFTP_USER="${3}" \
		SFTP_PASSWORD="${4}" \
		SFTP_KEY="${5}" \
		SFTP_REMOTE_THEME_PATH="${6}" \
		SFTP_REMOTE_PLUGIN_PATH="${7}" \
		GITHUB_OUTPUT="${8}" \
		GITHUB_STEP_SUMMARY="${9:-}" \
		bash "$preflight"
}

ok_out="$tmp/ok-output"
: >"$ok_out"
ok_summary="$tmp/ok-summary"
: >"$ok_summary"
run_preflight \
	"obsidienne.o2switch.net" \
	"" \
	"crch2121" \
	"" \
	"$good_key" \
	"public_html/wp-content/themes/refungi-child" \
	"" \
	"$ok_out" \
	"$ok_summary" >/dev/null
grep -q '^auth=key$' "$ok_out" || fail "key auth was not selected"
grep -q '^transport=ssh$' "$ok_out" || fail "empty SFTP_PORT did not stay on SSH"
grep -q '^port=22$' "$ok_out" || fail "empty SFTP_PORT did not default to 22"
grep -q '^theme_path=public_html/wp-content/themes/refungi-child/$' "$ok_out" || fail "theme path was not normalized"
grep -q '^deploy_plugin=false$' "$ok_out" || fail "plugin deploy should be skipped when unset"
grep -q '^plugin_path=$' "$ok_out" || fail "plugin path should be empty when unset"
grep -F -q "$key_sample" "$ok_out" && fail "preflight output contains the private key"
grep -F -q "$key_sample" "$ok_summary" && fail "step summary contains the private key"
pass=$((pass + 1))

both_out="$tmp/both-output"
: >"$both_out"
secret_password="super-secret-password-value"
run_preflight \
	"obsidienne.o2switch.net" \
	"22" \
	"crch2121" \
	"$secret_password" \
	"$good_key" \
	"/home/crch2121/public_html/wp-content/themes/refungi-child/" \
	"public_html/wp-content/plugins/refungi-custom" \
	"$both_out" >/dev/null
grep -q '^auth=key$' "$both_out" || fail "key should win when both secrets are set"
grep -q '^transport=ssh$' "$both_out" || fail "port 22 with a key should stay on SSH"
grep -q '^deploy_plugin=true$' "$both_out" || fail "plugin path should deploy when set"
grep -q '^plugin_path=public_html/wp-content/plugins/refungi-custom/$' "$both_out" || fail "plugin path was not normalized"
grep -F -q "$secret_password" "$both_out" && fail "preflight output contains the password"
grep -F -q "$key_sample" "$both_out" && fail "preflight output contains the private key"
pass=$((pass + 1))

pass_out="$tmp/pass-output"
: >"$pass_out"
run_preflight \
	"obsidienne.o2switch.net" \
	"2222" \
	"crch2121" \
	"$secret_password" \
	"" \
	"public_html/wp-content/themes/refungi-child" \
	"" \
	"$pass_out" >/dev/null
grep -q '^auth=password$' "$pass_out" || fail "password auth was not selected"
grep -q '^transport=ssh$' "$pass_out" || fail "a custom SSH port should stay on SSH"
grep -q '^port=2222$' "$pass_out" || fail "custom port was not kept"
grep -F -q "$secret_password" "$pass_out" && fail "password auth output contains the password"
pass=$((pass + 1))

bad_out="$tmp/bad-output"
: >"$bad_out"
set +e
bad_err=$(
	run_preflight \
		"obsidienne.o2switch.net" \
		"22" \
		"crch2121" \
		"" \
		"$good_key" \
		"public_html/wp-content/themes/bridge-child" \
		"" \
		"$bad_out" 2>&1
)
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] || fail "preflight accepted bridge-child"
printf '%s' "$bad_err" | grep -q "wp-content/themes/refungi-child" || fail "unsafe path error did not name the required suffix"
[ ! -s "$bad_out" ] || fail "preflight wrote outputs for an unsafe path"
pass=$((pass + 1))

set +e
port_err=$(
	run_preflight \
		"https://obsidienne.o2switch.net" \
		"0" \
		"crch2121" \
		"$secret_password" \
		"" \
		"public_html/wp-content/themes/refungi-child" \
		"" \
		"$tmp/unused-output" 2>&1
)
port_status=$?
set -e
[ "$port_status" -ne 0 ] || fail "preflight accepted a URL host"
printf '%s' "$port_err" | grep -q "SFTP_HOST" || fail "bad host error did not name SFTP_HOST"
pass=$((pass + 1))

set +e
zero_port_err=$(
	run_preflight \
		"obsidienne.o2switch.net" \
		"0" \
		"crch2121" \
		"$secret_password" \
		"" \
		"public_html/wp-content/themes/refungi-child" \
		"" \
		"$tmp/zero-port-output" 2>&1
)
zero_port_status=$?
set -e
[ "$zero_port_status" -ne 0 ] || fail "preflight accepted port 0"
printf '%s' "$zero_port_err" | grep -q "SFTP_PORT" || fail "bad port error did not name SFTP_PORT"
[ ! -s "$tmp/zero-port-output" ] || fail "preflight wrote outputs for an invalid port"
pass=$((pass + 1))

ssh-keygen -t ed25519 -N "correct-horse" -f "$tmp/id_enc" -q -C "refungi-encrypted"
enc_key=$(cat "$tmp/id_enc")
set +e
enc_err=$(
	run_preflight \
		"obsidienne.o2switch.net" \
		"22" \
		"crch2121" \
		"" \
		"$enc_key" \
		"public_html/wp-content/themes/refungi-child" \
		"" \
		"$tmp/enc-output" 2>&1
)
enc_status=$?
set -e
[ "$enc_status" -ne 0 ] || fail "preflight accepted a passphrase-protected key"
printf '%s' "$enc_err" | grep -q "passphrase" || fail "encrypted-key error did not mention passphrase"
printf '%s' "$enc_err" | grep -F -q "correct-horse" && fail "preflight printed the key passphrase"
pass=$((pass + 1))

# ssh-key-guard talks to a fake ssh so the private key never hits a network.
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${FAKE_SSH_ARGS:?}"
cat >"${FAKE_SSH_STDIN:?}"
exit "${FAKE_SSH_STATUS:-0}"
EOF
chmod +x "$fake_bin/ssh"

export FAKE_SSH_ARGS="$tmp/ssh-args"
export FAKE_SSH_STDIN="$tmp/ssh-stdin"
export FAKE_SSH_STATUS=0
env \
	PATH="$fake_bin:$PATH" \
	SFTP_HOST="obsidienne.o2switch.net" \
	SFTP_PORT="22" \
	SFTP_USER="crch2121" \
	SFTP_KEY="$good_key" \
	bash "$script_dir/ssh-key-guard.sh" "public_html/wp-content/themes/refungi-child/" >/dev/null
grep -q "crch2121@obsidienne.o2switch.net" "$FAKE_SSH_ARGS" || fail "ssh was not invoked with the configured user and host"
grep -q "public_html/wp-content/themes/refungi-child/" "$FAKE_SSH_ARGS" || fail "ssh was not invoked with the theme path"
grep -F -q "$key_sample" "$FAKE_SSH_ARGS" && fail "ssh arguments contain the private key"
grep -q "set -euo pipefail" "$FAKE_SSH_STDIN" || fail "remote guard script was not sent over stdin"
# The key file passed to -i must have been removed.
key_path=$(awk '$0 == "-i" { getline; print; exit }' "$FAKE_SSH_ARGS")
[ -n "$key_path" ] || fail "ssh was not given an identity file"
[ ! -e "$key_path" ] || fail "deploy key file was left on disk: ${key_path}"
pass=$((pass + 1))

export FAKE_SSH_STATUS=1
if env \
	PATH="$fake_bin:$PATH" \
	SFTP_HOST="obsidienne.o2switch.net" \
	SFTP_PORT="22" \
	SFTP_USER="crch2121" \
	SFTP_KEY="$good_key" \
	bash "$script_dir/ssh-key-guard.sh" "public_html/wp-content/themes/refungi-child/" >/dev/null; then
	fail "ssh-key-guard succeeded when ssh failed"
fi
pass=$((pass + 1))
unset FAKE_SSH_ARGS FAKE_SSH_STDIN FAKE_SSH_STATUS

set +e
inject_err=$(
	env \
		SFTP_HOST='example.com' \
		SFTP_USER='crch2121' \
		SFTP_PASSWORD='not-used' \
		SFTP_PORT='22;touch' \
		THEME_PATH='public_html/wp-content/themes/refungi-child' \
		DEPLOY_PLUGIN='false' \
		bash "$script_dir/sftp-password-deploy.sh" 2>&1
)
inject_status=$?
set -e
[ "$inject_status" -ne 0 ] || fail "password deploy accepted an unsafe port"
printf '%s' "$inject_err" | grep -q "SFTP_PORT" || fail "unsafe port error did not name SFTP_PORT"
printf '%s' "$inject_err" | grep -q "touch" && fail "unsafe port was echoed in a way that could hide the rejection"
pass=$((pass + 1))

set +e
port21_ssh_err=$(
	env \
		SFTP_HOST='example.com' \
		SFTP_USER='crch2121' \
		SFTP_PASSWORD='not-used' \
		SFTP_PORT='21' \
		THEME_PATH='public_html/wp-content/themes/refungi-child' \
		DEPLOY_PLUGIN='false' \
		bash "$script_dir/sftp-password-deploy.sh" 2>&1
)
port21_ssh_status=$?
set -e
[ "$port21_ssh_status" -ne 0 ] || fail "SSH password deploy accepted port 21"
printf '%s' "$port21_ssh_err" | grep -q "plain FTP" || fail "port 21 SSH refusal did not name plain FTP"
pass=$((pass + 1))

ftp_out="$tmp/ftp-output"
: >"$ftp_out"
run_preflight \
	"crch2121.odns.fr" \
	"21" \
	"crch2121" \
	"$secret_password" \
	"" \
	"/home/crch2121/public_html/wp-content/themes/refungi-child" \
	"/home/crch2121/public_html/wp-content/plugins/refungi-custom" \
	"$ftp_out" >/dev/null
grep -q '^transport=ftp$' "$ftp_out" || fail "port 21 did not select FTP"
grep -q '^auth=password$' "$ftp_out" || fail "port 21 did not select password auth"
grep -q '^port=21$' "$ftp_out" || fail "port 21 was not kept"
grep -q '^theme_path=/home/crch2121/public_html/wp-content/themes/refungi-child/$' "$ftp_out" || fail "FTP theme path was not normalized"
grep -q '^plugin_path=/home/crch2121/public_html/wp-content/plugins/refungi-custom/$' "$ftp_out" || fail "FTP plugin path was not normalized"
grep -F -q "$secret_password" "$ftp_out" && fail "FTP preflight output contains the password"
pass=$((pass + 1))

# A leftover SSH key must not block the FTP path, and it must not be validated or echoed.
ftp_both="$tmp/ftp-both-output"
: >"$ftp_both"
run_preflight \
	"crch2121.odns.fr" \
	"21" \
	"crch2121" \
	"$secret_password" \
	"not-a-private-key" \
	"/home/crch2121/public_html/wp-content/themes/refungi-child/" \
	"" \
	"$ftp_both" >/dev/null
grep -q '^transport=ftp$' "$ftp_both" || fail "port 21 with a leftover key did not stay on FTP"
grep -q '^auth=password$' "$ftp_both" || fail "port 21 should ignore the SSH key"
grep -q '^deploy_plugin=false$' "$ftp_both" || fail "FTP preflight deployed the plugin with an empty path"
grep -F -q "not-a-private-key" "$ftp_both" && fail "FTP preflight output contains the ignored key"
grep -F -q "$secret_password" "$ftp_both" && fail "FTP preflight output contains the password"
pass=$((pass + 1))

ftp_key_only="$tmp/ftp-key-only-output"
: >"$ftp_key_only"
set +e
ftp_key_err=$(
	run_preflight \
		"crch2121.odns.fr" \
		"21" \
		"crch2121" \
		"" \
		"$good_key" \
		"/home/crch2121/public_html/wp-content/themes/refungi-child" \
		"" \
		"$ftp_key_only" 2>&1
)
ftp_key_status=$?
set -e
[ "$ftp_key_status" -ne 0 ] || fail "port 21 accepted an SSH key without a password"
printf '%s' "$ftp_key_err" | grep -q "SFTP_PASSWORD" || fail "port 21 key-only error did not name SFTP_PASSWORD"
grep -F -q "$key_sample" <<<"$ftp_key_err" && fail "port 21 key-only error printed the private key"
[ ! -s "$ftp_key_only" ] || fail "preflight wrote outputs for FTP without a password"
pass=$((pass + 1))

# Fake lftp records the generated session and answers directory probes.
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/lftp" <<'EOF'
#!/usr/bin/env bash
set +H
printf '%s\n' "$@" >>"${FAKE_LFTP_ARGS:?}"
script=""
while [ $# -gt 0 ]; do
	if [ "$1" = "-e" ]; then
		shift
		script=${1#source }
		script=${script# }
		break
	fi
	shift
done
{
	echo "===== CALL ====="
	cat "$script"
} >>"${FAKE_LFTP_SCRIPTS:?}"
if [ -f "${HOME}/.lftprc" ] && grep -q 'ftp:ssl-allow false' "${HOME}/.lftprc"; then
	echo "ssl-off" >>"${FAKE_LFTP_NOTES:?}"
else
	echo "ssl-not-disabled" >>"${FAKE_LFTP_NOTES:?}"
fi
if grep -F -q -- "${FAKE_LFTP_SECRET:?}" "${FAKE_LFTP_ARGS:?}" "${FAKE_LFTP_SCRIPTS:?}" "${HOME}/.lftprc"; then
	echo "SECRET_LEAK" >>"${FAKE_LFTP_NOTES:?}"
fi
if grep -q 'mirror --reverse --delete' "$script"; then
	echo "mirror" >>"${FAKE_LFTP_CALLS:?}"
	exit 0
fi
if grep -q 'mkdir "' "$script"; then
	echo "mkdir" >>"${FAKE_LFTP_CALLS:?}"
	exit 0
fi
if grep -q 'cls -ld' "$script"; then
	base=$(sed -n 's/.*cls -ld "\([^"]*\)".*/\1/p' "$script")
	case "${FAKE_LFTP_MODE:?}" in
		noparent)
			echo "cd: Access failed: 550 No such file or directory." >&2
			exit 1
			;;
		login-failed)
			echo "Login failed: 530 Authentication failed." >&2
			exit 1
			;;
		symlink)
			echo PARENT_OK
			echo "lrwxrwxrwx 1 user user 6 Oct 31 00:00 ${base} -> bridge"
			exit 0
			;;
		file)
			echo PARENT_OK
			echo "-rw-r--r-- 1 user user 10 Oct 31 00:00 ${base}"
			exit 0
			;;
		plugin-missing)
			echo PARENT_OK
			if [ "$base" = "refungi-custom" ]; then
				echo "Access failed: 550 No such file or directory. (${base})" >&2
				exit 1
			fi
			echo "drwxr-xr-x 2 user user 4096 Oct 31 00:00 ${base}"
			exit 0
			;;
		*)
			echo PARENT_OK
			echo "drwxr-xr-x 2 user user 4096 Oct 31 00:00 ${base}"
			exit 0
			;;
	esac
fi
echo "unexpected lftp script" >&2
exit 1
EOF
chmod +x "$fake_bin/lftp"

run_fake_ftp() {
	local mode="$1"
	: >"$FAKE_LFTP_ARGS"
	: >"$FAKE_LFTP_SCRIPTS"
	: >"$FAKE_LFTP_CALLS"
	: >"$FAKE_LFTP_NOTES"
	env \
		LFTP_BIN="$fake_bin/lftp" \
		FAKE_LFTP_MODE="$mode" \
		FAKE_LFTP_ARGS="$FAKE_LFTP_ARGS" \
		FAKE_LFTP_SCRIPTS="$FAKE_LFTP_SCRIPTS" \
		FAKE_LFTP_CALLS="$FAKE_LFTP_CALLS" \
		FAKE_LFTP_NOTES="$FAKE_LFTP_NOTES" \
		FAKE_LFTP_SECRET="$secret_password" \
		SFTP_HOST="crch2121.odns.fr" \
		SFTP_PORT="21" \
		SFTP_USER="crch2121" \
		SFTP_PASSWORD="$secret_password" \
		THEME_PATH="/home/crch2121/public_html/wp-content/themes/refungi-child/" \
		PLUGIN_PATH="/home/crch2121/public_html/wp-content/plugins/refungi-custom/" \
		DEPLOY_PLUGIN="true" \
		bash "$script_dir/ftp-password-deploy.sh"
}

FAKE_LFTP_ARGS="$tmp/lftp-args"
FAKE_LFTP_SCRIPTS="$tmp/lftp-scripts"
FAKE_LFTP_CALLS="$tmp/lftp-calls"
FAKE_LFTP_NOTES="$tmp/lftp-notes"

run_fake_ftp dir >/dev/null
grep -q 'ssl-off' "$FAKE_LFTP_NOTES" || fail "FTP session did not disable TLS before connect"
grep -q 'SECRET_LEAK' "$FAKE_LFTP_NOTES" && fail "FTP password appeared in argv, the lftp script, or the rc file"
grep -q 'mirror --reverse --delete' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror is missing --delete"
grep -q -- '--exclude-glob node_modules/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror does not exclude node_modules"
grep -q -- '--exclude-glob .git/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror does not exclude .git"
grep -q -- '--exclude-glob .github/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror does not exclude .github"
grep -F -q 'cd "public_html/wp-content/themes"' "$FAKE_LFTP_SCRIPTS" || fail "FTP did not cd to the login-root theme parent"
grep -F -q 'public_html/wp-content/themes/refungi-child/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror target is not the child theme relative to the login root"
grep -F -q 'public_html/wp-content/plugins/refungi-custom/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror target is not the custom plugin relative to the login root"
grep -F -q 'cd "/home/' "$FAKE_LFTP_SCRIPTS" && fail "FTP cd used an absolute /home path"
grep -F -q 'themes/refungi-child/' "$FAKE_LFTP_SCRIPTS" || fail "FTP mirror source is not the child theme"
grep -q 'mkdir ' "$FAKE_LFTP_SCRIPTS" && fail "FTP mkdir ran for directories that already exist"
grep -q -- '--env-password' "$FAKE_LFTP_ARGS" || fail "lftp was not started with --env-password"
pass=$((pass + 1))

: >"$FAKE_LFTP_ARGS"
: >"$FAKE_LFTP_SCRIPTS"
: >"$FAKE_LFTP_CALLS"
: >"$FAKE_LFTP_NOTES"
env \
	LFTP_BIN="$fake_bin/lftp" \
	FAKE_LFTP_MODE="dir" \
	FAKE_LFTP_ARGS="$FAKE_LFTP_ARGS" \
	FAKE_LFTP_SCRIPTS="$FAKE_LFTP_SCRIPTS" \
	FAKE_LFTP_CALLS="$FAKE_LFTP_CALLS" \
	FAKE_LFTP_NOTES="$FAKE_LFTP_NOTES" \
	FAKE_LFTP_SECRET="$secret_password" \
	SFTP_HOST="crch2121.odns.fr" \
	SFTP_PORT="21" \
	SFTP_USER="crch2121" \
	SFTP_PASSWORD="$secret_password" \
	THEME_PATH="public_html/wp-content/themes/refungi-child" \
	PLUGIN_PATH="public_html/wp-content/plugins/refungi-custom" \
	DEPLOY_PLUGIN="true" \
	bash "$script_dir/ftp-password-deploy.sh" >/dev/null
grep -F -q 'cd "public_html/wp-content/themes"' "$FAKE_LFTP_SCRIPTS" || fail "relative FTP theme path was rewritten"
grep -F -q 'cd "/home/' "$FAKE_LFTP_SCRIPTS" && fail "relative FTP path gained an /home prefix"
grep -F -q '/home/crch2121/' "$FAKE_LFTP_SCRIPTS" && fail "relative FTP path was joined to /home/crch2121"
pass=$((pass + 1))

: >"$FAKE_LFTP_ARGS"
: >"$FAKE_LFTP_SCRIPTS"
: >"$FAKE_LFTP_CALLS"
: >"$FAKE_LFTP_NOTES"
set +e
other_home_err=$(
	env \
		LFTP_BIN="$fake_bin/lftp" \
		FAKE_LFTP_MODE="dir" \
		FAKE_LFTP_ARGS="$FAKE_LFTP_ARGS" \
		FAKE_LFTP_SCRIPTS="$FAKE_LFTP_SCRIPTS" \
		FAKE_LFTP_CALLS="$FAKE_LFTP_CALLS" \
		FAKE_LFTP_NOTES="$FAKE_LFTP_NOTES" \
		FAKE_LFTP_SECRET="$secret_password" \
		SFTP_HOST="crch2121.odns.fr" \
		SFTP_PORT="21" \
		SFTP_USER="crch2121" \
		SFTP_PASSWORD="$secret_password" \
		THEME_PATH="/home/someoneelse/public_html/wp-content/themes/refungi-child" \
		DEPLOY_PLUGIN="false" \
		bash "$script_dir/ftp-password-deploy.sh" 2>&1
)
other_home_status=$?
set -e
[ "$other_home_status" -ne 0 ] || fail "FTP deploy accepted another account's /home path"
printf '%s' "$other_home_err" | grep -q "FTP login root" || fail "other-home error did not mention the FTP login root"
[ ! -s "$FAKE_LFTP_ARGS" ] || fail "other-home path still invoked lftp"
pass=$((pass + 1))

run_fake_ftp plugin-missing >/dev/null
grep -F -q 'mkdir "refungi-custom"' "$FAKE_LFTP_SCRIPTS" || fail "missing plugin directory was not created"
grep -F -q 'mkdir -p' "$FAKE_LFTP_SCRIPTS" && fail "FTP mkdir -p would create parent directories"
grep -F -q 'mkdir "themes"' "$FAKE_LFTP_SCRIPTS" && fail "FTP mkdir targeted the themes directory"
grep -F -q 'mkdir "refungi-child"' "$FAKE_LFTP_SCRIPTS" && fail "existing theme directory was created again"
pass=$((pass + 1))

set +e
symlink_err=$(run_fake_ftp symlink 2>&1)
symlink_status=$?
set -e
[ "$symlink_status" -ne 0 ] || fail "FTP deploy followed a symlink"
printf '%s' "$symlink_err" | grep -q "symlink" || fail "symlink refusal did not say symlink"
grep -q 'mirror --reverse' "$FAKE_LFTP_SCRIPTS" && fail "FTP mirror ran after a symlink listing"
pass=$((pass + 1))

set +e
file_err=$(run_fake_ftp file 2>&1)
file_status=$?
set -e
[ "$file_status" -ne 0 ] || fail "FTP deploy accepted a file where the theme directory should be"
printf '%s' "$file_err" | grep -q "not a directory" || fail "file refusal did not say not a directory"
grep -q 'mirror --reverse' "$FAKE_LFTP_SCRIPTS" && fail "FTP mirror ran for a non-directory"
pass=$((pass + 1))

set +e
parent_err=$(run_fake_ftp noparent 2>&1)
parent_status=$?
set -e
[ "$parent_status" -ne 0 ] || fail "FTP deploy created a missing parent"
printf '%s' "$parent_err" | grep -q "Parent directory does not exist" || fail "missing parent error was not specific"
grep -q 'mkdir ' "$FAKE_LFTP_SCRIPTS" && fail "FTP mkdir ran when the parent was missing"
grep -q 'mirror --reverse' "$FAKE_LFTP_SCRIPTS" && fail "FTP mirror ran when the parent was missing"
pass=$((pass + 1))

set +e
login_err=$(run_fake_ftp login-failed 2>&1)
login_status=$?
set -e
[ "$login_status" -ne 0 ] || fail "FTP deploy succeeded after a login failure"
printf '%s' "$login_err" | grep -q "FTP login failed" || fail "login failure was reported as a missing directory"
grep -F -q "$secret_password" <<<"$login_err" && fail "login error printed the password"
pass=$((pass + 1))

: >"$FAKE_LFTP_ARGS"
: >"$FAKE_LFTP_SCRIPTS"
: >"$FAKE_LFTP_CALLS"
: >"$FAKE_LFTP_NOTES"
set +e
ftp_inject_err=$(
	env \
		LFTP_BIN="$fake_bin/lftp" \
		FAKE_LFTP_MODE="dir" \
		FAKE_LFTP_ARGS="$FAKE_LFTP_ARGS" \
		FAKE_LFTP_SCRIPTS="$FAKE_LFTP_SCRIPTS" \
		FAKE_LFTP_CALLS="$FAKE_LFTP_CALLS" \
		FAKE_LFTP_NOTES="$FAKE_LFTP_NOTES" \
		FAKE_LFTP_SECRET="$secret_password" \
		SFTP_HOST='crch2121.odns.fr' \
		SFTP_USER='crch2121' \
		SFTP_PASSWORD="$secret_password" \
		SFTP_PORT='21;touch' \
		THEME_PATH='/home/crch2121/public_html/wp-content/themes/refungi-child' \
		DEPLOY_PLUGIN='false' \
		bash "$script_dir/ftp-password-deploy.sh" 2>&1
)
ftp_inject_status=$?
set -e
[ "$ftp_inject_status" -ne 0 ] || fail "FTP deploy accepted an unsafe port"
printf '%s' "$ftp_inject_err" | grep -q "SFTP_PORT" || fail "unsafe FTP port error did not name SFTP_PORT"
[ ! -s "$FAKE_LFTP_CALLS" ] || fail "unsafe FTP port still invoked lftp"
pass=$((pass + 1))

: >"$FAKE_LFTP_ARGS"
: >"$FAKE_LFTP_SCRIPTS"
: >"$FAKE_LFTP_CALLS"
: >"$FAKE_LFTP_NOTES"
set +e
bridge_err=$(
	env \
		LFTP_BIN="$fake_bin/lftp" \
		FAKE_LFTP_MODE="dir" \
		FAKE_LFTP_ARGS="$FAKE_LFTP_ARGS" \
		FAKE_LFTP_SCRIPTS="$FAKE_LFTP_SCRIPTS" \
		FAKE_LFTP_CALLS="$FAKE_LFTP_CALLS" \
		FAKE_LFTP_NOTES="$FAKE_LFTP_NOTES" \
		FAKE_LFTP_SECRET="$secret_password" \
		SFTP_HOST='crch2121.odns.fr' \
		SFTP_USER='crch2121' \
		SFTP_PASSWORD="$secret_password" \
		SFTP_PORT='21' \
		THEME_PATH='/home/crch2121/public_html/wp-content/themes/bridge-child' \
		DEPLOY_PLUGIN='false' \
		bash "$script_dir/ftp-password-deploy.sh" 2>&1
)
bridge_status=$?
set -e
[ "$bridge_status" -ne 0 ] || fail "FTP deploy accepted bridge-child"
printf '%s' "$bridge_err" | grep -q "wp-content/themes/refungi-child" || fail "unsafe FTP path error did not name the required suffix"
grep -q 'mirror --reverse' "$FAKE_LFTP_SCRIPTS" && fail "FTP mirror ran for bridge-child"
pass=$((pass + 1))

# shellcheck disable=SC1091
source "$script_dir/rsync-flags.sh"
[ -n "$RSYNC_DELETE_FLAGS" ] || fail "rsync flags are empty"
grep -F -q "ARGS: \"${RSYNC_DELETE_FLAGS}\"" .github/workflows/deploy.yml || fail "workflow ARGS drifted from rsync-flags.sh"
grep -F -q "easingthemes/ssh-deploy@v6.0.3" .github/workflows/deploy.yml || fail "ssh-deploy action pin missing"
grep -F -q "dangerous-clean-slate: true" .github/workflows/deploy.yml && fail "workflow enables a full remote wipe"
if grep -E 'obsidienne|crch2121' .github/workflows/deploy.yml; then
	fail "workflow hardcodes the example host or cPanel user"
fi
grep -q "secrets.SFTP_HOST" .github/workflows/deploy.yml || fail "workflow does not read SFTP_HOST from secrets"
grep -q "secrets.SFTP_KEY" .github/workflows/deploy.yml || fail "workflow does not read SFTP_KEY from secrets"
grep -q "secrets.SFTP_PASSWORD" .github/workflows/deploy.yml || fail "workflow does not read SFTP_PASSWORD from secrets"
grep -q "secrets.SFTP_REMOTE_THEME_PATH" .github/workflows/deploy.yml || fail "workflow does not read the theme path secret"
grep -q "secrets.SFTP_REMOTE_PLUGIN_PATH" .github/workflows/deploy.yml || fail "workflow does not read the plugin path secret"
grep -q "ftp-password-deploy.sh" .github/workflows/deploy.yml || fail "workflow does not run the FTP deploy"
grep -q "transport == 'ssh'" .github/workflows/deploy.yml || fail "SSH steps are not limited to the SSH transport"
grep -q "transport == 'ftp'" .github/workflows/deploy.yml || fail "FTP step is not limited to port 21"
grep -q "sftp-password-deploy.sh" .github/workflows/deploy.yml || fail "SSH password path was removed"
pass=$((pass + 1))

grep -q '^Theme Name: Refungi Child$' themes/refungi-child/style.css || fail "theme name header missing"
grep -q '^Template: bridge$' themes/refungi-child/style.css || fail "parent template is not bridge"
grep -q 'stylesheet.min.css' themes/refungi-child/functions.php || fail "child theme does not enqueue the Bridge stylesheet"
grep -q 'prod hero still says PERMAFUNGI' themes/refungi-child/assets/css/overrides.css || fail "overrides reminder missing"
grep -q 'wp_enqueue_style' themes/refungi-child/functions.php || fail "child theme does not enqueue styles"
if grep -R -n 'PARENT_THEME_SLUG' themes plugins README.md; then
	fail "PARENT_THEME_SLUG is still documented as the template"
fi
grep -q 'Plugin Name: Refungi Custom' plugins/refungi-custom/refungi-custom.php || fail "plugin header missing"
test -f themes/refungi-child/assets/js/.gitkeep || fail ".gitkeep missing"

for secret_name in SFTP_HOST SFTP_PORT SFTP_USER SFTP_PASSWORD SFTP_KEY SFTP_REMOTE_THEME_PATH SFTP_REMOTE_PLUGIN_PATH; do
	grep -q "$secret_name" README.md || fail "README does not document ${secret_name}"
done
grep -q '^Template: bridge$' README.md || fail "README does not record Template: bridge"
grep -q "JetBackup" README.md || fail "README does not mention JetBackup"
grep -q 'crch2121.odns.fr' README.md || fail "README does not document the FTP host"
grep -q '/home/crch2121/public_html/wp-content/themes/refungi-child' README.md || fail "README does not document the SSH theme path"
grep -q '/home/crch2121/public_html/wp-content/plugins/refungi-custom' README.md || fail "README does not document the SSH plugin path"
grep -q 'public_html/wp-content/themes/refungi-child' README.md || fail "README does not document the FTP theme path"
grep -q 'public_html/wp-content/plugins/refungi-custom' README.md || fail "README does not document the FTP plugin path"
grep -q 'FTP login root' README.md || fail "README does not say FTP paths are relative to the login root"
grep -q 'plain FTP' README.md || fail "README does not document plain FTP on port 21"
pass=$((pass + 1))

if command -v lftp >/dev/null 2>&1 && python3 -c 'import pyftpdlib' >/dev/null 2>&1; then
	ftp_root="$tmp/ftproot"
	mkdir -p \
		"$ftp_root/home/crch2121/public_html/wp-content/themes/bridge" \
		"$ftp_root/home/crch2121/public_html/wp-content/themes/bridge-child" \
		"$ftp_root/home/crch2121/public_html/wp-content/themes/refungi-child/assets/css" \
		"$ftp_root/home/crch2121/public_html/wp-content/plugins/woocommerce" \
		"$ftp_root/home/crch2121/public_html/wp-content/uploads"
	echo keep-bridge >"$ftp_root/home/crch2121/public_html/wp-content/themes/bridge/keep.txt"
	echo keep-bridge-child >"$ftp_root/home/crch2121/public_html/wp-content/themes/bridge-child/keep.txt"
	echo stale >"$ftp_root/home/crch2121/public_html/wp-content/themes/refungi-child/old.css"
	echo stale >"$ftp_root/home/crch2121/public_html/wp-content/themes/refungi-child/assets/css/stale.css"
	echo keep-woo >"$ftp_root/home/crch2121/public_html/wp-content/plugins/woocommerce/keep.txt"
	echo keep-uploads >"$ftp_root/home/crch2121/public_html/wp-content/uploads/keep.txt"
	printf '%s' 'ftp-test-password' >"$tmp/ftp-password"
	cat >"$tmp/ftpd.py" <<'PY'
import sys
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

root = sys.argv[1]
password = open(sys.argv[2], encoding="utf-8").read()
auth = DummyAuthorizer()
auth.add_user("crch2121", password, root, perm="elradfmw")
handler = FTPHandler
handler.authorizer = auth
handler.passive_ports = range(52100, 52140)
server = FTPServer(("127.0.0.1", 0), handler)
print(server.socket.getsockname()[1], flush=True)
server.serve_forever()
PY
	# Jail the test server at the account home, which is what o2switch FTP does.
	python3 "$tmp/ftpd.py" "$ftp_root/home/crch2121" "$tmp/ftp-password" >"$tmp/ftp-port" 2>"$tmp/ftpd.log" &
	ftp_pid=$!
	for _ in $(seq 1 50); do
		if [ -s "$tmp/ftp-port" ] && grep -Eq '^[0-9]+$' "$tmp/ftp-port"; then
			break
		fi
		sleep 0.05
	done
	ftp_port=$(head -1 "$tmp/ftp-port")
	grep -Eq '^[0-9]+$' <<<"$ftp_port" || fail "local FTP server did not publish a port"
	env \
		SFTP_HOST="127.0.0.1" \
		SFTP_PORT="$ftp_port" \
		REFUGI_FTP_TEST_PORT="$ftp_port" \
		SFTP_USER="crch2121" \
		SFTP_PASSWORD="ftp-test-password" \
		THEME_PATH="/home/crch2121/public_html/wp-content/themes/refungi-child" \
		PLUGIN_PATH="/home/crch2121/public_html/wp-content/plugins/refungi-custom" \
		DEPLOY_PLUGIN="true" \
		bash "$script_dir/ftp-password-deploy.sh" >/dev/null
	theme_remote="$ftp_root/home/crch2121/public_html/wp-content/themes/refungi-child"
	plugin_remote="$ftp_root/home/crch2121/public_html/wp-content/plugins/refungi-custom"
	[ ! -e "$theme_remote/old.css" ] || fail "FTP mirror left a file that is not in Git"
	[ ! -e "$theme_remote/assets/css/stale.css" ] || fail "FTP mirror left a nested file that is not in Git"
	grep -q '^Theme Name: Refungi Child$' "$theme_remote/style.css" || fail "FTP mirror did not upload style.css"
	grep -q 'Plugin Name: Refungi Custom' "$plugin_remote/refungi-custom.php" || fail "FTP mirror did not create the custom plugin"
	[ "$(cat "$ftp_root/home/crch2121/public_html/wp-content/themes/bridge/keep.txt")" = "keep-bridge" ] || fail "FTP mirror changed the Bridge parent theme"
	[ "$(cat "$ftp_root/home/crch2121/public_html/wp-content/themes/bridge-child/keep.txt")" = "keep-bridge-child" ] || fail "FTP mirror changed bridge-child"
	[ "$(cat "$ftp_root/home/crch2121/public_html/wp-content/plugins/woocommerce/keep.txt")" = "keep-woo" ] || fail "FTP mirror changed another plugin"
	[ "$(cat "$ftp_root/home/crch2121/public_html/wp-content/uploads/keep.txt")" = "keep-uploads" ] || fail "FTP mirror changed uploads"
	[ ! -d "$theme_remote/node_modules" ] || fail "FTP mirror uploaded node_modules"
	[ ! -d "$theme_remote/refungi-child" ] || fail "FTP mirror nested the theme directory inside itself"
	kill "$ftp_pid" 2>/dev/null || true
	wait "$ftp_pid" 2>/dev/null || true
	ftp_pid=""

	bare_root="$tmp/bare-ftproot"
	mkdir -p "$bare_root/home/crch2121/public_html/wp-content"
	python3 "$tmp/ftpd.py" "$bare_root/home/crch2121" "$tmp/ftp-password" >"$tmp/ftp-port-bare" 2>"$tmp/ftpd-bare.log" &
	ftp_pid=$!
	for _ in $(seq 1 50); do
		if [ -s "$tmp/ftp-port-bare" ] && grep -Eq '^[0-9]+$' "$tmp/ftp-port-bare"; then
			break
		fi
		sleep 0.05
	done
	bare_port=$(head -1 "$tmp/ftp-port-bare")
	set +e
	bare_err=$(
		env \
			SFTP_HOST="127.0.0.1" \
			SFTP_PORT="$bare_port" \
			REFUGI_FTP_TEST_PORT="$bare_port" \
			SFTP_USER="crch2121" \
			SFTP_PASSWORD="ftp-test-password" \
			THEME_PATH="/home/crch2121/public_html/wp-content/themes/refungi-child" \
			DEPLOY_PLUGIN="false" \
			bash "$script_dir/ftp-password-deploy.sh" 2>&1
	)
	bare_status=$?
	set -e
	[ "$bare_status" -ne 0 ] || fail "FTP deploy created a missing themes directory"
	printf '%s' "$bare_err" | grep -q "Parent directory does not exist" || fail "missing themes directory was not reported"
	[ ! -e "$bare_root/home/crch2121/public_html/wp-content/themes" ] || fail "FTP deploy created wp-content/themes"
	grep -F -q 'ftp-test-password' <<<"$bare_err" && fail "FTP error output contains the password"
	kill "$ftp_pid" 2>/dev/null || true
	wait "$ftp_pid" 2>/dev/null || true
	ftp_pid=""
	pass=$((pass + 1))
elif [ "${GITHUB_ACTIONS:-}" = "true" ]; then
	fail "lftp and python3-pyftpdlib are required on CI to test the FTP deploy"
else
	echo "Skipping local FTP mirror test (lftp or pyftpdlib is not installed)."
fi

if grep -R -n -E 'BEGIN (OPENSSH|RSA|EC|OPENSSH) PRIVATE KEY' \
	--exclude-dir=.git \
	--exclude=run-tests.sh \
	. ; then
	fail "a private key block was found in the repo"
fi

if command -v php >/dev/null 2>&1; then
	php -l themes/refungi-child/functions.php >/dev/null
	php -l plugins/refungi-custom/refungi-custom.php >/dev/null
fi

echo "Passed ${pass} deploy guard checks."
