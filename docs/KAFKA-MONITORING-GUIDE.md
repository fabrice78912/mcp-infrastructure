# Guide de Monitoring Kafka

## 🎯 Vue d'ensemble

Ce guide explique comment monitorer le flux complet des messages Kafka dans l'infrastructure MCP, depuis la production jusqu'à la consommation.

## 📊 Dashboard CloudWatch

**URL**: https://ca-central-1.console.aws.amazon.com/cloudwatch/home?region=ca-central-1#dashboards:name=dev-mcp-kafka-flow

### Widgets disponibles:

1. **Kafka Consumer - Messages Consumed**: Nombre de messages lus depuis le topic `client.name.updated`
2. **Kafka Consumer - Processing Duration**: Temps de traitement moyen en millisecondes
3. **Kafka Consumer - Errors**: Erreurs lors de la consommation
4. **Kafka Producer - Messages Published**: Nombre de messages publiés par `fcc_sender`
5. **Step Functions - Executions**: État des workflows (Started, Succeeded, Failed)
6. **Recent Kafka Messages (JSON Decoded)**: Les derniers messages consommés en JSON
7. **Kafka Message Metadata**: Topic, Partition, Offset, Key

## 🔍 Visualiser les messages Kafka

### Option 1: Scripts fournis

```bash
# Voir les messages des 30 dernières minutes
./scripts/view-kafka-messages.sh

# Voir les messages des 60 dernières minutes
./scripts/view-kafka-messages.sh 60

# Suivre les messages en temps réel
./scripts/follow-kafka-messages.sh
```

### Option 2: Commande AWS CLI directe

```bash
# Voir les messages récents
aws logs tail /aws/lambda/dev-mcp-kafka_consumer --since 30m --format short | \
  grep -A 20 "Message Content (JSON)"

# Suivre en temps réel
aws logs tail /aws/lambda/dev-mcp-kafka_consumer --follow --format short | \
  grep --line-buffered -A 20 "Message Content (JSON)"
```

### Option 3: CloudWatch Logs Insights

1. Aller sur CloudWatch Console
2. Choisir "Logs Insights"
3. Sélectionner le log group `/aws/lambda/dev-mcp-kafka_consumer`
4. Utiliser cette requête:

```sql
fields @timestamp, @message
| filter @message like /Message Content \(JSON\)/
| sort @timestamp desc
| limit 20
```

## 📝 Format des messages

Les messages Kafka sont automatiquement **décodés depuis Base64** et **formatés en JSON**:

```json
{
  "reason": "CORRECTION",
  "clientId": "TEST123",
  "previousLastName": "DashboardTest",
  "newLastName": "FABRICE",
  "correlationId": "null",
  "eventType": "NAME_UPDATED",
  "source": "mcp-api",
  "timestamp": "2026-10-09T20:56:32.590920176Z"
}
```

## 🧪 Tester le flux Kafka

### Générer un message de test

```bash
curl -X PUT "https://ezbi75dkik.execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/nom" \
  -H "Content-Type: application/json" \
  -d '{"newLastName": "MonTest", "reason": "TEST KAFKA"}'
```

### Vérifier la consommation

Attendre ~20 secondes, puis:

```bash
./scripts/view-kafka-messages.sh 5
```

## 🔧 Composants du flux

```
┌─────────────┐
│  API Gateway│
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Step Functions  │
└──────┬──────────┘
       │
       ▼
┌──────────────────┐      ┌─────────────┐
│ fcc_sender       │─────▶│ Kafka Topic │
│ (Producer)       │      │ client.name │
└──────────────────┘      │ .updated    │
                          └──────┬──────┘
                                 │
                                 ▼
                          ┌──────────────┐
                          │ Event Source │
                          │ Mapping      │
                          └──────┬───────┘
                                 │
                                 ▼
                          ┌──────────────┐
                          │kafka_consumer│
                          │ (Consumer)   │
                          └──────────────┘
```

## ⚙️ Configuration

### Consumer Lambda
- **Nom**: `dev-mcp-kafka_consumer`
- **Topic**: `client.name.updated`
- **Batch Size**: 100 messages
- **Batching Window**: 10 secondes
- **Event Source Mapping**: Activé

### Logging
- **Profil Spring**: `lambda`
- **Log Level**: `INFO`
- **Décodage**: Base64 → UTF-8 → JSON pretty-print

## 🐛 Dépannage

### Les messages n'apparaissent pas

1. Vérifier l'Event Source Mapping:
```bash
aws lambda list-event-source-mappings --function-name dev-mcp-kafka_consumer
```

Statut attendu: `"State": "Enabled"`, `"LastProcessingResult": "OK"`

2. Vérifier les logs d'erreur:
```bash
aws logs tail /aws/lambda/dev-mcp-kafka_consumer --since 10m --filter-pattern "ERROR"
```

### Step Functions échoue

```bash
# Récupérer l'ARN d'exécution depuis la réponse de l'API
EXECUTION_ARN="arn:aws:states:..."

# Voir les détails de l'échec
aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN"
```

### Vérifier la santé du système

```bash
# Event Source Mapping
aws lambda list-event-source-mappings --function-name dev-mcp-kafka_consumer \
  --query 'EventSourceMappings[0].{State:State,LastResult:LastProcessingResult}'

# Lambda récente
aws lambda get-function-configuration --function-name dev-mcp-kafka_consumer \
  --query '{LastModified:LastModified,Runtime:Runtime}'

# MSK Cluster
aws kafka describe-cluster-v2 --cluster-arn <ARN> --query 'ClusterInfo.State'
```

## 📚 Références

- **Dashboard**: https://ca-central-1.console.aws.amazon.com/cloudwatch/home?region=ca-central-1#dashboards:name=dev-mcp-kafka-flow
- **CloudWatch Logs**: https://ca-central-1.console.aws.amazon.com/cloudwatch/home?region=ca-central-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Fdev-mcp-kafka_consumer
- **Step Functions**: https://ca-central-1.console.aws.amazon.com/states/home?region=ca-central-1#/statemachines
- **API Gateway**: https://ezbi75dkik.execute-api.ca-central-1.amazonaws.com/dev/

## ✅ Checklist de déploiement

Après tout déploiement de `kafka_consumer`:

- [ ] Vérifier Event Source Mapping: `LastProcessingResult: "OK"`
- [ ] Tester avec un message: API → Kafka → Consumer
- [ ] Vérifier les logs CloudWatch (message décodé visible)
- [ ] Consulter le dashboard pour les métriques

---

**Date de création**: 2026-10-09
**Dernière mise à jour**: 2026-10-09