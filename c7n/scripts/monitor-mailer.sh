#!/bin/bash
# Cloud Custodian Mailer Monitoring Script
# Monitors SQS queues, SES email status, and Lambda logs in real-time

set -e

# Configuration
AWS_REGION=${AWS_REGION:-us-west-2}
SQS_QUEUE_URL=${SQS_QUEUE_URL:-https://sqs.us-west-2.amazonaws.com/172327596604/c7n-mailer-test}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-cloud-custodian-mailer}
LOG_GROUP_NAME="/aws/lambda/$LAMBDA_FUNCTION_NAME"
REFRESH_INTERVAL=${REFRESH_INTERVAL:-10}
MONITORING_DURATION=${MONITORING_DURATION:-300}  # 5 minutes default

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}================================================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================================================${NC}"
}

print_section() {
    echo -e "\n${CYAN}📊 $1${NC}"
    echo -e "${CYAN}$(printf '%.0s-' {1..80})${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to check AWS connectivity
check_aws_connectivity() {
    print_section "AWS Connectivity Check"
    
    if aws sts get-caller-identity --region $AWS_REGION > /dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $AWS_REGION)
        print_success "Connected to AWS Account: $ACCOUNT_ID, Region: $AWS_REGION"
        return 0
    else
        print_error "Failed to connect to AWS. Check your credentials and region."
        return 1
    fi
}

# Function to monitor SQS queue
monitor_sqs_queue() {
    print_section "SQS Queue Status"
    
    # Extract queue name from URL
    QUEUE_NAME=$(basename "$SQS_QUEUE_URL")
    
    # Check if queue exists
    if aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" --region "$AWS_REGION" > /dev/null 2>&1; then
        # Get queue attributes
        ATTRIBUTES=$(aws sqs get-queue-attributes \
            --queue-url "$SQS_QUEUE_URL" \
            --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,ApproximateNumberOfMessagesDelayed \
            --region "$AWS_REGION" \
            --output json)
        
        VISIBLE_MESSAGES=$(echo "$ATTRIBUTES" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
        IN_FLIGHT_MESSAGES=$(echo "$ATTRIBUTES" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "0"')
        DELAYED_MESSAGES=$(echo "$ATTRIBUTES" | jq -r '.Attributes.ApproximateNumberOfMessagesDelayed // "0"')
        
        echo "📧 Queue: $QUEUE_NAME"
        echo "🔢 Messages Available: $VISIBLE_MESSAGES"
        echo "🔄 Messages In Flight: $IN_FLIGHT_MESSAGES"
        echo "⏰ Messages Delayed: $DELAYED_MESSAGES"
        
        if [ "$VISIBLE_MESSAGES" -gt 0 ]; then
            print_warning "$VISIBLE_MESSAGES messages waiting to be processed"
        elif [ "$IN_FLIGHT_MESSAGES" -gt 0 ]; then
            print_info "$IN_FLIGHT_MESSAGES messages currently being processed"
        else
            print_success "Queue is empty - all messages processed"
        fi
    else
        print_error "Queue not found: $SQS_QUEUE_URL"
    fi
}

# Function to check SES sending statistics
monitor_ses_statistics() {
    print_section "SES Sending Statistics (Last 24 Hours)"
    
    # Get sending statistics
    SES_STATS=$(aws ses get-send-statistics --region "$AWS_REGION" --output json 2>/dev/null || echo '{"SendDataPoints":[]}')
    
    if [ "$(echo "$SES_STATS" | jq '.SendDataPoints | length')" -gt 0 ]; then
        # Get the most recent data point
        LATEST_STATS=$(echo "$SES_STATS" | jq '.SendDataPoints | sort_by(.Timestamp) | last')
        
        DELIVERY_ATTEMPTS=$(echo "$LATEST_STATS" | jq -r '.DeliveryAttempts // 0')
        BOUNCES=$(echo "$LATEST_STATS" | jq -r '.Bounces // 0')
        COMPLAINTS=$(echo "$LATEST_STATS" | jq -r '.Complaints // 0')
        REJECTS=$(echo "$LATEST_STATS" | jq -r '.Rejects // 0')
        TIMESTAMP=$(echo "$LATEST_STATS" | jq -r '.Timestamp')
        
        echo "📊 Latest SES Statistics ($(date -d "$TIMESTAMP" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$TIMESTAMP")):"
        echo "📤 Delivery Attempts: $DELIVERY_ATTEMPTS"
        echo "↩️  Bounces: $BOUNCES"
        echo "🚫 Complaints: $COMPLAINTS"
        echo "❌ Rejects: $REJECTS"
        
        if [ "$BOUNCES" -gt 0 ] || [ "$COMPLAINTS" -gt 0 ] || [ "$REJECTS" -gt 0 ]; then
            print_warning "Issues detected in email delivery"
        else
            print_success "No delivery issues detected"
        fi
    else
        print_info "No SES statistics available for the last 24 hours"
    fi
}

# Function to check SES sending quota
check_ses_quota() {
    print_section "SES Sending Quota"
    
    SES_QUOTA=$(aws ses get-send-quota --region "$AWS_REGION" --output json 2>/dev/null || echo '{}')
    
    if [ "$(echo "$SES_QUOTA" | jq 'has("Max24HourSend")')" = "true" ]; then
        MAX_24_HOUR=$(echo "$SES_QUOTA" | jq -r '.Max24HourSend')
        MAX_SEND_RATE=$(echo "$SES_QUOTA" | jq -r '.MaxSendRate')
        SENT_24_HOUR=$(echo "$SES_QUOTA" | jq -r '.SentLast24Hours')
        
        echo "📈 24-Hour Limit: $MAX_24_HOUR emails"
        echo "⚡ Max Send Rate: $MAX_SEND_RATE emails/second"
        echo "📊 Sent Last 24h: $SENT_24_HOUR emails"
        
        PERCENTAGE_USED=$(echo "scale=1; $SENT_24_HOUR * 100 / $MAX_24_HOUR" | bc -l 2>/dev/null || echo "0")
        echo "💯 Quota Used: $PERCENTAGE_USED%"
        
        if (( $(echo "$PERCENTAGE_USED > 80" | bc -l 2>/dev/null || echo "0") )); then
            print_warning "High quota usage: $PERCENTAGE_USED%"
        else
            print_success "Quota usage normal: $PERCENTAGE_USED%"
        fi
    else
        print_info "SES quota information not available"
    fi
}

# Function to monitor Lambda function
monitor_lambda_function() {
    print_section "Lambda Function Status"
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
        LAMBDA_INFO=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --output json)
        
        STATE=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.State')
        LAST_MODIFIED=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.LastModified')
        RUNTIME=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.Runtime')
        MEMORY=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.MemorySize')
        TIMEOUT=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.Timeout')
        
        echo "🔧 Function: $LAMBDA_FUNCTION_NAME"
        echo "📊 State: $STATE"
        echo "⏰ Last Modified: $LAST_MODIFIED"
        echo "🐍 Runtime: $RUNTIME"
        echo "💾 Memory: ${MEMORY}MB"
        echo "⏱️  Timeout: ${TIMEOUT}s"
        
        if [ "$STATE" = "Active" ]; then
            print_success "Lambda function is active and ready"
        else
            print_warning "Lambda function state: $STATE"
        fi
    else
        print_error "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
}

# Function to get recent Lambda logs
get_recent_lambda_logs() {
    print_section "Recent Lambda Execution Logs"
    
    # Get log streams from the last hour
    START_TIME=$(date -d '1 hour ago' +%s)000
    
    # Get the most recent log stream
    LOG_STREAMS=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP_NAME" \
        --order-by LastEventTime \
        --descending \
        --max-items 3 \
        --region "$AWS_REGION" \
        --output json 2>/dev/null || echo '{"logStreams":[]}')
    
    if [ "$(echo "$LOG_STREAMS" | jq '.logStreams | length')" -gt 0 ]; then
        echo "📋 Recent Log Streams:"
        echo "$LOG_STREAMS" | jq -r '.logStreams[] | "  🕐 \(.logStreamName) (Last: \(.lastEventTimestamp | todate))"'
        
        # Get logs from the most recent stream
        LATEST_STREAM=$(echo "$LOG_STREAMS" | jq -r '.logStreams[0].logStreamName')
        
        if [ "$LATEST_STREAM" != "null" ] && [ -n "$LATEST_STREAM" ]; then
            echo ""
            echo "📄 Recent logs from: $LATEST_STREAM"
            echo "$(printf '%.0s-' {1..60})"
            
            RECENT_LOGS=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP_NAME" \
                --log-stream-name "$LATEST_STREAM" \
                --start-time "$START_TIME" \
                --region "$AWS_REGION" \
                --output json 2>/dev/null || echo '{"events":[]}')
            
            if [ "$(echo "$RECENT_LOGS" | jq '.events | length')" -gt 0 ]; then
                echo "$RECENT_LOGS" | jq -r '.events[] | "\(.timestamp | todate): \(.message)"' | tail -10
            else
                print_info "No recent log events found"
            fi
        fi
    else
        print_info "No log streams found for $LOG_GROUP_NAME"
    fi
}

# Function to check for errors in logs
check_log_errors() {
    print_section "Error Detection in Logs"
    
    # Look for errors in the last 30 minutes
    START_TIME=$(date -d '30 minutes ago' +%s)000
    
    # Search for error patterns
    ERROR_PATTERNS=("ERROR" "Exception" "Traceback" "FAILED" "ModuleNotFoundError" "ImportError")
    
    for pattern in "${ERROR_PATTERNS[@]}"; do
        ERRORS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --start-time "$START_TIME" \
            --filter-pattern "$pattern" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null || echo '{"events":[]}')
        
        ERROR_COUNT=$(echo "$ERRORS" | jq '.events | length')
        
        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_error "Found $ERROR_COUNT occurrences of '$pattern' in logs"
            # Show the most recent error
            echo "$ERRORS" | jq -r '.events[0] | "  Last occurrence: \(.timestamp | todate)\n  Message: \(.message)"' | head -5
        fi
    done
    
    # If no errors found
    if ! aws logs filter-log-events \
        --log-group-name "$LOG_GROUP_NAME" \
        --start-time "$START_TIME" \
        --filter-pattern "ERROR" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null | jq -e '.events | length > 0' > /dev/null; then
        print_success "No errors detected in recent logs"
    fi
}

# Function to test email sending capability
test_email_capability() {
    print_section "Email Sending Capability Test"
    
    # Check SES verified identities
    VERIFIED_EMAILS=$(aws ses list-verified-email-addresses --region "$AWS_REGION" --output json 2>/dev/null || echo '{"VerifiedEmailAddresses":[]}')
    
    EMAIL_COUNT=$(echo "$VERIFIED_EMAILS" | jq '.VerifiedEmailAddresses | length')
    
    if [ "$EMAIL_COUNT" -gt 0 ]; then
        print_success "$EMAIL_COUNT verified email addresses found"
        echo "$VERIFIED_EMAILS" | jq -r '.VerifiedEmailAddresses[] | "  ✉️  \(.)"'
    else
        print_warning "No verified email addresses found in SES"
    fi
    
    # Check SES sandbox status
    SANDBOX_STATUS=$(aws ses get-account-sending-enabled --region "$AWS_REGION" --output text 2>/dev/null || echo "unknown")
    
    if [ "$SANDBOX_STATUS" = "True" ]; then
        print_success "SES sending is enabled"
    else
        print_warning "SES sending may be disabled or in sandbox mode"
    fi
}

# Function to trigger manual Lambda execution for testing
trigger_test_execution() {
    print_section "Manual Lambda Test Execution"
    
    print_info "Triggering test execution of $LAMBDA_FUNCTION_NAME..."
    
    RESULT=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{}' \
        --region "$AWS_REGION" \
        --output json \
        /tmp/lambda-test-response.json 2>/dev/null || echo '{"StatusCode":0}')
    
    STATUS_CODE=$(echo "$RESULT" | jq -r '.StatusCode')
    
    if [ "$STATUS_CODE" = "200" ]; then
        print_success "Lambda test execution successful (StatusCode: 200)"
    else
        print_error "Lambda test execution failed (StatusCode: $STATUS_CODE)"
    fi
    
    # Clean up temporary file
    rm -f /tmp/lambda-test-response.json
}

# Function to display monitoring dashboard
display_dashboard() {
    clear
    print_header "🔍 Cloud Custodian Mailer Monitoring Dashboard - $(get_timestamp)"
    
    echo -e "${PURPLE}Configuration:${NC}"
    echo "  📍 Region: $AWS_REGION"
    echo "  📮 SQS Queue: $(basename "$SQS_QUEUE_URL")"
    echo "  🔧 Lambda: $LAMBDA_FUNCTION_NAME"
    echo "  🔄 Refresh: ${REFRESH_INTERVAL}s"
    echo ""
    
    check_aws_connectivity
    monitor_sqs_queue
    monitor_ses_statistics
    check_ses_quota
    monitor_lambda_function
    get_recent_lambda_logs
    check_log_errors
    test_email_capability
}

# Function to show usage
show_usage() {
    cat << EOF
🔍 Cloud Custodian Mailer Monitoring Script

Usage: $0 [OPTIONS]

Options:
    -r, --region REGION          AWS region (default: us-west-2)
    -q, --queue-url URL          SQS queue URL
    -l, --lambda-name NAME       Lambda function name (default: cloud-custodian-mailer)
    -i, --interval SECONDS       Refresh interval (default: 10)
    -d, --duration SECONDS       Monitoring duration (default: 300)
    -t, --test                   Run single test and exit
    --trigger-test               Trigger manual Lambda execution
    -h, --help                   Show this help message

Examples:
    $0                           # Start monitoring with defaults
    $0 -i 5 -d 600              # Monitor for 10 minutes, refresh every 5 seconds
    $0 --test                    # Run single diagnostic test
    $0 --trigger-test            # Trigger manual Lambda test

Environment Variables:
    AWS_REGION                   AWS region to use
    SQS_QUEUE_URL               SQS queue URL to monitor
    LAMBDA_FUNCTION_NAME        Lambda function name to monitor
    REFRESH_INTERVAL            Refresh interval in seconds
    MONITORING_DURATION         Total monitoring duration in seconds

Dependencies:
    - aws CLI configured with appropriate permissions
    - jq for JSON parsing
    - bc for calculations
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -q|--queue-url)
            SQS_QUEUE_URL="$2"
            shift 2
            ;;
        -l|--lambda-name)
            LAMBDA_FUNCTION_NAME="$2"
            LOG_GROUP_NAME="/aws/lambda/$LAMBDA_FUNCTION_NAME"
            shift 2
            ;;
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -d|--duration)
            MONITORING_DURATION="$2"
            shift 2
            ;;
        -t|--test)
            TEST_MODE=true
            shift
            ;;
        --trigger-test)
            TRIGGER_TEST=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_error "jq is not installed. Please install jq for JSON parsing"
    exit 1
fi

# Handle special modes
if [ "$TRIGGER_TEST" = true ]; then
    print_header "🧪 Manual Lambda Test Execution"
    check_aws_connectivity
    trigger_test_execution
    exit 0
fi

if [ "$TEST_MODE" = true ]; then
    display_dashboard
    exit 0
fi

# Main monitoring loop
print_header "🚀 Starting Cloud Custodian Mailer Monitoring"
print_info "Monitoring will run for $MONITORING_DURATION seconds with $REFRESH_INTERVAL second intervals"
print_info "Press Ctrl+C to stop monitoring"

START_TIME=$(date +%s)
END_TIME=$((START_TIME + MONITORING_DURATION))

# Trap for graceful exit
trap 'echo -e "\n\n${YELLOW}📊 Monitoring stopped by user${NC}"; exit 0' INT

while [ $(date +%s) -lt $END_TIME ]; do
    display_dashboard
    
    REMAINING=$((END_TIME - $(date +%s)))
    if [ $REMAINING -gt 0 ]; then
        echo ""
        print_info "Next refresh in $REFRESH_INTERVAL seconds (${REMAINING}s remaining, Ctrl+C to stop)"
        sleep $REFRESH_INTERVAL
    fi
done

print_header "✅ Monitoring Complete"
print_success "Monitoring completed after $MONITORING_DURATION seconds"