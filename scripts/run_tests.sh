#!/bin/bash

set -e

tests_output=$(scarb run test || true)

# Extract summary information
echo "::group::Summary"

tests_passed=$(echo "$tests_output" | awk '/Tests:/{print $2}')
tests_failed=$(echo "$tests_output" | awk '/Tests:/{print $4}')
skipped_count=$(echo "$tests_output" | awk '/Tests:/{print $6}')
ignored_count=$(echo "$tests_output" | awk '/Tests:/{print $6}')
filtered_out_count=$(echo "$tests_output" | awk '/Tests:/{print $6}')

echo "Total passed tests: $tests_passed"
echo "Total failed tests: $tests_failed"
echo "Total skipped tests: $skipped_count"
echo "Total ignored tests: $ignored_count"
echo "Total filtered out tests: $filtered_out_count"
echo "::endgroup::"

# Check if any test failed
if [ "$tests_failed" -gt 0 ]; then
  failed_tests=$(echo "$tests_output" | awk '/Failures:/{flag=1;next}/^\s*$/{flag=0}flag')
  echo "::error::Tests failed:"
  echo "$failed_tests"
  exit 1
fi

# Generate badge markdown
badge="[![Tests](https://img.shields.io/badge/Tests-${tests_passed}%20passed-brightgreen)](README.md)"

# Replace or add the badge below "## About"
if grep -q '\[!\[Tests\]' README.md; then
  # Replace the existing badge
  sed -i "s|\[!\[Tests\].*|$badge|" README.md
else
  # Add the badge below "## About"
  sed -i "/## About/a \ \n$badge\n" README.md
fi
