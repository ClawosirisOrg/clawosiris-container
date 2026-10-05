#!/bin/sh
set -eu
image=$1
flavor=$2
engine=${ENGINE:-podman}
uid=${SANDBOX_TEST_UID:-1556100503}
if [ -z "$image" ] || [ -z "$flavor" ]; then echo "usage: $0 IMAGE base|node24" >&2; exit 2; fi
case "$flavor" in base|node24) ;; *) echo "unknown flavor: $flavor" >&2; exit 2 ;; esac
command -v "$engine" >/dev/null

# Never forward host credentials, socket, home or workspace.
run_sandbox() {
  "$engine" run --rm --user "$uid:$uid" --read-only \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --tmpfs /tmp:rw,nosuid,nodev,size=64m,mode=1777 \
    --tmpfs /workspace:rw,nosuid,nodev,size=64m,mode=1777 \
    --env HOME=/tmp --env COREPACK_ENABLE_NETWORK=0 \
    --env GIT_TERMINAL_PROMPT=0 --env SANDBOX_TEST_UID="$uid" \
    --entrypoint /bin/sh "$@"
}
if output=$(run_sandbox --network none "$image" -ec '
  test "$(id -u)" = "$SANDBOX_TEST_UID"
  touch /workspace/sandbox-write-probe; rm /workspace/sandbox-write-probe
  gh --version >/dev/null; git --version; ssh -V; jq --version
  test "$(printf "{}" | jq -c .)" = "{}"
  if touch /etc/sandbox-write-probe 2>/dev/null; then echo "root is writable" >&2; exit 1; fi
  if timeout 12 git ls-remote https://github.com/git/git.git HEAD >/dev/null 2>&1; then
    echo "network-none unexpectedly reached GitHub" >&2; exit 1
  fi
' 2>&1); then
  printf '%s\n' "$output"
else
  status=$?
  detail=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-400 | sed 's/%/%25/g')
  echo "::error title=offline sandbox smoke::exit $status; $detail"
  exit "$status"
fi
# Root itself must also be unable to write the read-only image layer.
if "$engine" run --rm --user 0:0 --read-only --network none \
  --cap-drop=ALL --security-opt=no-new-privileges --entrypoint /bin/sh \
  "$image" -ec 'if touch /etc/sandbox-write-probe 2>/dev/null; then exit 1; fi'; then :; else
  status=$?; echo "::error title=root read-only smoke::exit $status"; exit "$status"
fi
if [ "$flavor" = node24 ]; then
  if run_sandbox --network none "$image" -ec '
    test "$(node --version)" = v24.19.0
    test "$(pnpm --version)" = 12.5.0
  '; then :; else
    status=$?; echo "::error title=offline Node smoke::exit $status"; exit "$status"
  fi
fi

# Named bridge DNS is deterministic and does not depend on public DNS.
network="sandbox-smoke-$$"
peer="sandbox-peer-$$"
cleanup() {
  "$engine" rm -f "$peer" >/dev/null 2>&1 || :
  "$engine" network rm "$network" >/dev/null 2>&1 || :
}
trap cleanup EXIT HUP INT TERM
if "$engine" network create "$network" >/dev/null; then :; else
  status=$?; echo "::error title=bridge creation smoke::exit $status"; exit "$status"
fi
if "$engine" run -d --name "$peer" --network "$network" --read-only \
  --user "$uid:$uid" --cap-drop=ALL --security-opt=no-new-privileges \
  --entrypoint sleep "$image" 120 >/dev/null; then :; else
  status=$?; echo "::error title=bridge peer smoke::exit $status"; exit "$status"
fi
if run_sandbox --network "$network" "$image" -ec '
  test "$(id -u)" = "$SANDBOX_TEST_UID"
  getent hosts "$1" >/dev/null
  if touch /etc/sandbox-write-probe 2>/dev/null; then echo "root is writable" >&2; exit 1; fi
' sh "$peer"; then :; else
  status=$?; echo "::error title=bridge DNS smoke::exit $status"; exit "$status"
fi

# Opt-in live read-only GitHub lookup; not a CI dependency.
if [ "${SANDBOX_LIVE_GITHUB:-0}" = 1 ]; then
  run_sandbox --network "$network" "$image" -ec '
    timeout 30 git ls-remote https://github.com/git/git.git HEAD |
      grep -E "^[0-9a-f]{40}[[:space:]]+HEAD$"
  '
fi
printf 'sandbox smoke passed: %s (%s)\n' "$image" "$flavor"
