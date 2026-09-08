#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 UPSTREAM_DOCKERFILE OUTPUT_DOCKERFILE" >&2
  exit 2
fi

upstream_dockerfile=$1
output_dockerfile=$2
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
homebrew_layer="$script_dir/../docker/homebrew.Dockerfile"

if [ ! -f "$upstream_dockerfile" ]; then
  echo "upstream Dockerfile not found: $upstream_dockerfile" >&2
  exit 1
fi

if [ ! -f "$homebrew_layer" ]; then
  echo "Homebrew layer not found: $homebrew_layer" >&2
  exit 1
fi

if [ "$upstream_dockerfile" = "$output_dockerfile" ]; then
  echo "output Dockerfile must differ from the upstream Dockerfile" >&2
  exit 1
fi

output_dir=$(dirname -- "$output_dockerfile")
mkdir -p "$output_dir"
temporary_dockerfile="${output_dockerfile}.tmp"
trap 'rm -f "$temporary_dockerfile"' EXIT HUP INT TERM

{
  cat "$upstream_dockerfile"
  cat "$homebrew_layer"
} > "$temporary_dockerfile"

mv "$temporary_dockerfile" "$output_dockerfile"
trap - EXIT HUP INT TERM
