# Configuration GitHub pour le déploiement AWS

Ce guide explique comment configurer les secrets et variables GitHub nécessaires pour déployer l'infrastructure MCP sur AWS via GitHub Actions.

---

## Table des matières

1. [Prérequis](#prérequis)
2. [Secrets AWS](#secrets-aws)
3. [Secrets Dev (Développement)](#secrets-dev-développement)
4. [Secrets Prod (Production)](#secrets-prod-production)
5. [Configuration des secrets sur GitHub](#configuration-des-secrets-sur-github)
6. [Déploiement via GitHub Actions](#déploiement-via-github-actions)
7. [Vérification](#vérification)

---

## Prérequis

- Un compte AWS avec accès administrateur
- Un compte GitHub avec accès au repository
- Les credentials AWS (Access Key ID et Secret Access Key)
- IBM MQ accessible depuis AWS (via ngrok pour dev ou EC2/Amazon MQ pour prod)

---

## Secrets AWS

Ces secrets sont **communs aux deux environnements** (dev et prod):

| Nom du secret | Description | Exemple de valeur |
|--------------|-------------|-------------------|
| `AWS_ACCESS_KEY_ID` | Access Key ID AWS | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Secret Access Key AWS | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | Région AWS | `ca-central-1` |

### Comment obtenir les credentials AWS

1. Connectez-vous à la console AWS
2. Allez dans **IAM** → **Users** → Votre utilisateur
3. Onglet **Security credentials**
4. Cliquez **Create access key**
5. Sélectionnez **CLI** ou **Third-party service**
6. Copiez **Access Key ID** et **Secret Access Key**

⚠️ **IMPORTANT**: Sauvegardez ces credentials en lieu sûr, vous ne pourrez plus voir le Secret Access Key après cette étape.

---

## Secrets Dev (Développement)

Ces secrets sont spécifiques à l'environnement **dev**:

| Nom du secret | Description | Exemple de valeur | Comment l'obtenir |
|--------------|-------------|-------------------|-------------------|
| `DEV_IBM_MQ_HOST` | Adresse du serveur IBM MQ | `0.tcp.ngrok.io` | URL ngrok ou IP du serveur |
| `DEV_IBM_MQ_PORT` | Port IBM MQ | `12345` | Port exposé par ngrok ou `1414` |
| `DEV_IBM_MQ_CHANNEL` | Canal IBM MQ | `DEV.APP.SVRCONN` | Configuration MQ locale |
| `DEV_IBM_MQ_PASSWORD` | Mot de passe IBM MQ | `passw0rd` | Mot de passe configuré dans Docker |
| `DEV_MDMAE_URL` | URL de l'API MDMAE dev | `https://mdmae-dev.example.com/api` | URL de votre API MDMAE |

### Configuration IBM MQ local avec ngrok (Dev)

Pour exposer votre IBM MQ local aux Lambdas AWS:

```bash
# Installer ngrok
brew install ngrok

# Authentification (créer un compte sur ngrok.com)
ngrok authtoken YOUR_TOKEN

# Exposer le port 1414 d'IBM MQ
ngrok tcp 1414
```

Ngrok affichera une URL comme `0.tcp.ngrok.io:12345`:
- **DEV_IBM_MQ_HOST**: `0.tcp.ngrok.io`
- **DEV_IBM_MQ_PORT**: `12345`

⚠️ **Note**: L'URL ngrok change à chaque redémarrage de ngrok (sauf avec un compte payant).

---

## Secrets Prod (Production)

Ces secrets sont spécifiques à l'environnement **prod**:

| Nom du secret | Description | Exemple de valeur | Comment l'obtenir |
|--------------|-------------|-------------------|-------------------|
| `PROD_IBM_MQ_HOST` | Adresse du serveur IBM MQ prod | `ibm-mq-prod.example.com` | IP EC2 ou endpoint Amazon MQ |
| `PROD_IBM_MQ_PORT` | Port IBM MQ prod | `1414` | Port standard IBM MQ |
| `PROD_IBM_MQ_CHANNEL` | Canal IBM MQ prod | `PROD.APP.SVRCONN` | Configuration MQ production |
| `PROD_IBM_MQ_PASSWORD` | Mot de passe IBM MQ prod | `SecureP@ssw0rd!` | Mot de passe sécurisé |
| `PROD_MDMAE_URL` | URL de l'API MDMAE prod | `https://mdmae.example.com/api` | URL de votre API MDMAE prod |
| `PROD_ALARM_EMAIL` | Email pour les alertes CloudWatch | `team-mcp@example.com` | Email de votre équipe |

### Options pour IBM MQ en production

**Option 1: Amazon MQ (recommandé)**
- Service géré AWS
- Haute disponibilité
- Pas de gestion d'infrastructure

**Option 2: EC2 avec IBM MQ**
- Déployer IBM MQ sur une instance EC2
- Plus de contrôle
- Nécessite maintenance

**Option 3: Serveur on-premise exposé via VPN**
- Connexion VPN Site-to-Site entre AWS et votre datacenter
- Sécurisé
- Complexe à mettre en place

---

## Configuration des secrets sur GitHub

### Via l'interface web GitHub

1. **Ouvrir les paramètres du repository**
   - Allez sur `https://github.com/VOTRE_ORG/mcp-infrastructure`
   - Cliquez sur **Settings**

2. **Accéder aux secrets**
   - Dans le menu de gauche: **Secrets and variables** → **Actions**
   - Cliquez sur l'onglet **Secrets**

3. **Ajouter chaque secret**
   - Cliquez **New repository secret**
   - Entrez le **Name** (ex: `AWS_ACCESS_KEY_ID`)
   - Entrez la **Value** (ex: `AKIAIOSFODNN7EXAMPLE`)
   - Cliquez **Add secret**

4. **Répéter pour tous les secrets**

### Via GitHub CLI (alternative)

```bash
# Installer GitHub CLI
brew install gh

# Authentification
gh auth login

# Ajouter les secrets
gh secret set AWS_ACCESS_KEY_ID --body "AKIAIOSFODNN7EXAMPLE"
gh secret set AWS_SECRET_ACCESS_KEY --body "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
gh secret set AWS_REGION --body "ca-central-1"

# Secrets Dev
gh secret set DEV_IBM_MQ_HOST --body "0.tcp.ngrok.io"
gh secret set DEV_IBM_MQ_PORT --body "12345"
gh secret set DEV_IBM_MQ_CHANNEL --body "DEV.APP.SVRCONN"
gh secret set DEV_IBM_MQ_PASSWORD --body "passw0rd"
gh secret set DEV_MDMAE_URL --body "https://mdmae-dev.example.com/api"

# Secrets Prod
gh secret set PROD_IBM_MQ_HOST --body "ibm-mq-prod.example.com"
gh secret set PROD_IBM_MQ_PORT --body "1414"
gh secret set PROD_IBM_MQ_CHANNEL --body "PROD.APP.SVRCONN"
gh secret set PROD_IBM_MQ_PASSWORD --body "SecureP@ssw0rd!"
gh secret set PROD_MDMAE_URL --body "https://mdmae.example.com/api"
gh secret set PROD_ALARM_EMAIL --body "team-mcp@example.com"
```

---

## Checklist complète des secrets

Copiez cette checklist et cochez au fur et à mesure:

### Secrets AWS (communs)
- [ ] `AWS_ACCESS_KEY_ID`
- [ ] `AWS_SECRET_ACCESS_KEY`
- [ ] `AWS_REGION`

### Secrets Dev
- [ ] `DEV_IBM_MQ_HOST`
- [ ] `DEV_IBM_MQ_PORT`
- [ ] `DEV_IBM_MQ_CHANNEL`
- [ ] `DEV_IBM_MQ_PASSWORD`
- [ ] `DEV_MDMAE_URL`

### Secrets Prod
- [ ] `PROD_IBM_MQ_HOST`
- [ ] `PROD_IBM_MQ_PORT`
- [ ] `PROD_IBM_MQ_CHANNEL`
- [ ] `PROD_IBM_MQ_PASSWORD`
- [ ] `PROD_MDMAE_URL`
- [ ] `PROD_ALARM_EMAIL`

**Total**: 14 secrets à configurer

---

## Déploiement via GitHub Actions

### 1. Créer le backend Terraform (première fois uniquement)

Avant de déployer, créez les buckets S3 pour le state Terraform:

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure

# Dev
./scripts/create-backend.sh dev ca-central-1

# Prod
./scripts/create-backend.sh prod ca-central-1
```

### 2. Builder les Lambda packages

```bash
./scripts/build-lambda-packages.sh
```

Puis commitez les JARs:

```bash
git add modules/lambda/functions/*/function.jar
git commit -m "Add Lambda JAR packages"
git push
```

### 3. Déclencher le workflow manuellement

1. **Ouvrir GitHub Actions**
   - Allez sur `https://github.com/VOTRE_ORG/mcp-infrastructure/actions`

2. **Sélectionner le workflow**
   - Cliquez sur **Terraform Deploy** dans la liste de gauche

3. **Lancer le workflow**
   - Cliquez **Run workflow** (bouton à droite)
   - Sélectionnez la **branch** (ex: `main`)
   - Sélectionnez **environment**: `dev` ou `prod`
   - Sélectionnez **action**: `plan` (pour commencer)
   - Cliquez **Run workflow**

4. **Vérifier le plan**
   - Attendez que le workflow se termine
   - Cliquez sur le run pour voir les détails
   - Téléchargez l'artifact **terraform-plan** pour voir les changements

5. **Appliquer les changements**
   - Si le plan est correct, relancez avec **action**: `apply`

### 4. Ordre de déploiement recommandé

**Première fois:**
1. `dev` + `plan` → Vérifier le plan
2. `dev` + `apply` → Déployer dev
3. Tester l'API dev
4. `prod` + `plan` → Vérifier le plan prod
5. `prod` + `apply` → Déployer prod

**Mises à jour:**
1. Toujours commencer par `plan` sur dev
2. Puis `apply` sur dev
3. Tester
4. Ensuite `plan` et `apply` sur prod

---

## Vérification

### 1. Vérifier que les secrets sont configurés

```bash
gh secret list
```

Vous devriez voir tous les secrets listés (sans leur valeur).

### 2. Vérifier le workflow

Dans l'onglet **Actions**, vous devriez voir:
- ✅ Workflow terminé avec succès
- 📦 Artifact **terraform-plan** disponible
- 📦 Artifact **terraform-outputs** disponible (après apply)

### 3. Vérifier les ressources AWS

Après un `apply` réussi:

```bash
# Lister les Lambda functions
aws lambda list-functions --region ca-central-1 | grep dev-mcp

# Vérifier la table DynamoDB
aws dynamodb list-tables --region ca-central-1 | grep dev-mcp

# Vérifier l'API Gateway
aws apigateway get-rest-apis --region ca-central-1 | grep dev-mcp
```

### 4. Tester l'API

```bash
# Récupérer l'URL de l'API depuis les outputs
API_URL=$(terraform output -raw api_gateway_url)

# Tester l'endpoint
curl -X PUT "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{"newName": "Jean Dupont"}'
```

---

## Troubleshooting

### Erreur: "Secret not found"

**Cause**: Le secret n'est pas configuré ou mal nommé.

**Solution**: Vérifiez le nom exact du secret (sensible à la casse).

### Erreur: "Invalid AWS credentials"

**Cause**: Les credentials AWS sont incorrects ou expirés.

**Solution**:
1. Vérifiez que `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY` sont corrects
2. Vérifiez que l'utilisateur IAM a les permissions nécessaires
3. Régénérez les credentials si nécessaire

### Erreur: "Backend initialization required"

**Cause**: Le bucket S3 n'existe pas.

**Solution**: Exécutez `./scripts/create-backend.sh` avant de déployer.

### Erreur: "Unable to connect to IBM MQ"

**Cause**: Lambda ne peut pas atteindre IBM MQ.

**Solution (Dev)**:
1. Vérifiez que ngrok est démarré: `ngrok tcp 1414`
2. Mettez à jour `DEV_IBM_MQ_HOST` et `DEV_IBM_MQ_PORT` avec la nouvelle URL ngrok
3. Redéployez avec `apply`

**Solution (Prod)**:
1. Vérifiez les security groups
2. Vérifiez que le serveur IBM MQ est accessible depuis AWS

---

## Sécurité

### Bonnes pratiques

1. **Ne jamais commiter les secrets dans Git**
   - Utilisez `.gitignore` pour exclure `*.tfvars` (sauf `.example`)
   - Les secrets doivent uniquement être dans GitHub Secrets

2. **Rotation régulière des credentials**
   - AWS Access Keys: tous les 90 jours
   - IBM MQ passwords: tous les 180 jours

3. **Principe du moindre privilège**
   - L'utilisateur AWS doit avoir uniquement les permissions nécessaires
   - Pas d'admin permanent

4. **Séparation dev/prod**
   - Utilisez des credentials AWS différents pour dev et prod (idéalement)
   - Utilisez des comptes AWS séparés si possible

5. **Monitoring**
   - Activez CloudTrail pour auditer l'utilisation des credentials
   - Configurez des alertes sur les accès inhabituels

---

## Support

Si vous rencontrez des problèmes:

1. Vérifiez les logs du workflow GitHub Actions
2. Consultez les logs CloudWatch des Lambdas
3. Vérifiez le fichier `STATUS.md` pour l'état du projet
4. Consultez le `README.md` pour plus de détails

---

**Dernière mise à jour**: 2026-09-23
**Auteur**: Claude Code