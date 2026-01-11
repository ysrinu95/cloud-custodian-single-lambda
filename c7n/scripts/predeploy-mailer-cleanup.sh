#!/usr/bin/env bash
set -euo pipefail

# predeploy-mailer-cleanup.sh
# Usage:
#   predeploy-mailer-cleanup.sh --disable true --delete true --regions us-east-1,us-west-2 --account 123456789012

DISABLE_RULES=${1:-}
DELETE_MAILER=${2:-}

# Allow both long form or positional parsing
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --disable)
      DISABLE_RULES="$2"; shift 2;;
    --delete)
      DELETE_MAILER="$2"; shift 2;;
    --regions)
      REGIONS="$2"; shift 2;;
    --account)
      ACCOUNT_ID="$2"; shift 2;;
    *)
      echo "Unknown arg: $1"; shift;;
  esac
done

if [ -z "${REGIONS:-}" ] || [ -z "${ACCOUNT_ID:-}" ]; then
  echo "Usage: $0 --disable true|false --delete true|false --regions <r1,r2> --account <account-id>"
  exit 2
fi

IFS=',' read -ra REGION_LIST <<< "${REGIONS}"
for R in "${REGION_LIST[@]}"; do
  echo "🌐 Processing region: ${R}"

  if [ "${DISABLE_RULES}" = 'true' ]; then
    echo "🛑 Disabling CloudWatch Event rules that target cloud-custodian-mailer in ${R}"
    RULES=$(aws events list-rule-names-by-target --target-arn arn:aws:lambda:${R}:${ACCOUNT_ID}:function:cloud-custodian-mailer --region ${R} --output text 2>/dev/null || true)
    if [ -n "${RULES}" ]; then
      for RULE in ${RULES}; do
        echo "   Disabling rule: ${RULE}"
        aws events disable-rule --name "${RULE}" --region ${R} || echo "⚠️ Failed to disable ${RULE} in ${R}"
      done
    else
      echo "   No event rules found targeting mailer in ${R}"
    fi
  fi

  if [ "${DELETE_MAILER}" = 'true' ]; then
    echo "🗑️ Deleting existing Lambda: cloud-custodian-mailer in ${R} (if present)"
    if aws lambda get-function --function-name cloud-custodian-mailer --region ${R} >/dev/null 2>&1; then
      aws lambda delete-function --function-name cloud-custodian-mailer --region ${R} && echo "   ✅ Deleted mailer in ${R}" || echo "   ⚠️ Failed to delete mailer in ${R}"
    else
      echo "   Mailer not found in ${R}"
    fi
  fi
done

echo "✅ Pre-deploy mailer cleanup completed"
