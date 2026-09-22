#!/usr/bin/env bash
# Latency / CDN test: shows timings and which CloudFront edge location (POP)
# answered, and whether the response came from the edge cache.
set -euo pipefail

URL=$(terraform output -raw website_url)
for i in 1 2 3; do
  echo "--- Request ${i}"
  curl -s -o /dev/null -D - "${URL}/" | grep -iE '^(x-cache|x-amz-cf-pop|age|strict-transport-security):' || true
  curl -s -o /dev/null -w 'DNS %{time_namelookup}s | TLS done %{time_appconnect}s | first byte %{time_starttransfer}s | total %{time_total}s\n' "${URL}/"
done
echo "Tip: 'Hit from cloudfront' = served from the edge cache; x-amz-cf-pop = edge location code (e.g. FRA56)."
echo "For a worldwide view, test the URL with a free global tool such as https://tools.keycdn.com/performance"
