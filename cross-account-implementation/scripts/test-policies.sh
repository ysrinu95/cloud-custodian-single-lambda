#!/bin/bash
# Cloud Custodian Policy Testing Script
# Tests each policy file for syntax validation and dry-run execution

POLICY_DIR="../policies"
OUTPUT_DIR="../output"
TEST_RESULTS="./policy-test-results.txt"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================" > $TEST_RESULTS
echo "Cloud Custodian Policy Testing Report" >> $TEST_RESULTS
echo "Test Date: $(date)" >> $TEST_RESULTS
echo "========================================" >> $TEST_RESULTS
echo "" >> $TEST_RESULTS

TOTAL_POLICIES=0
VALID_POLICIES=0
FAILED_POLICIES=0

# Test each policy file
for policy_file in $POLICY_DIR/aws-*.yml; do
    filename=$(basename "$policy_file")
    echo ""
    echo -e "${YELLOW}Testing: $filename${NC}"
    echo "========================================" >> $TEST_RESULTS
    echo "Policy File: $filename" >> $TEST_RESULTS
    echo "----------------------------------------" >> $TEST_RESULTS
    
    # Count policies in file
    policy_count=$(grep -c "^  - name:" "$policy_file" 2>/dev/null || echo "0")
    TOTAL_POLICIES=$((TOTAL_POLICIES + policy_count))
    echo "Number of policies: $policy_count" >> $TEST_RESULTS
    
    # Validate YAML syntax
    echo "1. YAML Validation..." | tee -a $TEST_RESULTS
    if custodian validate "$policy_file" 2>&1 | tee -a $TEST_RESULTS; then
        echo -e "${GREEN}✓ YAML validation passed${NC}"
        echo "✓ YAML validation: PASSED" >> $TEST_RESULTS
        
        # Try dry-run
        echo "2. Dry-run execution..." | tee -a $TEST_RESULTS
        if custodian run -s "$OUTPUT_DIR/test-$(basename $policy_file .yml)" "$policy_file" --dryrun 2>&1 | tee -a $TEST_RESULTS; then
            echo -e "${GREEN}✓ Dry-run successful${NC}"
            echo "✓ Dry-run: PASSED" >> $TEST_RESULTS
            VALID_POLICIES=$((VALID_POLICIES + policy_count))
        else
            echo -e "${RED}✗ Dry-run failed${NC}"
            echo "✗ Dry-run: FAILED" >> $TEST_RESULTS
            FAILED_POLICIES=$((FAILED_POLICIES + policy_count))
        fi
    else
        echo -e "${RED}✗ YAML validation failed${NC}"
        echo "✗ YAML validation: FAILED" >> $TEST_RESULTS
        FAILED_POLICIES=$((FAILED_POLICIES + policy_count))
    fi
    
    echo "" >> $TEST_RESULTS
done

# Summary
echo ""
echo "========================================" | tee -a $TEST_RESULTS
echo "TEST SUMMARY" | tee -a $TEST_RESULTS
echo "========================================" | tee -a $TEST_RESULTS
echo "Total Policies: $TOTAL_POLICIES" | tee -a $TEST_RESULTS
echo "Valid Policies: $VALID_POLICIES" | tee -a $TEST_RESULTS
echo "Failed Policies: $FAILED_POLICIES" | tee -a $TEST_RESULTS
echo "Success Rate: $(awk "BEGIN {printf \"%.2f\", ($VALID_POLICIES/$TOTAL_POLICIES)*100}")%" | tee -a $TEST_RESULTS
echo "" | tee -a $TEST_RESULTS

if [ $FAILED_POLICIES -eq 0 ]; then
    echo -e "${GREEN}All policies passed testing!${NC}" | tee -a $TEST_RESULTS
else
    echo -e "${RED}Some policies failed. Check $TEST_RESULTS for details.${NC}"
fi

echo ""
echo "Full test results saved to: $TEST_RESULTS"
