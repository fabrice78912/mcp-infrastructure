# API Gateway Module

Module Terraform pour configurer API Gateway avec Swagger UI.

## Prérequis

Avant de déployer ce module avec Terraform, vous devez générer le package de déploiement Lambda pour Swagger UI:

```bash
cd modules/api-gateway
./build-swagger-ui-lambda.sh
```

Ce script créera le fichier `swagger-ui-lambda.zip` requis par Terraform.

## Déploiement

Une fois le package Lambda généré:

```bash
cd environments/dev
terraform plan
terraform apply
```

## Fichiers

- `swagger-ui-lambda/index.py` - Code source de la Lambda Swagger UI
- `build-swagger-ui-lambda.sh` - Script de build pour créer le ZIP
- `swagger-ui-lambda.zip` - Package de déploiement (généré, non versionné dans Git)
- `swagger.tf` - Configuration Terraform pour Swagger UI

## Notes

Le fichier `swagger-ui-lambda.zip` n'est pas versionné dans Git (ajouté à `.gitignore`). Vous devez exécuter le script de build avant chaque déploiement Terraform.
