# Bootstrap Terraform

Ce module crée les ressources AWS nécessaires pour stocker l'état Terraform et les artifacts Lambda.

## 🎯 Objectif

Créer l'infrastructure de base **avant** de déployer l'infrastructure principale :
- Buckets S3 pour stocker le state Terraform (dev & prod)
- Tables DynamoDB pour le state locking
- Bucket S3 pour les JARs Lambda
- Rôle IAM pour GitHub Actions (OIDC)

## 📋 Prérequis

1. AWS CLI installé et configuré
2. Terraform >= 1.9.0 installé
3. Credentials AWS avec permissions AdministratorAccess

## 🚀 Déploiement

### Étape 1 : Configurer AWS CLI

```bash
aws configure
# Entrer vos Access Key ID et Secret Access Key
```

### Étape 2 : Modifier terraform.tfvars

```bash
# Modifier le fichier terraform.tfvars
# IMPORTANT: Mettre à jour github_repo avec votre organisation/repo
```

### Étape 3 : Déployer

```bash
cd bootstrap

# Initialiser Terraform
terraform init

# Planifier
terraform plan

# Appliquer (créer les ressources)
terraform apply
```

### Étape 4 : Vérifier les ressources

```bash
# Lister les buckets S3 créés
aws s3 ls | grep mcp

# Vérifier les tables DynamoDB
aws dynamodb list-tables | grep terraform-lock
```

## 📊 Ressources créées

| Ressource | Nom | Environnement |
|-----------|-----|---------------|
| S3 Bucket | `mcp-terraform-state-dev` | DEV |
| S3 Bucket | `mcp-terraform-state-prod` | PROD |
| S3 Bucket | `bnc-mcp-lambda-artifacts` | SHARED |
| DynamoDB Table | `mcp-terraform-lock-dev` | DEV |
| DynamoDB Table | `mcp-terraform-lock-prod` | PROD |
| IAM Role | `mcp-github-actions-role` | SHARED |
| OIDC Provider | GitHub Actions | SHARED |

## ⚠️ Important

- Le state du bootstrap est stocké **localement** dans `terraform.tfstate`
- **Commitez ce fichier** dans Git (exception au .gitignore)
- Ce bootstrap doit être déployé **UNE SEULE FOIS**
- Pour détruire : `terraform destroy` (⚠️ Supprime tout!)

## 🔄 Après le bootstrap

1. Les backends S3 sont déjà configurés dans `environments/*/backend.tf`
2. Modifiez `.github/workflows/terraform-deploy.yml` pour utiliser le rôle OIDC
3. Déployez l'infrastructure principale :
   ```bash
   cd ../environments/dev
   terraform init
   terraform apply
   ```

## 📝 Notes

- Le bootstrap utilise un backend local (pas de S3) car les buckets n'existent pas encore
- C'est le problème "chicken and egg" classique de Terraform
- Une fois déployé, ne pas modifier sauf nécessité absolue