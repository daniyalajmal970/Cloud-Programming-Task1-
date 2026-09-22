#!/usr/bin/env bash
# High-availability test: terminate one web server and watch the site stay up
# while the Auto Scaling Group launches a replacement.
# Run from the terraform/ folder after `terraform apply`.
set -euo pipefail

URL=$(terraform output -raw whoami_url)
ASG=$(terraform output -raw autoscaling_group_name)

echo "Instances in ${ASG} before the test:"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output table

VICTIM=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
echo ">>> Terminating ${VICTIM} (simulated server failure)"
aws ec2 terminate-instances --instance-ids "${VICTIM}" --output text >/dev/null

echo ">>> Polling ${URL} for 3 minutes (status code + answering AZ):"
END=$((SECONDS + 180))
OK=0; FAIL=0
while [ ${SECONDS} -lt ${END} ]; do
  BODY=$(curl -s -w '\n%{http_code}' "${URL}" || true)
  CODE=$(echo "${BODY}" | tail -n1)
  AZ=$(echo "${BODY}" | grep -o 'eu-[a-z]*-[0-9][a-z]' | head -n1 || true)
  if [ "${CODE}" = "200" ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); fi
  printf '%s  HTTP %s  %s\n' "$(date +%T)" "${CODE}" "${AZ}"
  sleep 3
done
echo ">>> Result: ${OK} successful, ${FAIL} failed requests"

echo "Instances in ${ASG} after the test (a replacement should be launching/in service):"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output table
