#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config="$project_dir/routing.conf"
allow_placeholder=false

if [ "${1:-}" = "--allow-placeholder" ]; then
  allow_placeholder=true
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--allow-placeholder]" >&2
  exit 2
fi

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f "$config" ] || fail "routing.conf is missing"
grep -qx '\[General\]' "$config" || fail "[General] section is missing"
grep -qx '\[Rule\]' "$config" || fail "[Rule] section is missing"
grep -qx 'FINAL,DIRECT' "$config" || fail "FINAL,DIRECT is missing"

if [ "$allow_placeholder" = false ] && grep -q 'CHANGE_ME\|__RAW_BASE_URL__' "$config"; then
  fail "run scripts/configure.sh with your GitHub owner before publishing"
fi

update_url=$(sed -n 's/^update-url = //p' "$config")
[ -n "$update_url" ] || fail "update-url is missing"
raw_base=${update_url%/routing.conf}
grep -Fqx "RULE-SET,$raw_base/rules/proxy-domains.list,PROXY,force-remote-dns" "$config" || \
  fail "proxy-domains.list URL does not match update-url"
grep -Fqx "RULE-SET,$raw_base/rules/proxy-ips.list,PROXY,no-resolve" "$config" || \
  fail "proxy-ips.list URL does not match update-url"
grep -Fqx "RULE-SET,$raw_base/rules/direct-apple.list,DIRECT,no-resolve" "$config" || \
  fail "direct-apple.list URL does not match update-url"
grep -Fqx "RULE-SET,$raw_base/rules/proxy-apple-services.list,PROXY,force-remote-dns" "$config" || \
  fail "proxy-apple-services.list URL does not match update-url"

validate_rule_file() {
  rule_file=$1
  awk '
    /^[[:space:]]*($|#)/ { next }
    /^(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|IP-CIDR|IP-CIDR6),[^,[:space:]]+$/ { next }
    { print FNR ":" $0; bad=1 }
    END { exit bad }
  ' "$rule_file" || fail "invalid rule syntax in $rule_file"

  duplicates=$(grep -vE '^[[:space:]]*($|#)' "$rule_file" | sort | uniq -d || true)
  [ -z "$duplicates" ] || fail "duplicate rules in $rule_file: $duplicates"
}

validate_rule_file "$project_dir/rules/proxy-domains.list"
validate_rule_file "$project_dir/rules/proxy-ips.list"
validate_rule_file "$project_dir/rules/direct-apple.list"
validate_rule_file "$project_dir/rules/proxy-apple-services.list"

echo "Configuration and local rule files are valid."
