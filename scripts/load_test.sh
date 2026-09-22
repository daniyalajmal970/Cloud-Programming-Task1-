#!/usr/bin/env bash
# Autoscaling test: generate load on the uncached /whoami.html page with many
# parallel curl workers and watch the Auto Scaling Group add instances.
# Needs only curl + AWS CLI (no extra tools). Works in Git Bash, macOS, Linux.
# Usage: ./scripts/load_test.sh [minutes, default 8] [parallel workers, default 30]
set -uo pipefail

MINUTES=${1:-8}
MINUTES=${MINUTES%m}            # accept "8" or "8m"
WORKERS=${2:-30}
URL=$(terraform output -raw whoami_url)
ASG=$(terraform output -raw autoscaling_group_name)
END=$(( $(date +%s) + MINUTES * 60 ))
RESULT_DIR=$(mktemp -d)

show_capacity() {
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" \
    --query 'AutoScalingGroups[0].[DesiredCapacity, length(Instances)]' --output text
}

worker() {
  local ok=0 fail=0 code
  while [ "$(date +%s)" -lt "${END}" ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${URL}")
    if [ "${code}" = "200" ]; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  done
  echo "${ok} ${fail}" > "${RESULT_DIR}/worker_$1"
}

echo "Desired capacity / running instances before: $(show_capacity)"
echo ">>> Sending load to ${URL} for ${MINUTES} min with ${WORKERS} parallel workers"
for i in $(seq 1 "${WORKERS}"); do worker "${i}" & done

while [ "$(date +%s)" -lt "${END}" ]; do
  printf '%s  desired/running: %s\n' "$(date +%T)" "$(show_capacity)"
  sleep 30
done
wait

OK=0; FAIL=0
for f in "${RESULT_DIR}"/worker_*; do
  read -r o fl < "${f}"; OK=$((OK + o)); FAIL=$((FAIL + fl))
done
TOTAL=$((OK + FAIL))
echo ">>> Load test finished: ${TOTAL} requests, ${OK} successful (HTTP 200), ${FAIL} failed" | tee load_test_result.txt
echo "Desired capacity / running instances after: $(show_capacity)" | tee -a load_test_result.txt
rm -rf "${RESULT_DIR}"

echo ">>> Scaling activities:"
aws autoscaling describe-scaling-activities --auto-scaling-group-name "${ASG}" --max-items 6 \
  --query 'Activities[].[StartTime,StatusCode,Description]' --output table
echo "The group scales back in automatically ~15 minutes after the load stops."