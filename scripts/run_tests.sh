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
badge="[![Tests](https://img.shields.io/badge/Tests-Passed-brightgreen)](README.md)"

# Check if badge already exists in README
if ! grep -q '\[!\[Tests\]' README.md; then
  # Add badge markdown at the top if not present
  echo "$badge" > badge_temp
  sed -i '1s/^/'"$badge"'\n\n/' README.md
fi

# Update passed tests count in README
echo "Passed tests: $tests_passed" > temp_file
sed -i 's/\(Passed tests: \).*/\1'"$tests_passed"'/' README.md

# Clean up temporary files
rm temp_file badge_temp
