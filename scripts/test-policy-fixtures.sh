#!/usr/bin/env bash
set -euo pipefail

opa test policies/opa -v

opa eval --format=json --data policies/opa \
  --input examples/06-plan-json/safe-plan.json \
  'data.terraform.guard.deny' | jq -e '.result[0].expressions[0].value == []'

for fixture in examples/06-plan-json/dangerous-*-plan.json; do
  # Assert a policy denial, not merely a nonzero exit from a broken OPA command.
  opa eval --format=json --data policies/opa --input "$fixture" \
    'data.terraform.guard.deny' | jq -e '.result[0].expressions[0].value | length > 0'
  echo "Denied as expected: $fixture"
done
