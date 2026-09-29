# Guide de Test Local Terraform

Guide complet pour tester vos modifications Terraform en local avant de les déployer.

---

## 🧪 Configuration Initiale

### 1. Vérifier les Credentials AWS

```bash
# Vérifier que les credentials fonctionnent
aws sts get-caller-identity

# Devrait afficher:
# {
#     "UserId": "AIDAST33T3L76JYUCJEOX",
#     "Account": "180111006463",
#     "Arn": "arn:aws:iam::180111006463:user/github-actions-terraform"
# }
```

### 2. Configurer les Variables d'Environnement

Créez un fichier `.env.local` pour vos secrets:

```bash
cat > /Users/fabricefoko/Documents/mcp-infrastructure/.env.local <<'EOF'
# IBM MQ Credentials
export IBM_MQ_HOST="your-mq-host.example.com"
export IBM_MQ_PORT="1414"
export IBM_MQ_CHANNEL="DEV.CHANNEL"
export IBM_MQ_PASSWORD="your-password-here"

# MDMAE API
export MDMAE_URL="https://mdmae-api-dev.example.com"
EOF

# Charger les variables
source .env.local
```

⚠️ **Note:** Le fichier `.env.local` est déjà dans `.gitignore` et ne sera jamais commité.

---

## 🔍 Étapes de Test

### 1. Initialiser Terraform

```bash
# Se placer dans l'environnement dev
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev

# Initialiser (télécharge providers et modules)
terraform init
```

### 2. Formater le Code

```bash
# Formater automatiquement tous les fichiers .tf
terraform fmt -recursive

# Vérifier le formatage sans modifier
terraform fmt -check -recursive
```

### 3. Valider la Syntaxe

```bash
# Valider la configuration (sans toucher AWS)
terraform validate

# Si succès:
# Success! The configuration is valid.
```

### 4. Créer un Plan de Déploiement

```bash
# Créer un plan SANS appliquer
terraform plan \
  -var="ibm_mq_host=$IBM_MQ_HOST" \
  -var="ibm_mq_port=$IBM_MQ_PORT" \
  -var="ibm_mq_channel=$IBM_MQ_CHANNEL" \
  -var="ibm_mq_password=$IBM_MQ_PASSWORD" \
  -var="mdmae_url=$MDMAE_URL" \
  -out=tfplan.local

# Ceci va:
# ✅ Lire le state depuis S3
# ✅ Comparer avec votre code local
# ✅ Montrer ce qui sera créé/modifié/détruit
# ❌ Ne modifie RIEN dans AWS
```

### 5. Analyser le Plan

```bash
# Voir le plan en détail
terraform show tfplan.local

# Voir juste le résumé
terraform show -json tfplan.local | jq '.resource_changes[] | {address, change: .change.actions}'

# Compter les changements
terraform show -json tfplan.local | jq '[.resource_changes[].change.actions] | flatten | group_by(.) | map({(.[0]): length}) | add'
```

---

## 🧪 Tests Avancés

### Test avec Console Interactive

```bash
# Ouvrir une console Terraform
terraform console

# Tester des expressions:
> module.dynamodb.table_name
"dev-ClientProfile"

> module.lambda.function_arns
{
  "client_profile_reader" = "arn:aws:lambda:..."
}

# Ctrl+D pour quitter
```

### Test avec Workspace Temporaire

```bash
# Créer un workspace de test (OPTION AVANCÉE)
terraform workspace new test-local

# Faire vos tests
terraform plan -out=tfplan.test

# Revenir au workspace principal
terraform workspace select default

# Supprimer le workspace de test
terraform workspace delete test-local
```

---

## 🚀 Script de Test Automatisé

Créez un script pour automatiser les tests:

```bash
cat > /Users/fabricefoko/Documents/mcp-infrastructure/test-local.sh <<'EOF'
#!/bin/bash
set -e

echo "🧪 Testing Terraform configuration locally..."

# Charger les variables d'environnement
if [ -f .env.local ]; then
    source .env.local
    echo "✅ Loaded environment variables"
else
    echo "❌ .env.local not found. Create it first!"
    exit 1
fi

# Se placer dans dev
cd environments/dev

# Formater
echo "📝 Formatting code..."
terraform fmt -recursive

# Valider
echo "✔️  Validating configuration..."
terraform validate

# Plan
echo "📊 Creating plan..."
terraform plan \
  -var="ibm_mq_host=$IBM_MQ_HOST" \
  -var="ibm_mq_port=$IBM_MQ_PORT" \
  -var="ibm_mq_channel=$IBM_MQ_CHANNEL" \
  -var="ibm_mq_password=$IBM_MQ_PASSWORD" \
  -var="mdmae_url=$MDMAE_URL" \
  -out=tfplan.local

echo ""
echo "✅ Tests passed! Review the plan above."
echo "💡 To apply locally: terraform apply tfplan.local"
echo "⚠️  WARNING: This will modify the same state as GitHub Actions!"
EOF

chmod +x test-local.sh
```

**Utilisation:**

```bash
./test-local.sh
```

---

## 🔍 Commandes de Diagnostic

```bash
# Voir le state actuel
terraform state list

# Comparer le state avec AWS
terraform refresh

# Voir les outputs actuels
terraform output

# Vérifier les providers installés
terraform providers

# Voir la configuration détaillée
terraform show

# Valider avec logs détaillés
TF_LOG=INFO terraform validate

# Plan avec debug
TF_LOG=DEBUG terraform plan
```

---

## ⚠️ Appliquer en Local (Prudence!)

```bash
# ATTENTION: Ceci modifiera le state S3 partagé avec GitHub Actions!
terraform apply tfplan.local

# Alternative plus sûre: Utiliser GitHub Actions
gh workflow run terraform-deploy.yml \
  --ref main \
  -f environment=dev \
  -f action=apply
```

---

## 📋 Checklist de Test

Avant de push votre code:

- [ ] ✅ `terraform fmt -recursive` exécuté
- [ ] ✅ `terraform validate` passé avec succès
- [ ] ✅ `terraform plan` créé et analysé
- [ ] ✅ Pas de changements inattendus dans le plan
- [ ] ✅ Pas de destructions accidentelles
- [ ] ✅ Variables d'environnement chargées
- [ ] ✅ `.env.local` n'est pas commité
- [ ] ✅ Pas de fichiers `.tfplan` commitées
- [ ] ✅ `git diff` vérifié

---

## 🎯 Exemple Complet

Workflow typique pour ajouter une Lambda:

```bash
# 1. Créer une branche
git checkout -b feature/add-notification-lambda

# 2. Charger les secrets
source .env.local

# 3. Modifier le code
code environments/dev/main.tf

# 4. Tester
cd environments/dev
terraform init
terraform fmt -recursive
terraform validate

# 5. Créer un plan
terraform plan \
  -var="ibm_mq_host=$IBM_MQ_HOST" \
  -var="ibm_mq_port=$IBM_MQ_PORT" \
  -var="ibm_mq_channel=$IBM_MQ_CHANNEL" \
  -var="ibm_mq_password=$IBM_MQ_PASSWORD" \
  -var="mdmae_url=$MDMAE_URL"

# 6. Vérifier le plan
# Doit montrer: Plan: 1 to add, 0 to change, 0 to destroy

# 7. Si OK, commit et push
cd ../..
git add environments/dev/main.tf
git commit -m "Add notification sender Lambda"
git push origin feature/add-notification-lambda

# 8. Déployer via GitHub Actions
gh workflow run terraform-deploy.yml \
  --ref feature/add-notification-lambda \
  -f environment=dev \
  -f action=apply
```

---

## 🛡️ Bonnes Pratiques

### ✅ À FAIRE:
- Toujours `terraform validate` avant de commit
- Toujours `terraform plan` pour voir les changements
- Toujours charger les variables d'environnement
- Vérifier le plan pour éviter les surprises
- Utiliser `.env.local` pour les secrets

### ❌ À ÉVITER:
- Jamais commit les fichiers `.tfplan`
- Jamais commit les fichiers `.tfvars` avec secrets
- Prudence avec `terraform apply` en local
- Jamais modifier le state S3 manuellement
- Attention aux workspaces si vous testez en local

---

## 🐛 Dépannage

### Erreur: Backend initialization required

```bash
terraform init -reconfigure
```

### Erreur: State lock

```bash
# Forcer le déverrouillage (ATTENTION!)
terraform force-unlock <LOCK_ID>
```

### Erreur: Variables not set

```bash
# Vérifier que .env.local est chargé
echo $IBM_MQ_HOST

# Recharger si nécessaire
source .env.local
```

### Plan montre des changements inattendus

```bash
# Rafraîchir le state
terraform refresh

# Voir les différences
terraform show
```

---

## 📞 Support

En cas de problème:
1. Vérifier les logs avec `TF_LOG=DEBUG`
2. Consulter la documentation Terraform
3. Vérifier le state avec `terraform show`
4. Comparer avec GitHub Actions logs