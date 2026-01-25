#!/bin/bash
# Bash script to run all integration tests on macOS/Linux
# Kills the test app between runs to avoid debug connection failures

set -o pipefail

# Auto-detect platform
case "$(uname -s)" in
    Darwin) DEVICE="macos" ;;
    Linux)  DEVICE="linux" ;;
    *)
        echo "Unsupported platform: $(uname -s)"
        echo "Use run_integration_tests_windows.ps1 for Windows"
        exit 1
        ;;
esac

TEST_FILES=(
    "smoke_test.dart"
    "app_test.dart"
    "database_test.dart"
    "error_handling_test.dart"
    "image_format_test.dart"
    "stabilization_test.dart"
    "video_compilation_test.dart"
    "e2e_workflow_test.dart"
)

PROCESS_NAME="agelapse"
PASSED=0
FAILED=0
FAILED_TESTS=()

echo ""
echo "========================================"
echo "  Running Integration Tests ($DEVICE)"
echo "========================================"
echo ""

for TEST_FILE in "${TEST_FILES[@]}"; do
    echo "=== $TEST_FILE ==="

    # Kill any existing app instance
    pkill -9 -f "$PROCESS_NAME" 2>/dev/null
    sleep 2

    # Run the test
    if flutter test "integration_test/$TEST_FILE" -d "$DEVICE"; then
        echo -e "\033[32mPASSED: $TEST_FILE\033[0m"
        ((PASSED++))
    else
        echo -e "\033[31mFAILED: $TEST_FILE\033[0m"
        ((FAILED++))
        FAILED_TESTS+=("$TEST_FILE")
    fi

    echo ""
done

# Final cleanup
pkill -9 -f "$PROCESS_NAME" 2>/dev/null

# Summary
echo ""
echo "========================================"
echo "            Test Summary"
echo "========================================"
echo -e "\033[32mPassed: $PASSED\033[0m"

if [ $FAILED -gt 0 ]; then
    echo -e "\033[31mFailed: $FAILED\033[0m"
    echo ""
    echo -e "\033[31mFailed tests:\033[0m"
    for FT in "${FAILED_TESTS[@]}"; do
        echo -e "\033[31m  - $FT\033[0m"
    done
    exit 1
else
    echo -e "\033[32mFailed: 0\033[0m"
    echo ""
    echo -e "\033[32mAll tests passed!\033[0m"
    exit 0
fi
