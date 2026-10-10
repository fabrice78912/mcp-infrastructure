#!/bin/bash

# Script de test end-to-end pour vérifier la propagation du requestId
# Usage: ./scripts/test-requestid.sh

set -e

API_URL="https://ezbi75dkik.execute-api.ca-central-1.amazonaws.com/dev"
CLIENT_ID="TEST-REQUESTID-$(date +%s)"
NEW_LAST_NAME="TestRequestId-$(date +%H%M%S)"
REASON="TEST_REQUESTID_TRACING"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         TEST END-TO-END REQUESTID TRACING                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Test Parameters:"
echo "   • API URL:       $API_URL"
echo "   • Client ID:     $CLIENT_ID"
echo "   • New Last Name: $NEW_LAST_NAME"
echo "   • Reason:        $REASON"
echo ""

# ========================================
# STEP 1: CALL API
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "STEP 1: Calling API to trigger workflow"
echo "════════════════════════════════════════════════════════════"
echo ""

RESPONSE=$(curl -s -X PUT "$API_URL/api/clients/$CLIENT_ID/nom" \
  -H "Content-Type: application/json" \
  -d "{\"newLastName\": \"$NEW_LAST_NAME\", \"reason\": \"$REASON\"}")

echo "API Response:"
echo "$RESPONSE" | jq '.'
echo ""

# Extract execution ARN
EXECUTION_ARN=$(echo "$RESPONSE" | jq -r '.executionArn // empty')

if [ -z "$EXECUTION_ARN" ]; then
  echo "❌ ERROR: Could not extract execution ARN from response"
  echo "Response was: $RESPONSE"
  exit 1
fi

echo "✅ Workflow started"
echo "   Execution ARN: $EXECUTION_ARN"
echo ""

# ========================================
# STEP 2: WAIT FOR WORKFLOW COMPLETION
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "STEP 2: Waiting for workflow to complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "⏳ Waiting 30 seconds for workflow to complete..."
echo ""

for i in {1..30}; do
  echo -n "."
  sleep 1
done
echo ""
echo ""

# ========================================
# STEP 3: CHECK STEP FUNCTIONS EXECUTION
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "STEP 3: Checking Step Functions execution"
echo "════════════════════════════════════════════════════════════"
echo ""

EXECUTION_DETAILS=$(aws stepfunctions describe-execution \
  --execution-arn "$EXECUTION_ARN" \
  --query '{status:status,startDate:startDate,stopDate:stopDate}' \
  --output json)

echo "Execution Details:"
echo "$EXECUTION_DETAILS" | jq '.'
echo ""

EXECUTION_STATUS=$(echo "$EXECUTION_DETAILS" | jq -r '.status')

if [ "$EXECUTION_STATUS" = "SUCCEEDED" ]; then
  echo "✅ Workflow completed successfully"
elif [ "$EXECUTION_STATUS" = "RUNNING" ]; then
  echo "⏳ Workflow still running (may need more time)"
else
  echo "❌ Workflow status: $EXECUTION_STATUS"
fi
echo ""

# ========================================
# STEP 4: EXTRACT REQUESTID FROM LOGS
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "STEP 4: Extracting requestId from CloudWatch logs"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Searching ValidationHandler logs for requestId..."
VALIDATION_LOGS=$(aws logs filter-log-events \
  --log-group-name "/aws/lambda/dev-mcp-client_profile_reader" \
  --start-time $(($(date +%s) * 1000 - 120000)) \
  --filter-pattern "\"$CLIENT_ID\"" \
  --query 'events[*].message' \
  --output text \
  --max-items 5)

if [ -n "$VALIDATION_LOGS" ]; then
  echo "Validation Logs:"
  echo "$VALIDATION_LOGS"
  echo ""

  # Extract requestId from logs
  REQUEST_ID=$(echo "$VALIDATION_LOGS" | grep -o '"requestId":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ -n "$REQUEST_ID" ]; then
    echo "✅ Found requestId in logs: $REQUEST_ID"
  else
    echo "⚠️  Could not extract requestId from logs"
    REQUEST_ID="UNKNOWN"
  fi
else
  echo "⚠️  No validation logs found yet"
  REQUEST_ID="UNKNOWN"
fi
echo ""

# ========================================
# STEP 5: CHECK KAFKA MESSAGES
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "STEP 5: Checking Kafka messages for requestId"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Searching Kafka consumer logs..."
KAFKA_LOGS=$(aws logs filter-log-events \
  --log-group-name "/aws/lambda/dev-mcp-kafka_consumer" \
  --start-time $(($(date +%s) * 1000 - 120000)) \
  --filter-pattern "\"$CLIENT_ID\"" \
  --query 'events[*].message' \
  --output text \
  --max-items 10)

if [ -n "$KAFKA_LOGS" ]; then
  echo "Kafka Consumer Logs:"
  echo "$KAFKA_LOGS"
  echo ""

  # Check if requestId is present in Kafka message
  if echo "$KAFKA_LOGS" | grep -q "\"requestId\""; then
    echo "✅ requestId found in Kafka message!"

    # Extract the Kafka message with requestId
    KAFKA_MESSAGE=$(echo "$KAFKA_LOGS" | grep -A 10 "Message Content (JSON)" | head -20)
    echo ""
    echo "Kafka Message (excerpt):"
    echo "$KAFKA_MESSAGE"
    echo ""

    # Verify requestId is not null
    if echo "$KAFKA_MESSAGE" | grep -q "\"requestId\" : \"null\""; then
      echo "❌ requestId is null in Kafka message"
    elif echo "$KAFKA_MESSAGE" | grep -q "\"requestId\" : \"$REQUEST_ID\""; then
      echo "✅ requestId matches between logs and Kafka message!"
    else
      echo "⚠️  requestId present but value unclear"
    fi
  else
    echo "❌ requestId NOT found in Kafka message"
    echo "⚠️  This may indicate the new code is not deployed yet"
  fi
else
  echo "⚠️  No Kafka consumer logs found yet"
  echo "💡 The message may not have been consumed yet, wait a bit longer"
fi
echo ""

# ========================================
# STEP 6: SUMMARY
# ========================================
echo "════════════════════════════════════════════════════════════"
echo "TEST SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Client ID:        $CLIENT_ID"
echo "New Last Name:    $NEW_LAST_NAME"
echo "RequestId:        $REQUEST_ID"
echo "Workflow Status:  $EXECUTION_STATUS"
echo ""

if [ "$EXECUTION_STATUS" = "SUCCEEDED" ] && [ "$REQUEST_ID" != "UNKNOWN" ]; then
  echo "✅ Test completed successfully!"
  echo ""
  echo "📍 Next steps:"
  echo "   1. View full Kafka message: ./scripts/view-kafka-messages.sh 5"
  echo "   2. View CloudWatch dashboard: https://ca-central-1.console.aws.amazon.com/cloudwatch/home?region=ca-central-1#dashboards:name=dev-mcp-kafka-flow"
  echo "   3. Search logs by requestId in CloudWatch Logs Insights:"
  echo "      fields @timestamp, @message"
  echo "      | filter @message like /$REQUEST_ID/"
  echo "      | sort @timestamp desc"
else
  echo "⚠️  Test incomplete or pending"
  echo ""
  echo "📍 Troubleshooting:"
  echo "   1. Check if GitHub Actions workflow completed: https://github.com/fabrice78912/mcp-local/actions"
  echo "   2. Verify Lambda functions updated: aws lambda list-functions | grep dev-mcp"
  echo "   3. Check Step Functions execution: aws stepfunctions describe-execution --execution-arn $EXECUTION_ARN"
  echo "   4. Wait longer and re-run this script"
fi

echo ""
echo "════════════════════════════════════════════════════════════"