#!/usr/bin/env bash
# Usage: scripts/check_log.sh <logfile>
# Exit 0 only if the log shows a pass and no error of any kind.
set -u
log="${1:?usage: check_log.sh <logfile>}"
[ -f "$log" ] || { echo "check_log: $log not found"; exit 2; }

fail=0
grep -n "SVA:" "$log" && { echo "check_log: assertion failure"; fail=1; }
grep -nE "UVM_(ERROR|FATAL) *: *[1-9]" "$log" && { echo "check_log: UVM errors"; fail=1; }
grep -nE "TEST FAILED|%Error|^ERROR:|FATAL_ERROR" "$log" && { echo "check_log: failure message"; fail=1; }
if ! grep -qE "TEST PASSED|UVM_ERROR *: *0" "$log"; then
  echo "check_log: no pass marker"; fail=1
fi

if [ $fail -eq 0 ]; then echo "PASS  $log"; else echo "FAIL  $log"; fi
exit $fail
