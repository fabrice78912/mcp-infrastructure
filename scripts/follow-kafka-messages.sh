#!/bin/bash

# Script pour suivre les messages Kafka en temps réel
# Usage: ./scripts/follow-kafka-messages.sh

echo "========================================="
echo "📡 SUIVI TEMPS RÉEL DES MESSAGES KAFKA"
echo "========================================="
echo "Appuyez sur Ctrl+C pour arrêter"
echo ""

aws logs tail /aws/lambda/dev-mcp-kafka_consumer --follow --format short | \
  grep --line-buffered -A 20 "Message Content (JSON)" | \
  sed 's/^[0-9-]*T[0-9:]* //'