# 📚 Guide Swagger UI - MCP API

Documentation interactive de l'API MCP avec Swagger UI.

---

## 🎯 Accès Rapide

### Environnement DEV

| Ressource | URL |
|-----------|-----|
| **Swagger UI** (Interface interactive) | https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/docs |
| **OpenAPI Spec** (swagger.json) | https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/swagger.json |
| **Endpoint API** | https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/nom |

> 💡 **Note**: L'URL Swagger UI change à chaque redéploiement de l'infrastructure. Utilisez `terraform output swagger_ui_url` pour obtenir l'URL actuelle.

---

## 🚀 Comment Utiliser Swagger UI

### 1. Ouvrir l'Interface

Ouvrez votre navigateur et allez sur:
```
https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/docs
```

Vous verrez une interface interactive avec:
- **En-tête**: Informations sur l'environnement (DEV/PROD, région, URL de base)
- **Liste des endpoints**: Tous les endpoints disponibles organisés par tags
- **Détails**: Description, paramètres, exemples de requêtes/réponses

### 2. Explorer les Endpoints

#### Endpoints Disponibles:

**Tag: Clients**
- `PUT /api/clients/{clientId}/nom` - Mise à jour du nom de famille d'un client

**Tag: Documentation**
- `GET /swagger.json` - Spécification OpenAPI
- `GET /docs` - Interface Swagger UI

### 3. Tester un Endpoint (Try it out!)

#### Exemple: Mettre à jour le nom d'un client

1. **Cliquer sur** `PUT /api/clients/{clientId}/nom`
   - La section se déploie avec tous les détails

2. **Cliquer sur** "Try it out" (bouton en haut à droite)
   - Les champs deviennent éditables

3. **Remplir les paramètres**:

   **Parameters (Path)**:
   ```
   clientId: TEST123
   ```

   **Request body**:
   ```json
   {
     "newLastName": "Leblanc",
     "reason": "MARIAGE"
   }
   ```

4. **Cliquer sur** "Execute" (bouton bleu)

5. **Voir la réponse**:
   ```json
   {
     "message": "Client name update initiated",
     "executionArn": "arn:aws:states:ca-central-1:...:execution:dev-mcp-client_name_update:..."
   }
   ```

---

## 📖 Détails de l'API

### PUT /api/clients/{clientId}/nom

**Description**: Met à jour le nom de famille d'un client existant. Cette opération déclenche un workflow Step Functions qui:

1. Valide l'existence du client
2. Recherche les doublons potentiels (via MDMAE)
3. Met à jour le profil dans DynamoDB
4. Publie un événement Kafka
5. Propage vers le FCC (si applicable)

**Paramètres**:

| Nom | Type | Requis | Description |
|-----|------|--------|-------------|
| `clientId` | Path | ✅ | Identifiant unique du client (ex: TEST123) |
| `newLastName` | Body | ✅ | Nouveau nom de famille |
| `reason` | Body | ✅ | Raison du changement (MARIAGE, DIVORCE, CORRECTION, AUTRE) |

**Exemples de requêtes**:

**Changement suite à un mariage**:
```json
{
  "newLastName": "Leblanc",
  "reason": "MARIAGE"
}
```

**Changement suite à un divorce**:
```json
{
  "newLastName": "Tremblay",
  "reason": "DIVORCE"
}
```

**Correction d'erreur**:
```json
{
  "newLastName": "Gagnon",
  "reason": "CORRECTION"
}
```

**Réponses**:

| Code | Description | Exemple |
|------|-------------|---------|
| **200** | Demande acceptée et workflow démarré | `{"message":"Client name update initiated","executionArn":"arn:..."}` |
| **400** | Requête invalide | `{"error":"BadRequest","message":"Le champ 'newLastName' est requis"}` |
| **404** | Client non trouvé | `{"error":"NotFound","message":"Client INVALID123 introuvable"}` |
| **500** | Erreur serveur | `{"error":"InternalServerError","message":"..."}` |

---

## 🧪 Tests avec cURL

Si vous préférez la ligne de commande:

### Récupérer la spec OpenAPI

```bash
curl -s https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/swagger.json | jq .
```

### Mettre à jour un nom de client

```bash
curl -X PUT "https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/nom" \
  -H "Content-Type: application/json" \
  -d '{
    "newLastName": "Leblanc",
    "reason": "MARIAGE"
  }' | jq .
```

---

## 🔧 Configuration Technique

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      API Gateway                             │
│                     (kay1jn7cz1)                             │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────────┐  ┌──────────────┐
│ PUT /api/    │  │ GET /swagger.json│  │ GET /docs    │
│ clients/     │  │                  │  │              │
│ {id}/nom     │  │  (Mock)          │  │  (Lambda)    │
└──────────────┘  └──────────────────┘  └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
 Step Functions       OpenAPI Spec       Swagger UI HTML
```

### Ressources Créées

| Ressource | Nom | Description |
|-----------|-----|-------------|
| Lambda Function | `dev-mcp-swagger-ui` | Sert l'interface Swagger UI |
| API Gateway Resource | `/docs` | Endpoint pour Swagger UI |
| API Gateway Resource | `/swagger.json` | Endpoint pour la spec OpenAPI |
| API Gateway Method | `GET /docs` | Méthode HTTP pour Swagger UI |
| API Gateway Method | `GET /swagger.json` | Méthode HTTP pour la spec |
| Lambda Permission | - | Permet à API Gateway d'invoquer la Lambda Swagger UI |
| CloudWatch Log Group | `/aws/lambda/dev-mcp-swagger-ui` | Logs de la Lambda Swagger UI |

---

## 🎨 Fonctionnalités Swagger UI

### Filtrage

Utilisez la barre de recherche en haut pour filtrer les endpoints par:
- Nom de l'opération
- Tag
- Description

### Exemples Interactifs

Swagger UI charge automatiquement les exemples de requêtes prédéfinis:
- **mariage**: Changement de nom suite à un mariage
- **divorce**: Changement de nom suite à un divorce
- **correction**: Correction d'une erreur

Cliquez sur un exemple pour charger automatiquement les valeurs.

### Copier comme cURL

Après avoir exécuté une requête, cliquez sur "Copy as cURL" pour obtenir la commande cURL équivalente.

### Télécharger la Spec

Cliquez sur "Download" dans le menu du haut pour télécharger la spécification OpenAPI au format JSON ou YAML.

---

## 🔄 Mise à Jour de la Documentation

### Après Ajout d'un Nouveau Endpoint

Si vous ajoutez un nouveau endpoint à l'API Gateway:

1. **Mettre à jour le fichier OpenAPI**:
   ```bash
   vim /Users/fabricefoko/Documents/mcp-infrastructure/modules/api-gateway/openapi-spec.json.tpl
   ```

2. **Ajouter la définition de l'endpoint** dans la section `paths`

3. **Redéployer**:
   ```bash
   cd environments/dev
   terraform apply -target=module.api_gateway -auto-approve
   ```

4. **Vérifier**:
   - Ouvrir Swagger UI
   - Rafraîchir la page
   - Le nouvel endpoint devrait apparaître

### Exemple d'Ajout d'Endpoint

```json
"/api/clients/{clientId}/address": {
  "put": {
    "tags": ["Clients"],
    "summary": "Mise à jour de l'adresse d'un client",
    "description": "Met à jour l'adresse postale d'un client",
    "operationId": "updateClientAddress",
    "parameters": [
      {
        "name": "clientId",
        "in": "path",
        "required": true,
        "schema": {"type": "string"}
      }
    ],
    "requestBody": {
      "required": true,
      "content": {
        "application/json": {
          "schema": {
            "type": "object",
            "properties": {
              "newAddress": {"type": "string"},
              "reason": {"type": "string"}
            }
          }
        }
      }
    },
    "responses": {
      "200": {
        "description": "Mise à jour initiée"
      }
    }
  }
}
```

---

## 📊 Monitoring

### Logs Lambda Swagger UI

```bash
# Voir les logs en temps réel
aws logs tail /aws/lambda/dev-mcp-swagger-ui --follow --region ca-central-1

# Rechercher des erreurs
aws logs filter-log-events \
  --log-group-name /aws/lambda/dev-mcp-swagger-ui \
  --filter-pattern "ERROR" \
  --region ca-central-1
```

### Métriques API Gateway

```bash
# Nombre de requêtes vers /docs
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApiGateway \
  --metric-name Count \
  --dimensions Name=ApiName,Value=dev-mcp-api Name=Resource,Value=/docs Name=Method,Value=GET \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Sum \
  --region ca-central-1
```

---

## 🐛 Troubleshooting

### Problème: Swagger UI affiche "Failed to load API definition"

**Cause**: Le fichier swagger.json n'est pas accessible ou contient des erreurs

**Solution**:
```bash
# Vérifier que swagger.json est accessible
curl -s https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/swagger.json | jq .

# Valider la spec OpenAPI
curl -s https://kay1jn7cz1.execute-api.ca-central-1.amazonaws.com/dev/swagger.json | \
  npx @apidevtools/swagger-cli validate /dev/stdin
```

### Problème: 403 Forbidden sur /docs

**Cause**: Le déploiement API Gateway n'inclut pas les nouvelles ressources

**Solution**:
```bash
cd environments/dev
terraform apply -target=module.api_gateway -replace=module.api_gateway.aws_api_gateway_deployment.main -auto-approve
```

### Problème: Lambda Swagger UI timeout

**Cause**: La Lambda met trop de temps à répondre

**Solution**:
```bash
# Augmenter le timeout dans swagger.tf
timeout = 30  # au lieu de 10

# Redéployer
terraform apply -target=module.api_gateway.aws_lambda_function.swagger_ui -auto-approve
```

---

## 🔐 Sécurité

### Accès Public

Actuellement, Swagger UI est **accessible publiquement** (aucune authentification requise).

Pour un environnement de production, considérez:

1. **Ajouter une clé API**:
   ```hcl
   resource "aws_api_gateway_method" "get_docs" {
     authorization = "API_KEY"
     api_key_required = true
   }
   ```

2. **Utiliser AWS Cognito**:
   ```hcl
   resource "aws_api_gateway_method" "get_docs" {
     authorization = "COGNITO_USER_POOLS"
     authorizer_id = aws_api_gateway_authorizer.cognito.id
   }
   ```

3. **Restreindre par IP** (via WAF):
   ```bash
   # Créer une rule WAF qui autorise seulement certaines IPs
   ```

---

## 📞 Support

Pour des questions ou problèmes:

1. Consulter ce guide
2. Vérifier les logs CloudWatch
3. Contacter l'équipe DevOps

---

**Dernière mise à jour**: 2026-09-29
**Version de l'API**: 1.0.0