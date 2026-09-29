# 🚀 Quick Start - MCP Infrastructure

Guide de démarrage rapide pour gérer l'infrastructure MCP.

---

## 📌 Liens Rapides

- 📖 [Guide Complet de Destroy/Recreate](docs/DESTROY-RECREATE-GUIDE.md)
- 🛠️ [Documentation des Scripts](scripts/README.md)
- 🏗️ [Architecture](docs/ARCHITECTURE.md)
- 📚 [Guide Swagger UI](docs/SWAGGER-UI-GUIDE.md) - Documentation interactive de l'API

---

## ⚡ Commandes Essentielles

### Détruire l'Infrastructure (via GitHub Actions)

1. Aller dans **Actions** → **Deploy MCP Infrastructure**
2. **Run workflow** avec:
   - Environment: `dev`
   - Action: `destroy`

**⚠️ ATTENTION**: Opération irréversible! Toutes les données seront perdues.

---

### Recréer l'Infrastructure

#### Option A: GitHub Actions (Recommandé)

```
1. Vérifier les JARs dans S3:
   ./scripts/upload-lambda-jars.sh

2. GitHub Actions → Deploy MCP Infrastructure
   - Environment: dev
   - Action: apply

3. Configuration post-déploiement:
   ./scripts/post-deploy-setup.sh dev
```

#### Option B: Ligne de Commande

```bash
# 1. Upload des JARs
./scripts/upload-lambda-jars.sh

# 2. Terraform apply
cd environments/dev
terraform apply -var-file=dev.tfvars

# 3. Configuration
cd ../..
./scripts/post-deploy-setup.sh dev
```

---

## 🎯 Scripts Disponibles

### `post-deploy-setup.sh` - Configuration Automatique

```bash
# Configure tout après un déploiement
./scripts/post-deploy-setup.sh dev
```

**Ce qu'il fait**:
- Configure les secrets (IBM MQ, MDMAE)
- Charge les données de test
- Teste l'API Gateway

### `upload-lambda-jars.sh` - Upload des JARs

```bash
# Upload tous les JARs Lambda vers S3
./scripts/upload-lambda-jars.sh

# Ou spécifier le chemin
./scripts/upload-lambda-jars.sh ~/mcp-orchestration/target
```

---

## 📦 Prérequis

Avant de commencer, vérifier:

```bash
# AWS CLI configuré
aws sts get-caller-identity

# Terraform installé (>= 1.9.0)
terraform version

# jq installé
jq --version

# Accès au bucket S3
aws s3 ls s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
```

---

## 🔄 Workflow Complet (Destroy → Recreate)

```
┌──────────────────────────────────────────┐
│ 1. DESTROY (GitHub Actions)              │
│    Environment: dev, Action: destroy     │
│    Durée: 2-3 min                        │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ 2. UPLOAD JARs                           │
│    ./scripts/upload-lambda-jars.sh       │
│    Durée: 1 min                          │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ 3. APPLY (GitHub Actions)                │
│    Environment: dev, Action: apply       │
│    Durée: 5-7 min                        │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ 4. CONFIGURE                             │
│    ./scripts/post-deploy-setup.sh dev    │
│    Durée: 3-5 min                        │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ 5. ✅ OPÉRATIONNEL                        │
└──────────────────────────────────────────┘

Durée totale: ~15-20 minutes
```

---

## 🧪 Tester l'API

### Option A: Via Swagger UI (Recommandé) 📚

L'interface interactive Swagger UI permet de tester tous les endpoints directement depuis votre navigateur.

```bash
# Récupérer l'URL Swagger UI
cd environments/dev
terraform output swagger_ui_url
```

**Ouvrir dans le navigateur**:
```
https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/docs
```

**Utilisation**:
1. Cliquer sur `PUT /api/clients/{clientId}/nom`
2. Cliquer sur "Try it out"
3. Remplir:
   - **clientId**: `TEST123`
   - **Request body**:
     ```json
     {
       "newLastName": "Leblanc",
       "reason": "MARIAGE"
     }
     ```
4. Cliquer sur "Execute"
5. Voir la réponse en temps réel!

🎯 **Voir le [Guide Swagger UI complet](docs/SWAGGER-UI-GUIDE.md) pour plus de détails**

### Option B: Via cURL (Ligne de commande)

Après le déploiement, récupérer l'URL:

```bash
cd environments/dev
terraform output api_gateway_url
```

Tester l'endpoint:

```bash
# Remplacer [API-ID] par le vrai ID
curl -X PUT "https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/nom" \
  -H "Content-Type: application/json" \
  -d '{"newLastName":"Leblanc","reason":"MARIAGE"}'
```

Réponse attendue:

```json
{
  "message": "Client name update initiated",
  "executionArn": "arn:aws:states:ca-central-1:...:execution:..."
}
```

---

## 🎨 Structure du Projet

```
mcp-infrastructure/
├── environments/
│   ├── dev/              # Config Terraform DEV
│   └── prod/             # Config Terraform PROD
├── modules/
│   ├── api-gateway/      # Module API Gateway
│   ├── lambda/           # Module Lambda Functions
│   ├── step-functions/   # Module Step Functions
│   ├── dynamodb/         # Module DynamoDB
│   └── ...
├── scripts/
│   ├── post-deploy-setup.sh     # Configuration post-déploiement
│   ├── upload-lambda-jars.sh    # Upload JARs vers S3
│   └── README.md                # Documentation des scripts
├── docs/
│   ├── DESTROY-RECREATE-GUIDE.md  # Guide détaillé destroy/recreate
│   └── ARCHITECTURE.md             # Documentation architecture
└── .github/
    └── workflows/
        └── terraform-deploy.yml   # Workflow GitHub Actions
```

---

## 🔧 Troubleshooting Rapide

### Problème: JARs manquants

```bash
# Upload les JARs
./scripts/upload-lambda-jars.sh ~/mcp-orchestration/target
```

### Problème: Secrets vides

```bash
# Reconfigurer les secrets
./scripts/post-deploy-setup.sh dev
```

### Problème: API Gateway 403

```bash
# Vérifier l'URL actuelle
cd environments/dev
terraform output api_gateway_url

# Forcer un nouveau déploiement
terraform apply -target=module.api_gateway -replace=module.api_gateway.aws_api_gateway_deployment.main -auto-approve
```

### Problème: DynamoDB vide

```bash
# Charger le client de test
aws dynamodb put-item \
  --table-name dev-ClientProfile \
  --item '{"clientId":{"S":"TEST123"},"firstName":{"S":"Jean"},"lastName":{"S":"Tremblay"},"dateOfBirth":{"S":"1990-01-01"},"email":{"S":"test@example.com"}}' \
  --region ca-central-1
```

---

## 📊 Ressources Déployées

| Ressource | Environnement DEV | Description |
|-----------|-------------------|-------------|
| API Gateway | `dev-mcp-api` | Endpoint REST pour update client |
| Step Functions | `dev-mcp-client_name_update` | Orchestration du workflow |
| Lambda Functions | 7 fonctions | Validation, Matching, Update, etc. |
| DynamoDB | `dev-ClientProfile` | Base de données clients |
| SQS Queues | 2 queues | fraud_review, fcc_responses |
| Secrets | 2 secrets | ibmmq, mdmae |

---

## 🌐 Environnements

### DEV
- **Region**: ca-central-1
- **State file**: S3 backend
- **Secrets**: `dev/mcp/*`
- **Tables**: `dev-*`

### PROD
- **Region**: ca-central-1
- **State file**: S3 backend (séparé)
- **Secrets**: `prod/mcp/*`
- **Tables**: `prod-*`

---

## 📝 Checklist Post-Déploiement

Avant de considérer l'infrastructure opérationnelle:

- [ ] Workflow GitHub Actions `apply` terminé avec succès
- [ ] JARs Lambda présents dans S3
- [ ] Secrets configurés (IBM MQ, MDMAE)
- [ ] Client TEST123 dans DynamoDB
- [ ] API Gateway répond (HTTP 200)
- [ ] Step Functions exécution réussie
- [ ] CloudWatch Logs visibles
- [ ] Nouvelle URL API documentée

---

## 📞 Support

- 📖 [Guide Détaillé](docs/DESTROY-RECREATE-GUIDE.md) pour plus d'informations
- 🛠️ [Documentation Scripts](scripts/README.md) pour les scripts
- 💬 Contacter l'équipe DevOps en cas de problème

---

## 🎓 Commandes Utiles

```bash
# Lister les ressources déployées
cd environments/dev
terraform state list

# Voir les outputs
terraform output

# Vérifier les logs Lambda
aws logs tail /aws/lambda/dev-mcp-name_validator --follow --region ca-central-1

# Lister les exécutions Step Functions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw state_machine_arns | jq -r '.client_name_update') \
  --region ca-central-1

# Scanner DynamoDB
aws dynamodb scan --table-name dev-ClientProfile --region ca-central-1

# Vérifier les secrets
aws secretsmanager get-secret-value --secret-id dev/mcp/ibmmq --region ca-central-1
```

---

**Dernière mise à jour**: 2026-09-29