#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 GITHUB_OWNER [REPOSITORY] [BRANCH]" >&2
  exit 2
}

[ "$#" -ge 1 ] && [ "$#" -le 3 ] || usage

owner=$1
repository=${2:-routing}
branch=${3:-main}

case "$owner/$repository/$branch" in
  *[!A-Za-z0-9._/-]*)
    echo "Owner, repository and branch may contain only GitHub-safe characters." >&2
    exit 2
    ;;
esac

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
template="$project_dir/routing.conf.template"
output="$project_dir/routing.conf"
raw_base="https://raw.githubusercontent.com/$owner/$repository/$branch"
temp_file=$(mktemp "${TMPDIR:-/tmp}/routing.conf.XXXXXX")
trap 'rm -f "$temp_file"' EXIT HUP INT TERM

sed "s|__RAW_BASE_URL__|$raw_base|g" "$template" > "$temp_file"
mv "$temp_file" "$output"
trap - EXIT HUP INT TERM

"$project_dir/scripts/validate.sh"

echo "Created $output"
echo "Shadowrocket URL: $raw_base/routing.conf"
