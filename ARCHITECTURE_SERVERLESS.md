# Architecture Serverless - MCP (Banque Nationale du Canada)

**Date** : 2026-09-25
**Auteur** : Architecture Team
**Statut** : ✅ **PRÊT POUR SERVERLESS - AUCUN KUBERNETES REQUIS**

---

## 🎯 Réponse Courte

**OUI**, tous les services métier MCP peuvent fonctionner en **100% serverless** sur AWS sans Kubernetes.

L'architecture actuelle est déjà conçue avec ce modèle en tête :
- ✅ Handlers Spring Boot écrits comme des pseudo-Lambda (@Component)
- ✅ Step Functions comme orchestrateur central
- ✅ DynamoDB, SNS, SES, SQS déjà serverless
- ✅ API REST stateless (facile à migrer vers API Gateway + Lambda)

---

## 📊 Comparaison Architecture

### Architecture Actuelle (Développement Local)

```
┌─────────────────────────────────────────────────────────────┐
│ CONTAINERS DOCKER (développement local)                    │
├─────────────────────────────────────────────────────────────┤
│ mcp-api                  → Spring Boot REST (port 8080)     │
│ mcp-orchestration        → Spring Boot handlers (port 8081) │
│ mcp-fcc-connector        → Spring Boot consumer (port 8082) │
├─────────────────────────────────────────────────────────────┤
│ Infrastructure locale                                       │
│ - LocalStack (DynamoDB, SNS, SES, SQS)                     │
│ - Step Functions Local                                      │
│ - Kafka                                                     │
│ - IBM MQ                                                    │
└─────────────────────────────────────────────────────────────┘
```

### Architecture Production Serverless (AWS)

```
┌─────────────────────────────────────────────────────────────┐
│ SERVERLESS AWS (production)                                │
├─────────────────────────────────────────────────────────────┤
│ API Gateway + Lambda     → Remplace mcp-api                 │
│ Lambda Functions (x30+)  → Remplace mcp-orchestration       │
│ Lambda + EventBridge     → Remplace mcp-fcc-connector       │
├─────────────────────────────────────────────────────────────┤
│ Services gérés AWS                                          │
│ - DynamoDB (serverless)                                     │
│ - SNS/SES/SQS (serverless)                                  │
│ - Step Functions (serverless)                               │
│ - MSK Serverless (Kafka)                                    │
│ - Amazon MQ (IBM MQ géré)                                   │
│ - CloudWatch Logs                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 Migration Serverless par Service

### 1. mcp-api → API Gateway + Lambda

**Actuellement** :
```
Spring Boot REST API (container Docker)
├── ClientController (name, address)
├── PhoneController (phone update)
└── ReviewProxyController
```

**En Serverless** :
```
API Gateway
├── POST /api/v1/clients/{id}/name      → Lambda: api-change-name
├── POST /api/v1/clients/{id}/address   → Lambda: api-change-address
├── POST /api/v1/clients/{id}/phone     → Lambda: api-change-phone
├── GET  /api/v1/clients/{id}           → Lambda: api-get-client
└── GET  /api/v1/reviews                → Lambda: api-list-reviews
```

**Options d'implémentation** :

#### Option A : Lambda Java Spring Boot (Facile)
```xml
<!-- Utiliser AWS Serverless Java Container -->
<dependency>
    <groupId>com.amazonaws.serverless</groupId>
    <artifactId>aws-serverless-java-container-springboot3</artifactId>
    <version>2.0.0</version>
</dependency>
```
- ✅ Code Spring Boot existant fonctionne tel quel
- ✅ Migration en 1 journée
- ⚠️ Cold start ~3-5 secondes
- 💰 Coût moyen

#### Option B : Lambda Java Native (GraalVM)
```bash
# Compiler Spring Boot en natif avec GraalVM
./mvnw -Pnative native:compile
```
- ✅ Cold start <1 seconde
- ✅ Coût réduit (moins de RAM)
- ⚠️ Compilation plus complexe
- 💰 Coût optimal

#### Option C : Lambda Java SnapStart (Recommandé BNC)
```yaml
# serverless.yml ou SAM template
Functions:
  ApiChangePhone:
    Runtime: java21
    SnapStart:
      ApplyOn: PublishedVersions
```
- ✅ Cold start réduit de 90% (~500ms)
- ✅ Code Spring Boot sans changement
- ✅ Pas de travail GraalVM
- 💰 Coût moyen
- **RECOMMANDÉ pour BNC**

---

### 2. mcp-orchestration → Lambda Functions (x30+)

**Actuellement** :
```
Spring Boot avec 30+ handlers @Component simulant des Lambda :
├── Name Update (6 handlers)
├── Address Update (8 handlers)
├── Phone Update (12 handlers)
└── Shared handlers
```

**En Serverless** :
Chaque handler devient une **vraie Lambda function** :

```
Lambda Functions (Phone Update Workflow) :
├── ReadClientProfileLambda
├── PhoneValidatorLambda
├── CheckPhoneHistoryLambda
├── HumanApprovalLambda
├── SendOTPSMSLambda
├── CheckOTPStatusLambda
├── PhoneMDMAEClientLambda         ← CRITIQUE (retry 3-level)
├── FCCSenderLambda
├── CRMUpdaterLambda
├── NotificationUpdaterLambda
├── NotificationSenderLambda
└── RecordPhoneHistoryLambda

Lambda Functions (Name Update Workflow) :
├── ReadClientProfileLambda         ← RÉUTILISÉ
├── NameValidatorLambda
├── NameMDMAEClientLambda
├── HumanReviewNotifierLambda
├── WaitForApprovalLambda
└── RecordNameHistoryLambda

Lambda Functions (Address Update Workflow) :
├── ReadClientProfileLambda         ← RÉUTILISÉ
├── AddressValidatorLambda
├── GeocodeAddressLambda
├── AddressMDMAEClientLambda
└── RecordAddressHistoryLambda
```

**Migration** :

1. **Chaque @Component devient une classe Main** :
```java
// Avant (local simulation)
@Component("PhoneValidatorLambda")
public class PhoneValidatorHandler implements LambdaHandler {
    @Override
    public Map<String, Object> handle(Map<String, Object> input) {
        // validation logic
    }
}

// Après (vraie Lambda)
public class PhoneValidatorLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private final PhoneValidationService service;

    public PhoneValidatorLambda() {
        this.service = new PhoneValidationService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        // MÊME logique validation
        return service.validatePhone(input);
    }
}
```

2. **Déploiement SAM/Serverless Framework** :
```yaml
# template.yaml (AWS SAM)
Resources:
  PhoneValidatorLambda:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: PhoneValidatorLambda
      Runtime: java21
      Handler: com.bnc.mcp.orchestration.phone.PhoneValidatorLambda::handleRequest
      MemorySize: 512
      Timeout: 30
      SnapStart:
        ApplyOn: PublishedVersions
      Environment:
        Variables:
          AWS_REGION: ca-central-1
```

**Estimation** :
- ✅ 30+ Lambdas créées en **2-3 semaines**
- ✅ Code métier **AUCUN changement** (déjà écrit pour Lambda)
- ✅ Tests unitaires **réutilisés** à 100%

---

### 3. mcp-fcc-connector → Lambda + EventBridge

**Actuellement** :
```
Spring Boot Kafka Consumer (container Docker)
├── Consomme topic Kafka : fcc-compliance
└── Écrit dans IBM MQ
```

**En Serverless - Option A : Lambda + MSK Trigger** :
```
Amazon MSK Serverless (Kafka)
├── Topic: fcc-compliance
└── Lambda Trigger
    └── FccKafkaConsumerLambda
        └── Écrit dans Amazon MQ (IBM MQ compatible)
```

**Configuration** :
```yaml
FccKafkaConsumerLambda:
  Type: AWS::Serverless::Function
  Properties:
    Runtime: java21
    Handler: com.bnc.mcp.fcc.FccConsumerLambda::handleRequest
    Events:
      KafkaTrigger:
        Type: MSK
        Properties:
          Stream: !Ref MSKCluster
          Topics:
            - fcc-compliance
          StartingPosition: LATEST
```

**En Serverless - Option B : EventBridge + Lambda** :
```
EventBridge Rule
├── Source: Kafka MSK
├── Event Pattern: topic = fcc-compliance
└── Target: Lambda FccConsumerLambda
```

**Migration** :
- ✅ Code consumer Kafka → Lambda handler (1 journée)
- ✅ Pas de gestion d'infrastructure
- ✅ Auto-scaling automatique

---

## 📦 Services d'Infrastructure Serverless

### Services DÉJÀ Serverless

| Service Local | Service AWS | Type | Commentaire |
|---------------|-------------|------|-------------|
| LocalStack DynamoDB | **DynamoDB** | ✅ Serverless | Pay-per-request mode |
| LocalStack SNS | **Amazon SNS** | ✅ Serverless | SMS OTP |
| LocalStack SES | **Amazon SES** | ✅ Serverless | Emails |
| LocalStack SQS | **Amazon SQS** | ✅ Serverless | Fraud review queue |
| Step Functions Local | **AWS Step Functions** | ✅ Serverless | Orchestration |
| - | **CloudWatch Logs** | ✅ Serverless | Logs JSON |
| - | **X-Ray** | ✅ Serverless | Tracing distribué |

### Services Gérés (Pas Serverless, mais Sans Kubernetes)

| Service Local | Service AWS | Type | Commentaire |
|---------------|-------------|------|-------------|
| Kafka | **MSK Serverless** | 🟡 Serverless* | Kafka géré sans clusters |
| IBM MQ | **Amazon MQ** | 🟠 Géré | Broker RabbitMQ/ActiveMQ géré |
| Splunk | **CloudWatch + Splunk Cloud** | 🟡 SaaS | Splunk Cloud (SaaS) |
| WireMock (MDMAE) | **MDMAE réel** | - | API externe BNC |

**MSK Serverless** : Kafka sans gestion de brokers, auto-scaling
**Amazon MQ** : IBM MQ géré par AWS (pas de serveurs à gérer)

---

## 💰 Estimation des Coûts Serverless vs Containers

### Scénario : 10,000 demandes/jour (name/address/phone updates)

#### Option 1 : Containers sur Kubernetes/ECS

```
Infrastructure :
- 3 ECS Fargate tasks (2 vCPU, 4GB RAM)
  → 3 × $0.04/h × 730h = $87.60/mois

- Application Load Balancer
  → $16.20 + data = ~$25/mois

- ECS Cluster (gratuit)

Total : ~$112/mois (fixe, même sans trafic)
```

#### Option 2 : Serverless (Lambda + API Gateway)

```
Lambda (30 fonctions) :
- 10,000 req/jour × 30 jours = 300,000 invocations
- Durée moyenne : 2 secondes
- RAM : 512 MB

Calcul :
- Invocations : 300,000 × $0.0000002 = $0.06
- Durée : 300,000 × 2s × 512MB = 300,000 GB-s
  → (300,000 - 400,000 free) = 0 (dans free tier)
  → $0

API Gateway :
- 300,000 req × $0.0000035 = $1.05

DynamoDB (on-demand) :
- Estimé ~$5/mois

Total : ~$6/mois (pay-per-use)
```

**Économie** : **95% moins cher** pour faible/moyen trafic !

### Scénario : 1,000,000 demandes/jour (haute charge)

#### Containers :
```
- 10 ECS Fargate tasks = $292/mois
- ALB = $25/mois
Total : ~$317/mois
```

#### Serverless :
```
- Lambda : ~$45/mois
- API Gateway : ~$105/mois
- DynamoDB : ~$50/mois
Total : ~$200/mois
```

**Économie** : **37% moins cher** même en haute charge

---

## ⚡ Performance & Cold Starts

### Problème des Cold Starts Java

| Méthode | Cold Start | Warm Request | RAM | Complexité |
|---------|------------|--------------|-----|------------|
| Spring Boot classique | 3-5s | 50ms | 512MB | Facile |
| **SnapStart (RECOMMANDÉ)** | **500ms** | **50ms** | **512MB** | **Facile** |
| GraalVM Native | 800ms | 30ms | 256MB | Difficile |
| Provisioned Concurrency | 0ms | 50ms | 512MB | $$ Coûteux |

**Recommandation BNC** : **Lambda SnapStart**
- ✅ Activation 1-ligne dans template SAM
- ✅ Réduction 90% cold start
- ✅ Code Spring Boot sans modification
- ✅ Pas de surcoût

```yaml
# Exemple activation SnapStart
PhoneValidatorLambda:
  Type: AWS::Serverless::Function
  Properties:
    Runtime: java21
    SnapStart:
      ApplyOn: PublishedVersions  ← 1 LIGNE !
```

---

## 🏗️ Architecture Serverless Complète

```
┌─────────────────────────────────────────────────────────────────────┐
│ CLIENTS (Web, Mobile, Partenaires)                                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│ EDGE LAYER                                                          │
├─────────────────────────────────────────────────────────────────────┤
│ CloudFront CDN + WAF                                                │
│ ├── Protection DDoS                                                 │
│ ├── Rate limiting                                                   │
│ └── Cache statique                                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│ API LAYER - API Gateway REST                                        │
├─────────────────────────────────────────────────────────────────────┤
│ Routes :                                                            │
│ POST /clients/{id}/name      → Lambda: api-change-name             │
│ POST /clients/{id}/address   → Lambda: api-change-address          │
│ POST /clients/{id}/phone     → Lambda: api-change-phone            │
│ GET  /clients/{id}           → Lambda: api-get-client              │
│                                                                     │
│ Features :                                                          │
│ - Throttling (10,000 req/s)                                         │
│ - API Keys & Usage Plans                                            │
│ - Request/Response validation                                       │
│ - CORS                                                              │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│ ORCHESTRATION LAYER - AWS Step Functions                           │
├─────────────────────────────────────────────────────────────────────┤
│ State Machines :                                                    │
│ ├── ClientNameUpdate     (6 steps)                                 │
│ ├── ClientAddressUpdate  (8 steps)                                 │
│ └── ClientPhoneUpdate    (17 steps, OTP, fraud detection)          │
│                                                                     │
│ Features :                                                          │
│ - Retry automatique (exponential backoff)                          │
│ - Error handling (Catch, Fail states)                              │
│ - Compensation (Saga pattern)                                       │
│ - Monitoring intégré                                                │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│ BUSINESS LOGIC LAYER - Lambda Functions (30+)                      │
├─────────────────────────────────────────────────────────────────────┤
│ Phone Update Workflow (12 Lambdas) :                               │
│ ├── ReadClientProfileLambda                                        │
│ ├── PhoneValidatorLambda                                           │
│ ├── CheckPhoneHistoryLambda                                        │
│ ├── HumanApprovalLambda                                            │
│ ├── SendOTPSMSLambda                                               │
│ ├── CheckOTPStatusLambda                                           │
│ ├── PhoneMDMAEClientLambda      ← CRITIQUE (3-level retry)         │
│ ├── FCCSenderLambda                                                │
│ ├── CRMUpdaterLambda                                               │
│ ├── NotificationUpdaterLambda                                      │
│ ├── NotificationSenderLambda                                       │
│ └── RecordPhoneHistoryLambda                                       │
│                                                                     │
│ + Name Update (6 Lambdas)                                          │
│ + Address Update (8 Lambdas)                                       │
│ + Shared utilities                                                  │
│                                                                     │
│ Runtime : Java 21 + SnapStart                                      │
│ Memory : 256-512 MB                                                 │
│ Timeout : 15-60 secondes                                            │
└────────────────────────────┬────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│ DATA LAYER - AWS Serverless Services                               │
├─────────────────────────────────────────────────────────────────────┤
│ DynamoDB Tables (On-Demand) :                                      │
│ ├── mcp-client-profile                                             │
│ ├── PhoneNumberHistory        (TTL: 7 ans, audit)                  │
│ ├── OTPCodes                  (TTL: 5 minutes)                      │
│ └── NameChangeHistory         (TTL: 7 ans, audit)                  │
│                                                                     │
│ Messaging :                                                         │
│ ├── SNS : OTP SMS                                                   │
│ ├── SES : Email confirmations                                      │
│ └── SQS : phone-fraud-review-queue                                 │
│                                                                     │
│ Kafka :                                                             │
│ └── MSK Serverless                                                  │
│     ├── Topic: fcc-compliance                                       │
│     └── Topic: client-notifications                                │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ INTEGRATION LAYER                                                   │
├─────────────────────────────────────────────────────────────────────┤
│ MDMAE (MDM externe BNC) ← HTTP REST avec retry + idempotency       │
│ CRM (Mock en dev)       ← API externe                              │
│ Amazon MQ               ← IBM MQ géré pour FCC                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ OBSERVABILITY LAYER                                                 │
├─────────────────────────────────────────────────────────────────────┤
│ CloudWatch :                                                        │
│ ├── Logs (JSON structuré, retention 7 jours)                       │
│ ├── Metrics (latence, erreurs, throttling)                         │
│ └── Alarms (SNS notifications)                                      │
│                                                                     │
│ X-Ray :                                                             │
│ ├── Tracing distribué (correlationId)                              │
│ ├── Service map                                                     │
│ └── Latency analysis                                                │
│                                                                     │
│ Splunk Cloud (SaaS) :                                               │
│ └── Logs envoyés via Lambda Forwarder                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Plan de Migration vers Serverless

### Phase 1 : Préparation (1 semaine)

- [ ] Audit dépendances (vérifier compatibilité Lambda)
- [ ] Créer compte AWS Organization BNC
- [ ] Setup CI/CD (GitHub Actions + AWS SAM)
- [ ] Créer environnements : dev, staging, prod
- [ ] Formation équipe sur Lambda + Step Functions

### Phase 2 : Migration Infrastructure (1 semaine)

- [ ] Créer tables DynamoDB en production
- [ ] Configurer SNS/SES/SQS
- [ ] Setup MSK Serverless (Kafka)
- [ ] Setup Amazon MQ (IBM MQ)
- [ ] Configurer CloudWatch + X-Ray

### Phase 3 : Migration mcp-orchestration (2-3 semaines)

**Étape 1** : Handlers Phone Update (1 semaine)
- [ ] Créer 12 Lambda functions (phone workflow)
- [ ] Migrer state machine vers Step Functions production
- [ ] Tests end-to-end
- [ ] Déployer en dev puis staging

**Étape 2** : Handlers Name/Address Update (1 semaine)
- [ ] Créer Lambda functions name/address
- [ ] Migrer state machines
- [ ] Tests

**Étape 3** : Optimisation (3 jours)
- [ ] Activer SnapStart sur toutes les Lambdas
- [ ] Tuning mémoire/timeout
- [ ] Load testing

### Phase 4 : Migration mcp-api (1 semaine)

- [ ] API Gateway : créer routes REST
- [ ] Migrer controllers vers Lambda
- [ ] Configuration throttling/usage plans
- [ ] Setup CloudFront + WAF
- [ ] Tests de charge
- [ ] Déploiement staging

### Phase 5 : Migration mcp-fcc-connector (3 jours)

- [ ] Lambda consumer Kafka MSK
- [ ] Event Source Mapping Kafka → Lambda
- [ ] Tests avec Amazon MQ
- [ ] Déploiement staging

### Phase 6 : Tests & Validation (1 semaine)

- [ ] Tests end-to-end complets
- [ ] Tests de charge (1M req/jour)
- [ ] Tests de failover
- [ ] Validation sécurité
- [ ] Validation conformité FCC

### Phase 7 : Production (1 semaine)

- [ ] Déploiement progressif (canary 10% → 50% → 100%)
- [ ] Monitoring 24/7
- [ ] Rollback plan
- [ ] Documentation opérationnelle
- [ ] Formation support N2/N3

**Total** : **8-10 semaines** pour migration complète

---

## ✅ Avantages Serverless pour BNC

### 1. Réduction des Coûts
- 💰 **95% moins cher** pour trafic faible/moyen
- 💰 Pas de coûts infrastructure quand pas de trafic
- 💰 Pas de sur-provisionnement

### 2. Zero Gestion Infrastructure
- ✅ Pas de serveurs à patcher
- ✅ Pas de Kubernetes à gérer
- ✅ Pas de scaling manuel
- ✅ Haute disponibilité native (multi-AZ)

### 3. Scalabilité Automatique
- ⚡ Auto-scaling instantané (0 → 10,000 req/s)
- ⚡ Pas de tuning capacity planning
- ⚡ Handle peak loads automatiquement

### 4. Développement Rapide
- 🚀 Déploiement en 2-3 minutes
- 🚀 Pas de build/push d'images Docker
- 🚀 CI/CD simplifié (SAM/Serverless Framework)

### 5. Observabilité Native
- 📊 CloudWatch Logs automatique
- 📊 X-Ray tracing intégré
- 📊 Metrics sans configuration

### 6. Sécurité
- 🔒 IAM roles par fonction
- 🔒 VPC isolation
- 🔒 Secrets Manager intégration
- 🔒 Pas de CVE à patcher manuellement

---

## ⚠️ Considérations & Limites

### Limites Lambda

| Limite | Valeur | Impact MCP |
|--------|--------|------------|
| Timeout max | 15 minutes | ✅ OK (handlers < 60s) |
| Payload max | 6 MB | ✅ OK (JSON < 256 KB) |
| Déploiement max | 250 MB | ✅ OK (JAR Spring Boot ~40 MB) |
| Concurrent executions | 1000 (quota augmentable) | ✅ OK pour BNC |
| Cold start | 500ms-3s | ⚠️ SnapStart requis |

### Quand NE PAS Utiliser Serverless

❌ **WebSocket long-lived connections** (> 15 min)
- Solution : API Gateway WebSocket (max 2h) ou Fargate

❌ **Batch processing lourd** (> 15 min)
- Solution : ECS Fargate tasks ou Step Functions + SQS chunking

❌ **Stateful applications** nécessitant cache in-memory partagé
- Solution : ElastiCache Redis

❌ **GPU/ML inference lourd**
- Solution : SageMaker ou EC2 GPU

**Pour MCP** : ✅ Tous les workflows sont < 5 minutes → **100% compatible serverless**

---

## 🔐 Sécurité Serverless

### Architecture Réseau

```
Internet
    │
    ▼
CloudFront + WAF
    │
    ▼
API Gateway (public)
    │
    ▼
Lambda (VPC privé)
    │
    ├──▶ DynamoDB (VPC endpoint)
    ├──▶ SNS/SES/SQS (VPC endpoint)
    ├──▶ Secrets Manager (VPC endpoint)
    └──▶ MDMAE (NAT Gateway → Internet)
```

### IAM Least Privilege

Chaque Lambda a un rôle IAM minimal :

```yaml
# Exemple : PhoneValidatorLambda IAM Role
PhoneValidatorLambdaRole:
  Type: AWS::IAM::Role
  Properties:
    Policies:
      - PolicyName: DynamoDBReadOnly
        PolicyDocument:
          Statement:
            - Effect: Allow
              Action:
                - dynamodb:GetItem
              Resource: !GetAtt ClientProfileTable.Arn
      - PolicyName: CloudWatchLogs
        PolicyDocument:
          Statement:
            - Effect: Allow
              Action:
                - logs:CreateLogGroup
                - logs:CreateLogStream
                - logs:PutLogEvents
              Resource: arn:aws:logs:*:*:*
```

**Principe** : Chaque Lambda ne peut accéder QU'À ses ressources nécessaires.

### Secrets Management

```java
// Code Lambda avec Secrets Manager
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;

public class PhoneMDMAEClientLambda {
    private final SecretsManagerClient secretsClient = SecretsManagerClient.create();

    private String getMdmaeApiKey() {
        GetSecretValueRequest request = GetSecretValueRequest.builder()
            .secretId("prod/mdmae/api-key")
            .build();
        return secretsClient.getSecretValue(request).secretString();
    }
}
```

---

## 📚 Stack Technologique Serverless

### Infrastructure as Code

**AWS SAM** (Serverless Application Model) - RECOMMANDÉ BNC
```yaml
# template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Globals:
  Function:
    Runtime: java21
    MemorySize: 512
    Timeout: 30
    Environment:
      Variables:
        AWS_REGION: ca-central-1

Resources:
  PhoneValidatorLambda:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: mcp-orchestration/
      Handler: com.bnc.mcp.phone.PhoneValidatorLambda::handleRequest
      SnapStart:
        ApplyOn: PublishedVersions
```

**Déploiement** :
```bash
sam build
sam deploy --guided
```

### CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy Serverless

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-java@v3
        with:
          java-version: '21'

      - name: Build with Maven
        run: mvn clean package

      - name: Deploy to AWS
        run: |
          sam build
          sam deploy --no-confirm-changeset --no-fail-on-empty-changeset
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

---

## 🎓 Formation Équipe

### Compétences Requises

| Compétence | Niveau | Formation |
|------------|--------|-----------|
| AWS Lambda | ⭐⭐⭐ | 1 semaine |
| Step Functions | ⭐⭐⭐ | 3 jours |
| DynamoDB | ⭐⭐ | 2 jours |
| API Gateway | ⭐⭐ | 2 jours |
| CloudWatch | ⭐⭐ | 1 jour |
| SAM/IaC | ⭐⭐⭐ | 1 semaine |
| Java SDK v2 | ⭐⭐ | Connu |

**Total formation** : 3-4 semaines pour équipe de 5 personnes

### Ressources

- AWS Training : "Building Serverless Applications" (gratuit)
- AWS Well-Architected Serverless Lens
- Documentation SAM : https://docs.aws.amazon.com/serverless-application-model/
- Workshop Step Functions : https://catalog.workshops.aws/stepfunctions/

---

## 📊 Monitoring & Alertes

### CloudWatch Dashboards

```
┌─────────────────────────────────────────────────────────────┐
│ MCP Serverless Dashboard                                   │
├─────────────────────────────────────────────────────────────┤
│ API Gateway                                                 │
│ - Requests/min                   [Graph]                    │
│ - Latency p50/p95/p99            [Graph]                    │
│ - 4xx/5xx errors                 [Graph]                    │
├─────────────────────────────────────────────────────────────┤
│ Lambda Functions                                            │
│ - Invocations/min                [Graph]                    │
│ - Duration avg/max               [Graph]                    │
│ - Errors & Throttles             [Graph]                    │
│ - Cold starts                    [Graph]                    │
├─────────────────────────────────────────────────────────────┤
│ Step Functions                                              │
│ - Executions started             [Graph]                    │
│ - Executions succeeded/failed    [Graph]                    │
│ - Execution duration             [Graph]                    │
├─────────────────────────────────────────────────────────────┤
│ DynamoDB                                                    │
│ - Read/Write capacity used       [Graph]                    │
│ - Throttled requests             [Graph]                    │
│ - System errors                  [Graph]                    │
└─────────────────────────────────────────────────────────────┘
```

### Alertes SNS

```yaml
# CloudWatch Alarms
HighErrorRateAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: MCP-PhoneUpdate-HighErrorRate
    MetricName: Errors
    Namespace: AWS/Lambda
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 10
    AlarmActions:
      - !Ref OpsTeamSNSTopic
```

---

## 🏁 Conclusion

### ✅ Recommandation Finale

**OUI**, MCP doit migrer vers une **architecture 100% serverless** :

1. **Pas de Kubernetes requis**
2. **Coûts réduits de 95%** (trafic faible/moyen)
3. **Zero gestion infrastructure**
4. **Auto-scaling natif**
5. **Migration en 8-10 semaines**
6. **Code métier déjà prêt** (handlers écrits pour Lambda)

### Architecture Cible

```
Serverless Stack :
├── API Gateway + Lambda         (remplace mcp-api)
├── Step Functions + Lambda (x30) (remplace mcp-orchestration)
├── Lambda + EventBridge         (remplace mcp-fcc-connector)
├── DynamoDB (serverless)
├── SNS/SES/SQS (serverless)
├── MSK Serverless (Kafka)
├── Amazon MQ (IBM MQ géré)
└── CloudWatch + X-Ray

Total : ZERO serveurs à gérer !
```

### Next Steps

1. **Valider avec architecture BNC**
2. **POC sur 1 workflow** (phone update, 2 semaines)
3. **Présenter business case** (95% économies)
4. **Lancer migration complète** (8-10 semaines)

---

**Préparé par** : Architecture Team MCP
**Contact** : architecture@bnc.ca
**Version** : 1.0 - 2026-09-25