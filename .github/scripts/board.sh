#!/usr/bin/env bash
# The design board must declare UTF-8, be well-formed enough for libxml2's HTML parser,
# and load scripts and styles only from Google Fonts and cdnjs.
set -euo pipefail
shopt -s nullglob
pages=(docs/design/*.html)
[ ${#pages[@]} -gt 0 ] || { echo "No board yet."; exit 0; }
fail=0
for p in "${pages[@]}"; do
  grep -qi '<meta charset="utf-8">' "$p" || { echo "::error file=$p::missing <meta charset=\"utf-8\">"; fail=1; }
  if command -v xmllint >/dev/null; then
    xmllint --html --noout "$p" 2>&1 | grep -E 'parser error' && { echo "::error file=$p::HTML does not parse"; fail=1; }
  fi
  grep -oE '<(script|link)[^>]+(src|href)="https?://[^"]+"' "$p" | grep -oE 'https?://[^"]+' |
    grep -vE '^https://(fonts\.googleapis\.com|fonts\.gstatic\.com|cdnjs\.cloudflare\.com)/' |
    while read -r url; do echo "::error file=$p::loads $url"; done | grep . && fail=1
done
exit $fail
