#!/bin/bash

# Script pour visualiser les messages Kafka consommés depuis CloudWatch
# Usage: ./scripts/view-kafka-messages.sh [minutes]
# Exemple: ./scripts/view-kafka-messages.sh 60  (dernières 60 minutes)

MINUTES=${1:-30}  # Par défaut 30 minutes

echo "========================================="
echo "📊 KAFKA MESSAGES (dernières $MINUTES minutes)"
echo "========================================="
echo ""

aws logs tail /aws/lambda/dev-mcp-kafka_consumer --since ${MINUTES}m --format short | \
  grep -A 20 "Message Content (JSON)" | \
  sed 's/^[0-9-]*T[0-9:]* //'

echo ""
echo "========================================="
echo "✅ Fin des messages"
echo "========================================="