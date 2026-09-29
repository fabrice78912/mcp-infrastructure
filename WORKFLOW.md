# Workflow Infrastructure as Code

Guide complet pour ajouter et déployer de nouvelles ressources Terraform.

---

## 1️⃣ Développement Local

```bash
# 1. Créer une nouvelle branche
cd /Users/fabricefoko/Documents/mcp-infrastructure
git checkout -b feature/add-new-resource

# 2. Ajouter votre ressource Terraform
# Par exemple, ajouter une nouvelle table DynamoDB:
# Éditer: environments/dev/main.tf
```

**Exemple d'ajout:**

```hcl
# Nouvelle table DynamoDB pour les audits
module "dynamodb_audit" {
  source = "../../modules/dynamodb"

  environment                    = var.environment
  project_name                   = var.project_name
  table_name                     = "AuditLog"
  enable_point_in_time_recovery  = var.enable_dynamodb_backup
  enable_encryption              = true
}
```

---

## 2️⃣ Validation et Test Locaux

```bash
# 1. Se placer dans l'environnement dev
cd environments/dev

# 2. Initialiser Terraform (si nouveaux modules)
terraform init

# 3. Formater le code
terraform fmt -recursive

# 4. Valider la syntaxe
terraform validate

# 5. Créer un plan pour voir les changements
terraform plan \
  -var="ibm_mq_host=$IBM_MQ_HOST" \
  -var="ibm_mq_port=$IBM_MQ_PORT" \
  -var="ibm_mq_channel=$IBM_MQ_CHANNEL" \
  -var="ibm_mq_password=$IBM_MQ_PASSWORD" \
  -var="mdmae_url=$MDMAE_URL" \
  -out=tfplan

# 6. Examiner le plan détaillé
terraform show tfplan
```

---

## 3️⃣ Commit et Push

```bash
# 1. Retourner à la racine du projet
cd /Users/fabricefoko/Documents/mcp-infrastructure

# 2. Vérifier les changements
git status
git diff

# 3. Ajouter les fichiers modifiés
git add environments/dev/main.tf

# 4. Commit avec un message descriptif
git commit -m "Add DynamoDB AuditLog table for tracking changes

- Created new DynamoDB table module for audit logs
- Configured with encryption and point-in-time recovery
- Will be used to track all client profile changes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

# 5. Push vers GitHub
git push origin feature/add-new-resource
```

---

## 4️⃣ Créer une Pull Request (Optionnel mais recommandé)

### Option A - Via GitHub CLI

```bash
gh pr create \
  --title "Add DynamoDB AuditLog table" \
  --body "## Summary
- Adds new DynamoDB table for audit logging
- Configured with encryption and backups

## Test Plan
- [x] Terraform validate passed
- [x] Terraform plan reviewed
- [ ] Deploy to dev and verify table creation

## Changes
- Created \`module.dynamodb_audit\` in environments/dev/main.tf" \
  --base main \
  --head feature/add-new-resource
```

### Option B - Merger directement dans main

```bash
git checkout main
git merge feature/add-new-resource
git push origin main
```

---

## 5️⃣ Déploiement via GitHub Actions

### Option A - Automatique (si push direct sur main)

Le workflow se déclenche automatiquement après le push.

### Option B - Manuel (recommandé pour plus de contrôle)

```bash
# D'abord faire un PLAN pour vérifier
gh workflow run terraform-deploy.yml \
  --repo fabrice78912/mcp-infrastructure \
  --ref main \
  -f environment=dev \
  -f action=plan

# Attendre et vérifier le plan
gh run watch

# Si le plan est bon, faire l'APPLY
gh workflow run terraform-deploy.yml \
  --repo fabrice78912/mcp-infrastructure \
  --ref main \
  -f environment=dev \
  -f action=apply

# Suivre le déploiement en temps réel
gh run watch
```

---

## 6️⃣ Vérification Post-Déploiement

```bash
# 1. Vérifier que la ressource a été créée
aws dynamodb describe-table \
  --table-name dev-AuditLog \
  --region ca-central-1

# 2. Vérifier les logs CloudWatch du workflow
gh run view --log

# 3. Télécharger les outputs Terraform
gh run download <run-id> --name terraform-outputs-dev-<run-number>

# 4. Vérifier le state Terraform distant
cd environments/dev
terraform refresh
terraform show
```

---

## 7️⃣ Nettoyage (Optionnel)

```bash
# Supprimer la branche feature après merge
git branch -d feature/add-new-resource
git push origin --delete feature/add-new-resource
```

---

## 🎯 Workflow Résumé

```
┌─────────────────┐
│  Local Dev      │
│  - Éditer .tf   │
│  - Validate     │
│  - Plan         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Git Commit     │
│  - Add          │
│  - Commit       │
│  - Push         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  GitHub         │
│  - PR (opt.)    │
│  - Merge main   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  GitHub Actions │
│  - Plan (opt.)  │
│  - Apply        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AWS Deploy     │
│  - Create       │
│  - Verify       │
└─────────────────┘
```

---

## 💡 Bonnes Pratiques

1. **Toujours faire un `plan` avant `apply`**
2. **Utiliser des branches feature** pour les changements importants
3. **Faire des commits atomiques** (1 changement = 1 commit)
4. **Tester localement** avant de push
5. **Documenter** les changements dans le message de commit
6. **Vérifier les outputs** du workflow GitHub Actions
7. **Garder le state synchronisé** (ne jamais modifier manuellement dans AWS)

---

## 🔧 Commandes Utiles

```bash
# Voir l'état actuel de l'infrastructure
terraform state list

# Voir les détails d'une ressource
terraform state show module.dynamodb_audit.aws_dynamodb_table.client_profile

# Rafraîchir le state depuis AWS
terraform refresh

# Voir les outputs
terraform output

# Importer une ressource existante
terraform import module.dynamodb_audit.aws_dynamodb_table.client_profile dev-AuditLog
```

---

## 📋 Checklist Avant Push

- [ ] `terraform fmt -recursive` - Code formaté
- [ ] `terraform validate` - Syntaxe correcte
- [ ] `terraform plan` - Plan vérifié
- [ ] `git diff` - Changements revus
- [ ] Pas de secrets committés - .gitignore respecté
- [ ] Message commit descriptif - Documentation claire

---

## 🛡️ Sécurité

- ✅ Utiliser `.env.local` pour les secrets (git-ignored)
- ✅ Ne jamais commit les fichiers `.tfplan`
- ✅ Ne jamais commit les fichiers `.tfvars` avec secrets
- ⚠️ Prudence avec `terraform apply` en local (préférer GitHub Actions)
- ❌ Jamais modifier le state S3 manuellement

---

## 📞 Support

En cas de problème:
1. Vérifier les logs GitHub Actions
2. Consulter la documentation Terraform
3. Vérifier le state avec `terraform show`
4. Contacter l'équipe DevOps