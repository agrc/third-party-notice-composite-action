#!/bin/bash
# Test suite for third-party-notice-composite-action
# Run with: ./test/run-tests.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR/tmp"
PASS=0
FAIL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  # Set GITHUB_ACTION_PATH to the action directory for config.json access
  export GITHUB_ACTION_PATH="$ACTION_DIR"
}

teardown() {
  cd "$SCRIPT_DIR"
  rm -rf "$TEST_DIR"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" == "$actual" ]; then
    echo -e "${GREEN}✓${NC} $message"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if echo "$haystack" | grep -q "$needle"; then
    echo -e "${GREEN}✓${NC} $message"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected to contain: $needle"
    echo "  Actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

run_action_script() {
  # Run the action's shell script with the provided environment variables
  # Parse inputs into JSON array
  inputs_json=$(echo "$INPUTS" | grep -v '^$' | jq -R -s 'split("\n") | map(select(length > 0) | gsub("^\\s+|\\s+$";"") | select(length > 0) | gsub("^- ";""))')

  # Parse exclude patterns into JSON array
  exclude_json=$(echo "$EXCLUDE" | grep -v '^$' | jq -R -s 'split("\n") | map(select(length > 0) | gsub("^\\s+|\\s+$";"") | select(length > 0) | gsub("^- ";""))')

  # Build replacements object from array format
  # Format expected:
  # - package: pkg-name
  #   license: https://...
  if [ -n "$REPLACEMENTS" ] && [ "$REPLACEMENTS" != "" ]; then
    replace_json=$(echo "$REPLACEMENTS" | awk '
      /package:/ {
        gsub(/.*package:/, "")
        gsub(/^[ \t]+/, "")
        gsub(/[ \t]+$/, "")
        pkg=$0
      }
      /license:/ {
        gsub(/.*license:/, "")
        gsub(/^[ \t]+/, "")
        gsub(/[ \t]+$/, "")
        print "{\"" pkg "\": \"" $0 "\"}"
      }
    ' | jq -s 'add // {}')
  else
    replace_json='{}'
  fi

  # Merge with existing config.json replacements
  if [ -f "${GITHUB_ACTION_PATH}/config.json" ]; then
    existing_replace=$(jq '.replace // {}' "${GITHUB_ACTION_PATH}/config.json")
    replace_json=$(echo "$existing_replace $replace_json" | jq -s 'add')
  fi

  # Create the glf.json configuration file
  jq -n \
    --argjson inputs "$inputs_json" \
    --arg output "$OUTPUT" \
    --argjson exclude "$exclude_json" \
    --argjson replace "$replace_json" \
    '{
      inputs: $inputs,
      output: $output,
      overwrite: true,
      ci: true,
      exclude: $exclude,
      omitVersions: true,
      replace: $replace
    }' > glf.json
}

# ==============================================================================
# TEST 1: No advanced options - should create same config as in config.json
# ==============================================================================
test_no_advanced_options() {
  echo ""
  echo "📋 Test 1: No advanced options (defaults match config.json)"
  echo "-------------------------------------------------------------"

  setup

  # Set default values (simulating action defaults)
  export INPUTS="package.json"
  export OUTPUT="./public/ThirdPartyNotices.txt"
  export REPLACEMENTS=""
  export EXCLUDE="/^@ugrc\/.*\$/"

  run_action_script

  # Verify file was created
  assert_equals "true" "$([ -f glf.json ] && echo true || echo false)" "glf.json file was created"

  # Verify inputs match config.json
  local inputs_count=$(jq '.inputs | length' glf.json)
  assert_equals "1" "$inputs_count" "One input configured"
  local inputs_value=$(jq -r '.inputs[0]' glf.json)
  assert_equals "package.json" "$inputs_value" "Input is package.json (matches config.json)"

  # Verify output matches config.json
  local output_value=$(jq -r '.output' glf.json)
  assert_equals "./public/ThirdPartyNotices.txt" "$output_value" "Output path matches config.json"

  # Verify hardcoded values match config.json
  assert_equals "true" "$(jq -r '.overwrite' glf.json)" "overwrite is true (matches config.json)"
  assert_equals "true" "$(jq -r '.ci' glf.json)" "ci is true (matches config.json)"
  assert_equals "true" "$(jq -r '.omitVersions' glf.json)" "omitVersions is true (matches config.json)"

  # Verify exclude matches config.json default
  local exclude_count=$(jq '.exclude | length' glf.json)
  assert_equals "1" "$exclude_count" "One exclude pattern configured"
  local exclude_value=$(jq -r '.exclude[0]' glf.json)
  assert_contains "$exclude_value" "@ugrc" "Exclude pattern contains @ugrc (matches config.json)"

  # Verify replacements match config.json exactly
  local replace_count=$(jq '.replace | keys | length' glf.json)
  assert_equals "3" "$replace_count" "Three replacements from config.json"

  local esri_fetch=$(jq -r '.replace["@esri/arcgis-rest-fetch"]' glf.json)
  assert_equals "https://raw.githubusercontent.com/Esri/arcgis-rest-js/main/LICENSE" "$esri_fetch" "@esri/arcgis-rest-fetch replacement matches config.json"

  local esri_form=$(jq -r '.replace["@esri/arcgis-rest-form-data"]' glf.json)
  assert_equals "https://raw.githubusercontent.com/Esri/arcgis-rest-js/main/LICENSE" "$esri_form" "@esri/arcgis-rest-form-data replacement matches config.json"

  local type_fest=$(jq -r '.replace["type-fest"]' glf.json)
  assert_equals "https://raw.githubusercontent.com/sindresorhus/type-fest/main/license-mit" "$type_fest" "type-fest replacement matches config.json"

  teardown
}

# ==============================================================================
# TEST 2: All advanced options - should overwrite and merge all relevant options
# ==============================================================================
test_all_advanced_options() {
  echo ""
  echo "📋 Test 2: All advanced options (overwrite and merge)"
  echo "-------------------------------------------------------"

  setup

  # Set custom values for ALL options
  export INPUTS="package.json
functions/package.json
api/package.json"
  export OUTPUT="./dist/ThirdPartyNotices.txt"
  export REPLACEMENTS="- package: my-custom-package
  license: https://example.com/LICENSE
- package: another-package
  license: https://another.com/LICENSE
- package: @esri/arcgis-rest-fetch
  license: https://my-override.com/LICENSE"
  export EXCLUDE="/^@ugrc\/.*\$/
/^@my-org\/.*\$/
/^internal-.*\$/"

  run_action_script

  # Verify file was created
  assert_equals "true" "$([ -f glf.json ] && echo true || echo false)" "glf.json file was created"

  # --- INPUTS: Should be overwritten ---
  local inputs_count=$(jq '.inputs | length' glf.json)
  assert_equals "3" "$inputs_count" "Three inputs configured (overwritten)"
  assert_equals "package.json" "$(jq -r '.inputs[0]' glf.json)" "First input is package.json"
  assert_equals "functions/package.json" "$(jq -r '.inputs[1]' glf.json)" "Second input is functions/package.json"
  assert_equals "api/package.json" "$(jq -r '.inputs[2]' glf.json)" "Third input is api/package.json"

  # --- OUTPUT: Should be overwritten ---
  local output_value=$(jq -r '.output' glf.json)
  assert_equals "./dist/ThirdPartyNotices.txt" "$output_value" "Output path is overwritten"

  # --- EXCLUDE: Should be overwritten ---
  local exclude_count=$(jq '.exclude | length' glf.json)
  assert_equals "3" "$exclude_count" "Three exclude patterns configured (overwritten)"
  assert_contains "$(jq -r '.exclude[0]' glf.json)" "@ugrc" "First exclude pattern contains @ugrc"
  assert_contains "$(jq -r '.exclude[1]' glf.json)" "@my-org" "Second exclude pattern contains @my-org"
  assert_contains "$(jq -r '.exclude[2]' glf.json)" "internal-" "Third exclude pattern contains internal-"

  # --- REPLACEMENTS: Should be merged (config.json + user) with user taking precedence ---
  local replace_count=$(jq '.replace | keys | length' glf.json)
  assert_equals "5" "$replace_count" "Five total replacements (3 from config.json + 2 new, 1 override)"

  # Original config.json replacements preserved (except overridden one)
  local esri_form=$(jq -r '.replace["@esri/arcgis-rest-form-data"]' glf.json)
  assert_equals "https://raw.githubusercontent.com/Esri/arcgis-rest-js/main/LICENSE" "$esri_form" "@esri/arcgis-rest-form-data preserved from config.json"

  local type_fest=$(jq -r '.replace["type-fest"]' glf.json)
  assert_equals "https://raw.githubusercontent.com/sindresorhus/type-fest/main/license-mit" "$type_fest" "type-fest preserved from config.json"

  # New user replacements added
  local custom_pkg=$(jq -r '.replace["my-custom-package"]' glf.json)
  assert_equals "https://example.com/LICENSE" "$custom_pkg" "my-custom-package added from user input"

  local another_pkg=$(jq -r '.replace["another-package"]' glf.json)
  assert_equals "https://another.com/LICENSE" "$another_pkg" "another-package added from user input"

  # User replacement overrides config.json value
  local esri_fetch=$(jq -r '.replace["@esri/arcgis-rest-fetch"]' glf.json)
  assert_equals "https://my-override.com/LICENSE" "$esri_fetch" "@esri/arcgis-rest-fetch overridden by user input"

  # --- Hardcoded values should still be correct ---
  assert_equals "true" "$(jq -r '.overwrite' glf.json)" "overwrite is true"
  assert_equals "true" "$(jq -r '.ci' glf.json)" "ci is true"
  assert_equals "true" "$(jq -r '.omitVersions' glf.json)" "omitVersions is true"

  teardown
}

# ==============================================================================
# Run all tests
# ==============================================================================
echo "🧪 Running third-party-notice-composite-action tests"
echo "======================================================"

test_no_advanced_options
test_all_advanced_options

echo ""
echo "======================================================"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "======================================================"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
