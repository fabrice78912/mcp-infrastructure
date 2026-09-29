# MCP Infrastructure - Terraform

Infrastructure as Code pour le projet MCP (Modernisation Changement de Profil) déployé sur AWS avec architecture 100% Lambda.

## Architecture

- **Lambda Functions** (7): Handlers pour workflow Step Functions
- **API Gateway**: REST API `/api/clients/{clientId}/nom`
- **Step Functions**: Orchestration workflow ClientNameUpdate
- **DynamoDB**: Table ClientProfile
- **SQS**: Queues pour réponses FCC
- **EventBridge**: Schedule pour polling MQ (10s)
- **MSK Serverless**: Kafka pour événements
- **CloudWatch**: Logs et alarmes

## Prérequis

- Terraform >= 1.9.0
- AWS CLI configuré
- Compte AWS avec accès admin
- GitHub repository (pour secrets et actions)

## Structure du projet

```
mcp-infrastructure/
├── .github/workflows/          # GitHub Actions
├── environments/
│   ├── dev/                    # Configuration dev
│   └── prod/                   # Configuration prod
├── modules/                    # Modules Terraform réutilisables
│   ├── iam/
│   ├── dynamodb/
│   ├── lambda/
│   ├── api-gateway/
│   ├── step-functions/
│   ├── sqs/
│   ├── eventbridge/
│   ├── msk/
│   ├── vpc/
│   ├── cloudwatch/
│   └── secrets-manager/
└── scripts/                    # Scripts utilitaires
```

## Configuration des secrets GitHub

Allez dans **Settings > Secrets and variables > Actions** et ajoutez:

### Secrets AWS (requis)
- `AWS_ACCESS_KEY_ID`: Access key IAM user
- `AWS_SECRET_ACCESS_KEY`: Secret key IAM user
- `AWS_REGION`: `ca-central-1`

### Secrets applicatifs (requis)
- `DEV_IBM_MQ_HOST`: Host IBM MQ dev (ex: ngrok URL)
- `DEV_IBM_MQ_PORT`: Port MQ dev (ex: `1414`)
- `DEV_IBM_MQ_CHANNEL`: Channel MQ dev (ex: `DEV.APP.SVRCONN`)
- `DEV_IBM_MQ_PASSWORD`: Password MQ dev
- `DEV_MDMAE_URL`: URL MDMAE dev (ex: `http://localhost:8089`)

- `PROD_IBM_MQ_HOST`: Host IBM MQ prod
- `PROD_IBM_MQ_PORT`: Port MQ prod
- `PROD_IBM_MQ_CHANNEL`: Channel MQ prod
- `PROD_IBM_MQ_PASSWORD`: Password MQ prod
- `PROD_MDMAE_URL`: URL MDMAE prod

### Secrets optionnels
- `SPLUNK_HEC_TOKEN`: Token Splunk HEC (si utilisé)

## Initialisation (première fois)

### 1. Créer le backend S3 + DynamoDB

```bash
# Dev
./scripts/create-backend.sh dev

# Prod
./scripts/create-backend.sh prod
```

Cela crée:
- Bucket S3: `mcp-terraform-state-{env}`
- Table DynamoDB: `mcp-terraform-lock-{env}`

### 2. Initialiser Terraform localement (optionnel)

```bash
cd environments/dev
terraform init
terraform plan
```

## Déploiement via GitHub Actions

### Workflow Dispatch (déclenchement manuel)

1. Allez dans **Actions > Deploy MCP Infrastructure**
2. Cliquez sur **Run workflow**
3. Sélectionnez:
   - **Environment**: `dev` ou `prod`
   - **Action**: `plan` (voir changements) ou `apply` (déployer)
4. Cliquez sur **Run workflow**

### Plan (voir les changements sans appliquer)

```
Environment: dev
Action: plan
```

Cela exécute `terraform plan` et affiche les ressources qui seront créées/modifiées.

### Apply (déployer les changements)

```
Environment: dev
Action: apply
```

Cela exécute `terraform apply -auto-approve` et crée les ressources.

### Destroy (supprimer toutes les ressources)

```
Environment: dev
Action: destroy
```

⚠️ **ATTENTION**: Pour prod, il y a une protection. Vous devez d'abord modifier le workflow.

## Stratégie de déploiement

### Dev (branche `dev`)

1. Push code sur branche `dev`
2. Déclencher workflow avec `environment: dev` et `action: plan`
3. Vérifier les changements
4. Déclencher workflow avec `environment: dev` et `action: apply`

### Prod (branche `prod`)

1. Créer Pull Request `dev` → `prod`
2. Review par au moins 1 personne (configurer branch protection)
3. Merge PR
4. Déclencher workflow avec `environment: prod` et `action: plan`
5. Vérifier les changements
6. Déclencher workflow avec `environment: prod` et `action: apply`

## Différences dev vs prod

| Ressource | Dev | Prod |
|-----------|-----|------|
| **Lambda RAM** | 512 MB | 1024 MB |
| **Lambda timeout** | 60s | 300s |
| **DynamoDB backup** | Non | Point-in-Time Recovery |
| **CloudWatch retention** | 3 jours | 30 jours |
| **CloudWatch alarms** | Désactivées | Activées |
| **MSK partitions** | 1 | 3 |
| **API Gateway throttling** | 100 req/s | 1000 req/s |

## Ajouter un nouveau workflow Step Functions

1. Créer le fichier JSON:
   ```bash
   # modules/step-functions/state-machines/client-address-update.json
   ```

2. Ajouter dans `environments/{env}/main.tf`:
   ```hcl
   module "step_functions" {
     source = "../../modules/step-functions"

     state_machines = {
       "client-name-update" = {
         definition_file = "client-name-update.json"
       },
       "client-address-update" = {  # NOUVEAU
         definition_file = "client-address-update.json"
       }
     }
   }
   ```

3. Déployer via GitHub Actions

## Outputs

Après déploiement, vous obtenez:

```bash
# Dev
cd environments/dev
terraform output

# Résultat:
api_gateway_url = "https://xxxxx.execute-api.ca-central-1.amazonaws.com/dev"
state_machine_arn = "arn:aws:states:ca-central-1:xxx:stateMachine:ClientNameUpdate"
lambda_functions = {
  "mcp-client-profile-reader" = "arn:aws:lambda:ca-central-1:xxx:function:dev-mcp-client-profile-reader"
  ...
}
```

## Monitoring

- **CloudWatch Logs**: `/aws/lambda/{function-name}`
- **CloudWatch Alarms**: Tableau de bord auto-généré (prod seulement)
- **Terraform drift detection**: Action quotidienne à 9h UTC

## Coûts estimés

- **Dev**: ~$20-30/mois
- **Prod**: ~$40-50/mois

## Dépannage

### Erreur: Backend S3 not found

```bash
./scripts/create-backend.sh dev
```

### Erreur: Terraform state lock

```bash
# Forcer le unlock (DANGEREUX)
terraform force-unlock <LOCK_ID>
```

### Logs GitHub Actions

Allez dans **Actions > [Workflow run] > [Job] > [Step]**

## Support

Pour toute question, créer une issue GitHub ou contacter l'équipe DevOps.

---

**Version**: 1.0
**Dernière mise à jour**: 2026-09-23
**Auteur**: Équipe MCP