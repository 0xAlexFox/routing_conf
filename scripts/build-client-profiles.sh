#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
happ_json="$project_dir/happ/routing.json"
incy_json="$project_dir/incy/routing.json"

for profile in "$happ_json" "$incy_json"; do
  [ -f "$profile" ] || {
    echo "Missing profile: $profile" >&2
    exit 1
  }
done

timestamp=$(date +%s)
for profile in "$happ_json" "$incy_json"; do
  profile_tmp=$(mktemp "${TMPDIR:-/tmp}/routing-profile.XXXXXX")
  sed -E "s/\"LastUpdated\": \"[0-9]+\"/\"LastUpdated\": \"$timestamp\"/" "$profile" > "$profile_tmp"
  mv "$profile_tmp" "$profile"
done

encode_file() {
  base64 < "$1" | tr -d '\n'
}

happ_payload=$(encode_file "$happ_json")
incy_payload=$(encode_file "$incy_json")

printf '%s\n' "happ://routing/onadd/$happ_payload" > "$project_dir/happ/routing.deeplink"
printf '%s\n' "incy://routing/onadd/$incy_payload" > "$project_dir/incy/routing.deeplink"
printf '%s\n' "incy://autorouting/onadd/https://raw.githubusercontent.com/0xAlexFox/routing_conf/refs/heads/master/incy/routing.json" > "$project_dir/incy/autorouting.deeplink"

echo "Generated Happ and INCY deeplinks."
