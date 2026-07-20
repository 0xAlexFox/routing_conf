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
grep -qx 'block-quic = all-proxy' "$config" || fail "proxy QUIC fallback setting is missing"
grep -q '^always-raw-tcp-hosts = .*\*\.whatsapp\.com:443' "$config" || \
  fail "WhatsApp raw TCP setting is missing"

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

grep -qx 'DOMAIN-SUFFIX,telegram-cdn.org' "$project_dir/rules/proxy-domains.list" || \
  fail "Telegram CDN domain rule is missing"
grep -qx 'DOMAIN-SUFFIX,fbcdn.net' "$project_dir/rules/proxy-domains.list" || \
  fail "WhatsApp/Meta CDN domain rule is missing"
grep -qx 'IP-CIDR,185.76.151.0/24' "$project_dir/rules/proxy-ips.list" || \
  fail "Telegram CDN IP rule is missing"
grep -qx 'IP-CIDR,157.240.0.0/17' "$project_dir/rules/proxy-ips.list" || \
  fail "WhatsApp/Meta IP rule is missing"

for profile in "$project_dir/happ/routing.json" "$project_dir/incy/routing.json"; do
  if command -v jq >/dev/null 2>&1; then
    jq -e \
      --rawfile proxy_domains "$project_dir/rules/proxy-domains.list" \
      --rawfile proxy_ips "$project_dir/rules/proxy-ips.list" \
      --rawfile apple_proxy "$project_dir/rules/proxy-apple-services.list" '
      def active($rules):
        $rules
        | split("\n")
        | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
        | map(select(length > 0))
        | map(select(startswith("#") | not));
      def sites($rules):
        active($rules)
        | map(split(","))
        | map(if .[0] == "DOMAIN" then "full:" + .[1]
              elif .[0] == "DOMAIN-SUFFIX" then "domain:" + .[1]
              else error("unsupported domain rule") end);
      def ips($rules): active($rules) | map(split(",")[1]);

      (sites($proxy_domains) + sites($apple_proxy) + ["geosite:russia-inside"]) as $expected_sites
      | ips($proxy_ips) as $expected_ips
      |
      .GlobalProxy == "false" and
      .RouteOrder == "block-proxy-direct" and
      ((.ProxySites | sort) == ($expected_sites | sort)) and
      ((.ProxyIp | sort) == ($expected_ips | sort)) and
      ((.ProxySites | unique | length) == (.ProxySites | length)) and
      ((.ProxyIp | unique | length) == (.ProxyIp | length)) and
      (.DirectIp | index("17.0.0.0/8") != null) and
      (.LastUpdated | test("^[0-9]+$"))
    ' "$profile" >/dev/null || fail "invalid or incomplete routing profile in $profile"
  fi
done

echo "Configuration and local rule files are valid."
