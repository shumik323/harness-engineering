#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/layers.sh"
TPL="$HERE/../skeleton"
INSTANCE="${1:?usage: harness-status.sh <instance-path>}"

drift=0
echo "== CORE drift: $INSTANCE =="
for p in "${CORE_PATHS[@]}"; do
  tpl_file="$TPL/$p"; [ -f "$tpl_file" ] || tpl_file="$TPL/$p.template"
  inst_file="$INSTANCE/$p"
  if [ ! -f "$inst_file" ]; then echo "  MISSING  $p"; drift=1
  elif ! diff -q "$tpl_file" "$inst_file" >/dev/null 2>&1; then echo "  DIVERGED $p"; drift=1
  else echo "  ok       $p"; fi
done
[ "$drift" -eq 0 ] && echo "CORE clean" || echo "CORE drift detected"
exit "$drift"
