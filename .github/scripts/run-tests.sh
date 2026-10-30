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
trap 'rm -rf "$tmp"' EXIT

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
pass=$((pass + 1))

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
