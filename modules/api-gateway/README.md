# API Gateway Module

Module Terraform pour configurer API Gateway avec Swagger UI.

## Déploiement

Le package Lambda pour Swagger UI est **généré automatiquement** par Terraform lors de l'exécution de `terraform plan/apply`.

```bash
cd environments/dev
terraform plan
terraform apply
```

Aucune étape de build manuelle n'est requise ! 🚀

## Fichiers

- `swagger-ui-lambda/index.py` - Code source de la Lambda Swagger UI
- `swagger-ui-lambda.zip` - Package de déploiement (généré automatiquement par Terraform, non versionné dans Git)
- `swagger.tf` - Configuration Terraform pour Swagger UI avec `data "archive_file"`
- `build-swagger-ui-lambda.sh` - Script de build legacy (non requis, conservé pour référence)

## Comment ça fonctionne

Terraform utilise la ressource `data "archive_file"` pour générer automatiquement le ZIP à partir du répertoire `swagger-ui-lambda/` lors de chaque exécution.

Cela fonctionne à la fois :
- ✅ En local
- ✅ Dans GitHub Actions
- ✅ Dans n'importe quel environnement CI/CD

Le fichier `swagger-ui-lambda.zip` n'a pas besoin d'être versionné dans Git.
