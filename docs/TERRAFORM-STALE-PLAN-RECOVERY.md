# Récupération d'un Plan Terraform Obsolète

## 📋 Contexte

Ce guide explique comment gérer l'erreur `Saved plan is stale` et refaire un plan Terraform à jour lorsque l'infrastructure a été modifiée entre la création du plan et son application.

---

## 🎯 Problème : Plan Obsolète

Lorsque vous essayez d'appliquer un plan sauvegardé et que quelqu'un (ou quelque chose) a modifié l'infrastructure AWS entre temps, Terraform détecte l'incohérence et refuse d'appliquer le plan.

### Erreur typique :

```bash
terraform apply tfplan

╷
│ Error: Saved plan is stale
│
│ The given plan file can no longer be applied because the state was changed
│ by another operation after the plan was created.
╵
```

---

## 🔄 Solution : Workflow de Récupération

### Étape 1️⃣ : Navigation vers le répertoire

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev
```

---

### Étape 2️⃣ : Tentative d'application (échoue)

```bash
terraform apply tfplan
```

**Résultat attendu :**
```
❌ Error: Saved plan is stale
```

**Explication :** Terraform détecte que l'état actuel de l'infrastructure ne correspond plus à l'état enregistré dans le plan sauvegardé.

---

### Étape 3️⃣ : Synchronisation avec AWS

```bash
terraform refresh
```

**Ce que cette commande fait :**
- Lit l'état **actuel** de toutes les ressources sur AWS
- Met à jour le fichier d'état local (`terraform.tfstate`)
- **Ne modifie rien** sur AWS (lecture seule)

**Résultat attendu :**
```
module.lambda.aws_lambda_function.functions["human_review_handler"]: Refreshing...
module.lambda.aws_lambda_function.functions["name_validator"]: Refreshing...
...

✅ État mis à jour (memory_size = 1024)
```

---

### Étape 4️⃣ : Vérification des changements

```bash
terraform plan
```

**Ce que cette commande fait :**
- Compare votre **code Terraform** avec l'**état actuel** (fraîchement synchronisé)
- Affiche les différences et les changements prévus

**Résultat attendu :**
```
Terraform will perform the following actions:

  ~ module.lambda.aws_lambda_function.functions["human_review_handler"]
      environment.variables = {
        - "FRAUD_REVIEW_QUEUE_URL"     = "https://sqs..."
        + "MCP_FRAUD_REVIEW_QUEUE_URL" = "https://sqs..."
      }
      # memory_size = 1024 (inchangé ✅)

Plan: 0 to add, 1 to change, 0 to destroy.
```

**✅ Vérifiez que :**
- Vos changements sont présents
- Les modifications des autres sont préservées

---

### Étape 5️⃣ : Création d'un nouveau plan

```bash
terraform plan -out=tfplan-update
```

**Ce que cette commande fait :**
- Crée un **nouveau plan** basé sur l'état actuel
- Sauvegarde ce plan dans le fichier `tfplan-update`

**Résultat attendu :**
```
Plan: 0 to add, 1 to change, 0 to destroy.

Saved the plan to: tfplan-update
```

---

### Étape 6️⃣ : Application du nouveau plan

```bash
terraform apply tfplan-update
```

**Ce que cette commande fait :**
- Applique **exactement** le plan sauvegardé
- Modifie l'infrastructure AWS selon le plan

**Résultat attendu :**
```
module.lambda.aws_lambda_function.functions["human_review_handler"]: Modifying...
module.lambda.aws_lambda_function.functions["human_review_handler"]: Modifications complete

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

✅ Success!
```

---

## 📝 Résumé des Commandes

```bash
# Étape 1 : Navigation
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev

# Étape 2 : Tentative (échoue)
terraform apply tfplan
# ❌ Error: Saved plan is stale

# Étape 3 : Synchronisation
terraform refresh
# ✅ État mis à jour

# Étape 4 : Vérification
terraform plan
# ✅ Voir les changements

# Étape 5 : Nouveau plan
terraform plan -out=tfplan-update
# ✅ Plan sauvegardé

# Étape 6 : Application
terraform apply tfplan-update
# ✅ Success!
```

---

## 🎓 Bonnes Pratiques

### ✅ À FAIRE

1. **Toujours synchroniser** avant de créer un nouveau plan
   ```bash
   terraform refresh
   ```

2. **Vérifier le plan** avant d'appliquer
   ```bash
   terraform plan
   ```

3. **Communiquer** avec l'équipe avant d'appliquer des changements importants

4. **Nommer les plans** de manière explicite
   ```bash
   terraform plan -out=tfplan-$(date +%Y%m%d-%H%M%S)
   ```

### ❌ À ÉVITER

1. **Ne pas forcer l'application** avec `-refresh=false`
   ```bash
   # ❌ DANGEREUX - Peut écraser les changements des autres
   terraform apply -refresh=false tfplan
   ```

2. **Ne pas ignorer** les erreurs de plan obsolète

3. **Ne pas appliquer** sans vérifier le plan

---

## 🔍 Diagnostic Avancé

### Voir le contenu d'un plan sauvegardé

```bash
terraform show tfplan
```

### Comparer deux plans

```bash
# Exporter les plans
terraform show tfplan > ancien-plan.txt
terraform show tfplan-update > nouveau-plan.txt

# Comparer
diff ancien-plan.txt nouveau-plan.txt
```

### Vérifier l'état actuel

```bash
terraform show
```

---

## 📂 Gestion des Plans Sauvegardés

### Lister tous les plans sauvegardés

**Note :** Terraform n'a pas de commande native pour lister les plans. Utilisez les commandes shell :

#### Lister du plus récent au plus ancien

```bash
ls -lt tfplan*
```

**Résultat :**
```
-rw-r--r--  1 user  staff  45678 Oct  9 15:30 tfplan-20261009-153000
-rw-r--r--  1 user  staff  44521 Oct  9 14:15 tfplan-20261009-141500
-rw-r--r--  1 user  staff  43892 Oct  9 10:00 tfplan-20261009-100000
-rw-r--r--  1 user  staff  42341 Oct  8 16:45 tfplan
```

#### Avec tailles lisibles

```bash
ls -lth tfplan*
```

**Résultat :**
```
-rw-r--r--  1 user  staff   45K Oct  9 15:30 tfplan-20261009-153000
-rw-r--r--  1 user  staff   44K Oct  9 14:15 tfplan-20261009-141500
-rw-r--r--  1 user  staff   43K Oct  9 10:00 tfplan-20261009-100000
```

#### Uniquement les noms

```bash
ls -t tfplan*
```

#### Compter les plans sauvegardés

```bash
ls tfplan* 2>/dev/null | wc -l
```

---

### Organisation Recommandée

#### Structure avec dossier dédié

```bash
environments/dev/
├── main.tf
├── variables.tf
├── terraform.tfvars
├── plans/                    # ✅ Dossier dédié aux plans
│   ├── tfplan-20261009-153000
│   ├── tfplan-20261009-141500
│   └── tfplan-20261009-100000
└── terraform.tfstate
```

#### Créer un plan dans le dossier `plans/`

```bash
# Créer le dossier s'il n'existe pas
mkdir -p plans

# Sauvegarder le plan dans ce dossier
terraform plan -out=plans/tfplan-$(date +%Y%m%d-%H%M%S)
```

#### Lister les plans du dossier

```bash
ls -lt plans/tfplan*
```

---

### Convention de Nommage Recommandée

#### ✅ BON - Format avec timestamp ISO 8601

```bash
# Format : tfplan-YYYYMMDD-HHMMSS
terraform plan -out=tfplan-$(date +%Y%m%d-%H%M%S)
# Résultat : tfplan-20261009-153045
```

**Avantage :** Tri alphabétique = tri chronologique

#### ✅ BON - Avec description

```bash
terraform plan -out=tfplan-$(date +%Y%m%d-%H%M%S)-fix-lambda-vars
# Résultat : tfplan-20261009-153045-fix-lambda-vars
```

#### ❌ MOINS BON - Sans timestamp

```bash
terraform plan -out=tfplan-update
# Impossible de savoir quand il a été créé
```

---

### Commandes Avancées

#### Afficher les plans de moins de 24h

```bash
find . -name "tfplan*" -mtime -1 -ls
```

#### Afficher le résumé de chaque plan

```bash
for plan in $(ls -t tfplan* 2>/dev/null); do
  echo "=== $plan ==="
  terraform show -no-color "$plan" | head -20
  echo ""
done
```

#### Vérifier si des plans existent

```bash
ls tfplan* 2>/dev/null || echo "Aucun plan sauvegardé trouvé"
```

---

### Nettoyage Automatique

#### Supprimer les plans de plus de 7 jours

```bash
find . -name "tfplan*" -type f -mtime +7 -delete
```

#### Script de nettoyage

Créez un fichier `cleanup-old-plans.sh` :

```bash
#!/bin/bash
# Nettoyage automatique des plans obsolètes

DAYS_TO_KEEP=7
PLAN_PATTERN="tfplan*"

echo "🧹 Nettoyage des plans de plus de ${DAYS_TO_KEEP} jours..."

# Afficher les plans à supprimer
echo "Plans à supprimer :"
find . -name "${PLAN_PATTERN}" -type f -mtime +${DAYS_TO_KEEP} -print

# Compter
COUNT=$(find . -name "${PLAN_PATTERN}" -type f -mtime +${DAYS_TO_KEEP} | wc -l)

if [ "$COUNT" -eq 0 ]; then
  echo "✅ Aucun plan obsolète trouvé"
  exit 0
fi

# Demander confirmation
read -p "Supprimer ces $COUNT plans ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  find . -name "${PLAN_PATTERN}" -type f -mtime +${DAYS_TO_KEEP} -delete
  echo "✅ $COUNT plans supprimés"
else
  echo "❌ Annulé"
fi
```

**Utilisation :**
```bash
chmod +x cleanup-old-plans.sh
./cleanup-old-plans.sh
```

---

### Commandes Utiles Complètes

```bash
# Navigation vers le répertoire
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev

# Lister tous les plans (plus récent en premier)
ls -lt tfplan*

# Lister uniquement dans le dossier plans/
ls -lt plans/tfplan*

# Voir le contenu d'un plan spécifique
terraform show tfplan-20261009-153000

# Comparer deux plans
terraform show tfplan-20261009-153000 > plan1.txt
terraform show tfplan-20261009-141500 > plan2.txt
diff plan1.txt plan2.txt

# Supprimer un plan spécifique
rm tfplan-20261009-100000

# Nettoyer les vieux plans (plus de 7 jours)
find . -name "tfplan*" -type f -mtime +7 -delete
```

---

## 🚨 Cas d'Urgence

### Si vous devez annuler tous les changements

```bash
# Restaurer l'état depuis AWS (écrase votre état local)
terraform refresh

# Voir ce qui est différent
terraform plan
```

### Si l'état est corrompu

```bash
# Backup de l'état
cp terraform.tfstate terraform.tfstate.backup

# Pull de l'état depuis le backend distant
terraform state pull > terraform.tfstate
```

---

## 📚 Références

- [Terraform Plan Documentation](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Terraform Refresh Documentation](https://developer.hashicorp.com/terraform/cli/commands/refresh)
- [Terraform State Management](https://developer.hashicorp.com/terraform/language/state)

---

## 🤝 Support

Pour toute question ou problème :
1. Vérifier les logs CloudWatch
2. Consulter l'équipe DevOps
3. Créer une issue dans le repository

---

**Dernière mise à jour :** 2026-10-09
**Auteur :** MCP Infrastructure Team