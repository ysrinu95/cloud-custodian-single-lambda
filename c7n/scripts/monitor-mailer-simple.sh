# Function to fetch and decode SQS messages
show_sqs_messages() {
    echo "📨 SQS Messages (decrypted):"
    local total=0
    while true; do
        messages_json=$(aws sqs receive-message --queue-url "$SQS_QUEUE_URL" --max-number-of-messages 10 --region "$AWS_REGION" --output json 2>/dev/null)
        count=$(echo "$messages_json" | jq '.Messages | length')
        : "${count:=0}"
        : "${total:=0}"
        if [ "$count" -eq 0 ]; then
            if [ "$total" -eq 0 ]; then
                print_info "No messages found in SQS queue."
            fi
            break
        fi
        for i in $(seq 0 $((count - 1))); do
            raw_body=$(echo "$messages_json" | jq -r ".Messages[$i].Body")
            receipt_handle=$(echo "$messages_json" | jq -r ".Messages[$i].ReceiptHandle")
            # If message is base64 encoded, decode it. If not, just print as is.
            if echo "$raw_body" | grep -Eq '^[A-Za-z0-9+/=]+$'; then
                decoded=$(echo "$raw_body" | base64 -d 2>/dev/null)
                if [ $? -eq 0 ]; then
                    echo "----- Message $((total+1)) -----"
                    echo "$decoded"
                else
                    echo "----- Message $((total+1)) -----"
                    echo "$raw_body"
                fi
            else
                echo "----- Message $((total+1)) -----"
                echo "$raw_body"
            fi
            total=$((total+1))
            # Uncomment below to delete messages after reading:
            # aws sqs delete-message --queue-url "$SQS_QUEUE_URL" --receipt-handle "$receipt_handle" --region "$AWS_REGION" 2>/dev/null
        done
    done
    echo "--------------------------"
    # For KMS-encrypted messages, use:
    # aws kms decrypt --ciphertext-blob fileb://<(echo "$raw_body" | base64 -d) --output text --query Plaintext | base64 -d
}
#!/bin/bash
# Simple SQS and SES Email Status Monitor
# Focused monitoring script for c7n-mailer email sending status

# Configuration (adjust these to match your setup)
AWS_REGION="us-east-1"
SQS_QUEUE_URL="https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue"
LAMBDA_FUNCTION="cloud-custodian-mailer"
REFRESH_INTERVAL=60

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_status() {
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

# Function to check SQS queue status
check_sqs_status() {
    echo "📬 SQS Queue Status:"
    
    if QUEUE_ATTRS=$(aws sqs get-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible \
        --region "$AWS_REGION" \
        --output json 2>/dev/null); then
        
        MESSAGES=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
        IN_FLIGHT=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "0"')
        : "${MESSAGES:=0}"
        : "${IN_FLIGHT:=0}"
        
        echo "  📊 Available Messages: $MESSAGES"
        echo "  🔄 Processing Messages: $IN_FLIGHT"
        
        if [ "$MESSAGES" -gt 0 ]; then
            print_warning "$MESSAGES messages waiting to be processed"
        elif [ "$IN_FLIGHT" -gt 0 ]; then
            print_info "$IN_FLIGHT messages currently being processed"
        else
            print_status "Queue is empty - all messages processed"
        fi
    else
        print_error "Failed to check SQS queue: $SQS_QUEUE_URL"
    fi
    echo ""
}

# Function to check SES statistics
check_ses_status() {
    echo "📧 SES Email Status:"
    
    # Get recent sending statistics
    if SES_STATS=$(aws ses get-send-statistics --region "$AWS_REGION" --output json 2>/dev/null); then
        if [ "$(echo "$SES_STATS" | jq '.SendDataPoints | length')" -gt 0 ]; then
            LATEST=$(echo "$SES_STATS" | jq '.SendDataPoints | sort_by(.Timestamp) | last')
            
            ATTEMPTS=$(echo "$LATEST" | jq -r '.DeliveryAttempts // 0')
            BOUNCES=$(echo "$LATEST" | jq -r '.Bounces // 0')
            COMPLAINTS=$(echo "$LATEST" | jq -r '.Complaints // 0')
            REJECTS=$(echo "$LATEST" | jq -r '.Rejects // 0')
            : "${ATTEMPTS:=0}"
            : "${BOUNCES:=0}"
            : "${COMPLAINTS:=0}"
            : "${REJECTS:=0}"
            
            echo "  📤 Recent Delivery Attempts: $ATTEMPTS"
            echo "  ↩️  Bounces: $BOUNCES"
            echo "  🚫 Complaints: $COMPLAINTS"
            echo "  ❌ Rejects: $REJECTS"
            
            if [ "$BOUNCES" -gt 0 ] || [ "$COMPLAINTS" -gt 0 ] || [ "$REJECTS" -gt 0 ]; then
                print_warning "Email delivery issues detected"
            else
                print_status "No email delivery issues"
            fi
        else
            print_info "No recent SES statistics available"
        fi
    else
        print_error "Failed to get SES statistics"
    fi
    
    # Check SES quota
    if SES_QUOTA=$(aws ses get-send-quota --region "$AWS_REGION" --output json 2>/dev/null); then
        SENT_24H=$(echo "$SES_QUOTA" | jq -r '.SentLast24Hours // 0')
        MAX_24H=$(echo "$SES_QUOTA" | jq -r '.Max24HourSend // 0')
        # Use bc for floating-point comparison
        if (( $(echo "$MAX_24H > 0" | bc -l) )); then
            PERCENTAGE=$(echo "scale=1; $SENT_24H * 100 / $MAX_24H" | bc -l 2>/dev/null || echo "0")
            echo "  📊 24h Usage: $SENT_24H / $MAX_24H emails ($PERCENTAGE%)"
        fi
    fi
    echo ""
}

# Function to check Lambda function
check_lambda_status() {
    echo "🔧 Lambda Function Status:"
    
    if LAMBDA_INFO=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null); then
        
        STATE=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.State')
        LAST_MODIFIED=$(echo "$LAMBDA_INFO" | jq -r '.Configuration.LastModified')
        
        echo "  📊 State: $STATE"
        echo "  ⏰ Last Modified: $LAST_MODIFIED"
        
        if [ "$STATE" = "Active" ]; then
            print_status "Lambda function is active"
        else
            print_warning "Lambda function state: $STATE"
        fi
    else
        print_error "Failed to check Lambda function: $LAMBDA_FUNCTION"
    fi
    echo ""
}

# Function to check recent Lambda logs for errors
check_lambda_logs() {
    echo "📋 Recent Lambda Logs:"
    
    LOG_GROUP="/aws/lambda/$LAMBDA_FUNCTION"
    START_TIME=$(date -d '10 minutes ago' +%s)000
    
    # Check for recent errors
    if ERROR_LOGS=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --filter-pattern "ERROR" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null); then
        
        ERROR_COUNT=$(echo "$ERROR_LOGS" | jq '.events | length')
        
        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_error "$ERROR_COUNT errors found in last 10 minutes"
            echo "  Latest error:"
            echo "$ERROR_LOGS" | jq -r '.events[0].message' | head -3 | sed 's/^/    /'
        else
            print_status "No errors in recent logs"
        fi
    else
        print_info "Could not check Lambda logs"
    fi
    echo ""
}

# Function to trigger test Lambda execution
trigger_test() {
    echo "🧪 Testing Lambda Function:"
    
    if RESULT=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION" \
        --payload '{}' \
        --region "$AWS_REGION" \
        /tmp/test-response.json 2>/dev/null); then
        
        STATUS=$(echo "$RESULT" | jq -r '.StatusCode')
        if [ "$STATUS" = "200" ]; then
            print_status "Lambda test execution successful"
        else
            print_error "Lambda test failed (Status: $STATUS)"
        fi
    else
        print_error "Failed to invoke Lambda function"
    fi
    
    rm -f /tmp/test-response.json
    echo ""
}

# Main monitoring function
monitor_status() {
    clear
    echo "================================================================================"
    echo "🔍 Cloud Custodian Mailer Status Monitor - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================================"
    echo "📍 Region: $AWS_REGION"
    echo "📮 Queue: $(basename "$SQS_QUEUE_URL")"
    echo "🔧 Lambda: $LAMBDA_FUNCTION"
    echo "================================================================================"
    echo ""
    
    check_sqs_status
    show_sqs_messages
    check_ses_status
    check_lambda_status
    check_lambda_logs
    
    echo "================================================================================"
    echo "🔄 Auto-refresh every ${REFRESH_INTERVAL}s | Press 't' for test | Press 'q' to quit"
    echo "================================================================================"
}

# Function to show usage
show_usage() {
    cat << EOF
📧 Cloud Custodian Mailer Status Monitor

Usage: $0 [OPTIONS]

Options:
    -r, --region REGION     AWS region (default: us-west-2)
    -q, --queue URL         SQS queue URL
    -l, --lambda NAME       Lambda function name (default: cloud-custodian-mailer)
    -i, --interval SEC      Refresh interval (default: 5)
    --test                  Run single check and exit
    -h, --help              Show this help

Interactive Commands:
    't' - Trigger test Lambda execution
    'q' - Quit monitoring
    'r' - Refresh immediately

Example:
    $0                      # Start monitoring with defaults
    $0 -i 10                # Refresh every 10 seconds
    $0 --test               # Single status check
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -q|--queue)
            SQS_QUEUE_URL="$2"
            shift 2
            ;;
        -l|--lambda)
            LAMBDA_FUNCTION="$2"
            shift 2
            ;;
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --test)
            monitor_status
            exit 0
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
command -v aws >/dev/null 2>&1 || { echo "AWS CLI required but not installed. Aborting." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required but not installed. Aborting." >&2; exit 1; }

# Main monitoring loop
echo "🚀 Starting Cloud Custodian Mailer Monitor..."
echo "Press Ctrl+C to stop"

# Set up for interactive input
if [ -t 0 ]; then
    # Interactive mode
    while true; do
        monitor_status
        
        # Wait for input or timeout
        if read -t $REFRESH_INTERVAL -n 1 key; then
            case $key in
                t|T)
                    echo ""
                    trigger_test
                    sleep 2
                    ;;
                q|Q)
                    echo ""
                    echo "👋 Monitoring stopped"
                    exit 0
                    ;;
                r|R)
                    # Immediate refresh
                    continue
                    ;;
            esac
        fi
    done
else
    # Non-interactive mode
    while true; do
        monitor_status
        sleep $REFRESH_INTERVAL
    done
fi