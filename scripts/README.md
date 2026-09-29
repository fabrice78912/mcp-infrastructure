# Scripts MCP Infrastructure

Ce répertoire contient des scripts utilitaires pour faciliter la gestion de l'infrastructure MCP.

## 📜 Scripts Disponibles

### 1. `post-deploy-setup.sh`

**Description**: Configure automatiquement l'environnement après un déploiement Terraform.

**Usage**:
```bash
./post-deploy-setup.sh [dev|prod]
```

**Ce qu'il fait**:
- ✅ Vérifie la présence des JARs Lambda dans S3
- ✅ Configure les secrets AWS Secrets Manager (interactif)
- ✅ Charge les données de test dans DynamoDB
- ✅ Récupère l'URL de l'API Gateway
- ✅ Teste automatiquement l'endpoint

**Quand l'utiliser**:
- Après un nouveau déploiement (`terraform apply`)
- Après un destroy/recreate complet
- Pour reconfigurer les secrets
- Pour réinitialiser les données de test

**Exemple**:
```bash
# Configuration complète de l'environnement DEV
./post-deploy-setup.sh dev

# Le script vous demandera:
# - Credentials IBM MQ (host, port, channel, etc.)
# - Credentials MDMAE (URL, API key)
# - Confirmations pour chaque étape
```

---

### 2. `upload-lambda-jars.sh`

**Description**: Upload tous les JARs Lambda vers S3 en une seule commande.

**Usage**:
```bash
# Détection automatique du répertoire
./upload-lambda-jars.sh

# Ou spécifier le chemin
./upload-lambda-jars.sh /chemin/vers/mcp-orchestration/target
```

**Ce qu'il fait**:
- ✅ Recherche tous les JARs Lambda dans le répertoire de build
- ✅ Vérifie la connexion AWS
- ✅ Upload vers `s3://bnc-mcp-lambda-artifacts/`
- ✅ Affiche un résumé avec les tailles de fichiers

**Quand l'utiliser**:
- Avant un nouveau déploiement Terraform
- Après avoir rebuild les Lambda functions Java
- Avant un destroy/recreate

**JARs uploadés**:
- `ValidationLambda.jar`
- `MatchingLambda.jar`
- `UpdateProfileLambda.jar`
- `PublishEventLambda.jar`
- `HumanReviewLambda.jar`
- `FccSenderLambda.jar`
- `FccResponseProcessorLambda.jar`

**Exemple**:
```bash
# Après un build Maven
cd ~/Documents/mcp-local/mcp-orchestration
mvn clean package -DskipTests

# Upload automatique
cd /path/to/mcp-infrastructure
./scripts/upload-lambda-jars.sh
```

---

## 🔄 Workflows Typiques

### Workflow 1: Premier Déploiement

```bash
# 1. Builder les JARs Java
cd ~/Documents/mcp-local/mcp-orchestration
mvn clean package -DskipTests

# 2. Uploader vers S3
cd /path/to/mcp-infrastructure
./scripts/upload-lambda-jars.sh

# 3. Déployer via Terraform
cd environments/dev
terraform init
terraform apply -var-file=dev.tfvars

# 4. Configuration post-déploiement
cd ../..
./scripts/post-deploy-setup.sh dev
```

### Workflow 2: Destroy & Recreate Complet

```bash
# 1. Vérifier que les JARs sont dans S3
./scripts/upload-lambda-jars.sh

# 2. Destroy via GitHub Actions
# → Actions → Deploy MCP Infrastructure
# → Environment: dev, Action: destroy

# 3. Apply via GitHub Actions
# → Actions → Deploy MCP Infrastructure
# → Environment: dev, Action: apply

# 4. Configuration
./scripts/post-deploy-setup.sh dev
```

### Workflow 3: Mise à Jour des Lambda Functions

```bash
# 1. Modifier le code Java
cd ~/Documents/mcp-local/mcp-orchestration/src/main/java/...
# ... faire vos modifications ...

# 2. Rebuild
cd ~/Documents/mcp-local/mcp-orchestration
mvn clean package -DskipTests

# 3. Upload des nouveaux JARs
cd /path/to/mcp-infrastructure
./scripts/upload-lambda-jars.sh

# 4. Re-déployer les Lambda functions
cd environments/dev
terraform apply -target=module.lambda -auto-approve

# Pas besoin de post-deploy-setup si seulement les Lambda changent
```

### Workflow 4: Reconfiguration des Secrets

```bash
# Si vous devez changer les credentials IBM MQ ou MDMAE
./scripts/post-deploy-setup.sh dev

# Le script vous demandera les nouvelles valeurs
```

---

## 🛠️ Prérequis

Avant d'utiliser ces scripts, assurez-vous d'avoir:

### AWS CLI Configuré

```bash
# Vérifier
aws sts get-caller-identity

# Devrait afficher vos credentials AWS
```

### Terraform Installé

```bash
# Vérifier
terraform version

# Version requise: >= 1.9.0
```

### jq Installé (pour post-deploy-setup.sh)

```bash
# macOS
brew install jq

# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RedHat/CentOS
```

### Accès S3

```bash
# Vérifier l'accès au bucket
aws s3 ls s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
```

---

## ⚙️ Variables d'Environnement

Les scripts utilisent ces valeurs par défaut:

```bash
REGION="ca-central-1"
S3_BUCKET="bnc-mcp-lambda-artifacts"
```

Pour modifier, éditez directement les scripts ou exportez les variables:

```bash
export AWS_REGION="us-east-1"
export S3_BUCKET="mon-autre-bucket"
./scripts/upload-lambda-jars.sh
```

---

## 🐛 Troubleshooting

### "AWS credentials not found"

**Solution**:
```bash
# Configurer AWS CLI
aws configure

# Ou utiliser des variables d'environnement
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="ca-central-1"
```

### "Bucket does not exist"

**Solution**:
```bash
# Créer le bucket (une seule fois)
aws s3 mb s3://bnc-mcp-lambda-artifacts --region ca-central-1
```

### "JARs not found"

**Solution**:
```bash
# Spécifier le chemin explicitement
./scripts/upload-lambda-jars.sh /chemin/complet/vers/target

# Ou vérifier que le build Maven a réussi
cd ~/Documents/mcp-local/mcp-orchestration
mvn clean package -DskipTests
ls -lh target/*.jar
```

### "terraform output failed"

**Solution**:
```bash
# S'assurer d'être dans le bon répertoire
cd environments/dev

# Réinitialiser Terraform si nécessaire
terraform init
terraform refresh
```

---

## 📝 Logs et Debugging

Les scripts affichent des messages colorés:
- 🟢 **Vert**: Succès
- 🔴 **Rouge**: Erreur
- 🟡 **Jaune**: Avertissement
- 🔵 **Bleu**: Information

Pour plus de détails, vous pouvez activer le mode debug:

```bash
# Afficher toutes les commandes exécutées
bash -x ./scripts/post-deploy-setup.sh dev

# Ou modifier temporairement le script
# Ajouter: set -x en haut du script
```

---

## 🔐 Sécurité

### Secrets

Les scripts **NE STOCKENT PAS** les secrets dans des fichiers. Ils utilisent:
- Saisie interactive (avec masquage du mot de passe)
- AWS Secrets Manager pour le stockage sécurisé

### Bonnes Pratiques

- ✅ Ne jamais commiter les secrets dans Git
- ✅ Utiliser AWS Secrets Manager ou AWS Systems Manager Parameter Store
- ✅ Limiter les permissions IAM au strict nécessaire
- ✅ Utiliser des secrets différents pour dev/prod

---

## 📞 Support

Pour des questions ou problèmes:

1. Consulter le [Guide de Destroy/Recreate](../docs/DESTROY-RECREATE-GUIDE.md)
2. Vérifier les logs CloudWatch
3. Contacter l'équipe DevOps

---

**Dernière mise à jour**: 2026-09-29