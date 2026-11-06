#!/bin/sh

set -eu

fail() {
  printf 'quadlet validation failed: %s\n' "$*" >&2
  exit 1
}

script_dir=${0%/*}
if [ "$script_dir" = "$0" ]; then
  script_dir=.
fi
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)

homebrew_volume=$repo_root/quadlet/openclaw-homebrew.volume
homebrew_dropin=$repo_root/quadlet/openclaw.container.d/10-homebrew-volume.conf
state_dropin=$repo_root/quadlet/openclaw.container.d/20-state-path.conf
socket_dropin=$repo_root/quadlet/optional-podman-socket/openclaw.container.d/30-podman-socket.conf

require_file() {
  [ -f "$1" ] || fail "missing required file: ${1#"$repo_root"/}"
}

require_section_count() {
  file=$1
  section=$2
  expected_count=$3
  actual_count=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "[$section]" ]; then
      actual_count=$((actual_count + 1))
    fi
  done < "$file"

  [ "$actual_count" -eq "$expected_count" ] ||
    fail "${file#"$repo_root"/}: expected $expected_count [$section] section(s), found $actual_count"
}

require_key_count() {
  file=$1
  section=$2
  key=$3
  expected_count=$4
  current_section=
  actual_count=0

  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      \[*\]) current_section=$line ;;
    esac

    if [ "$current_section" = "[$section]" ]; then
      case $line in
        "$key"=*) actual_count=$((actual_count + 1)) ;;
      esac
    fi
  done < "$file"

  [ "$actual_count" -eq "$expected_count" ] ||
    fail "${file#"$repo_root"/}: expected $expected_count $key directive(s) in [$section], found $actual_count"
}

require_line_once() {
  file=$1
  section=$2
  expected_line=$3
  current_section=
  actual_count=0

  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      \[*\]) current_section=$line ;;
    esac

    if [ "$current_section" = "[$section]" ] && [ "$line" = "$expected_line" ]; then
      actual_count=$((actual_count + 1))
    fi
  done < "$file"

  [ "$actual_count" -eq 1 ] ||
    fail "${file#"$repo_root"/}: expected exactly once in [$section]: $expected_line"
}

require_absent_text() {
  file=$1
  forbidden_text=$2

  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *"$forbidden_text"*)
        fail "${file#"$repo_root"/}: privileged socket setting found in the normal drop-in directory: $forbidden_text"
        ;;
    esac
  done < "$file"
}

for file in "$homebrew_volume" "$homebrew_dropin" "$state_dropin" "$socket_dropin"; do
  require_file "$file"
done

# Preserve the existing optional Homebrew named-volume unit and mount.
require_section_count "$homebrew_volume" Unit 1
require_section_count "$homebrew_volume" Volume 1
require_key_count "$homebrew_volume" Unit Description 1
require_line_once "$homebrew_volume" Unit 'Description=Persistent Homebrew prefix for OpenClaw'
require_key_count "$homebrew_volume" Volume VolumeName 1
require_line_once "$homebrew_volume" Volume 'VolumeName=openclaw-homebrew'

require_section_count "$homebrew_dropin" Container 1
require_key_count "$homebrew_dropin" Container Volume 1
require_line_once "$homebrew_dropin" Container 'Volume=openclaw-homebrew.volume:/home/linuxbrew/.linuxbrew'

# The normal state drop-in aligns host and container state without fixed users.
require_section_count "$state_dropin" Container 1
require_key_count "$state_dropin" Container Volume 2
require_line_once "$state_dropin" Container 'Volume=%h/.openclaw:%h/.openclaw:Z'
require_line_once "$state_dropin" Container 'Volume=%h/.cache:%h/.cache:Z'
require_key_count "$state_dropin" Container Environment 2
require_line_once "$state_dropin" Container 'Environment=HOME=%h'
require_line_once "$state_dropin" Container 'Environment=NPM_CONFIG_CACHE=%h/.openclaw/.npm'

# The privileged socket integration must remain complete and physically opt-in.
require_section_count "$socket_dropin" Unit 1
require_key_count "$socket_dropin" Unit Requires 1
require_line_once "$socket_dropin" Unit 'Requires=podman.socket'
require_key_count "$socket_dropin" Unit After 1
require_line_once "$socket_dropin" Unit 'After=podman.socket'
require_section_count "$socket_dropin" Container 1
require_key_count "$socket_dropin" Container Volume 1
require_line_once "$socket_dropin" Container 'Volume=%t/podman/podman.sock:/run/podman/podman.sock:rw'
require_key_count "$socket_dropin" Container Environment 2
require_line_once "$socket_dropin" Container 'Environment=CONTAINER_HOST=unix:///run/podman/podman.sock'
require_line_once "$socket_dropin" Container 'Environment=DOCKER_HOST=unix:///run/podman/podman.sock'
require_key_count "$socket_dropin" Container SecurityLabelDisable 1
require_line_once "$socket_dropin" Container 'SecurityLabelDisable=true'

for file in "$repo_root"/quadlet/openclaw.container.d/*.conf; do
  require_absent_text "$file" '/run/podman/podman.sock'
  require_absent_text "$file" 'CONTAINER_HOST='
  require_absent_text "$file" 'DOCKER_HOST='
  require_absent_text "$file" 'SecurityLabelDisable='
done

printf 'Quadlet validation passed.\n'
