# 📦 Stratégie de Versioning des JARs Lambda

Guide complet du versioning des artefacts Lambda dans le projet MCP.

---

## 🎯 Stratégie Actuelle : Versioning S3 Hybride

### Principe

- **Nom du fichier S3** : Fixe (`client_profile_reader.jar`)
- **Versioning S3** : Activé (versions automatiques)
- **Métadonnées S3** : Version applicative, Git SHA, timestamp
- **Rétention** : 90 jours pour les anciennes versions

---

## 📊 Comment Ça Fonctionne

### 1. **Build & Upload via GitHub Actions**

```
Push vers main/develop
    ↓
GitHub Actions : build-and-deploy.yml
    ├─ Build Maven
    ├─ Extract version from pom.xml
    ├─ Generate Git SHA
    ├─ Upload JARs to S3 avec métadonnées
    └─ Trigger Terraform pour update Lambdas
```

### 2. **Structure S3**

```
Bucket: mcp-lambda-artifacts-ca-central-1

client_profile_reader.jar
├─ Version ID: v123abc (CURRENT)
│  ├─ Metadata:
│  │  ├─ version: 1.0.2
│  │  ├─ git-sha: a1b2c3d
│  │  └─ build-time: 2024-09-30T12:00:00Z
│  └─ Size: 45 MB
│
├─ Version ID: v456def (NON-CURRENT)
│  ├─ Metadata:
│  │  ├─ version: 1.0.1
│  │  ├─ git-sha: e4f5g6h
│  │  └─ build-time: 2024-09-25T10:00:00Z
│  └─ Size: 44 MB
│  └─ Deleted after: 90 days
│
└─ Version ID: v789ghi (NON-CURRENT)
   ├─ Metadata: version: 1.0.0
   └─ Deleted after: 90 days
```

### 3. **Terraform Lambda Configuration**

```hcl
resource "aws_lambda_function" "functions" {
  s3_bucket        = "mcp-lambda-artifacts-ca-central-1"
  s3_key           = "client_profile_reader.jar"  # Nom fixe
  source_code_hash = base64sha256("client_profile_reader-${var.code_version}")

  # Lambda utilise toujours la VERSION ACTUELLE dans S3
}
```

---

## 🔄 Workflow de Déploiement

### **Scénario 1 : Feature Branch → DEV**

```bash
# Développement
git checkout -b feature/add-validation
# ... développement ...
git commit -m "feat: add name validation"
git push origin feature/add-validation

# Workflow GitHub Actions déclenché automatiquement
# ├─ Build JAR avec version 1.0.2-SNAPSHOT
# ├─ Upload vers S3 (nom: client_profile_reader.jar)
# │  └─ Metadata: version=1.0.2-SNAPSHOT, git-sha=abc1234
# └─ Deploy sur DEV via Terraform

# Résultat
Lambda DEV: version 1.0.2-SNAPSHOT (Git SHA: abc1234)
```

### **Scénario 2 : Release → PROD**

```bash
# Release
git checkout main
git tag v1.0.2
git push origin v1.0.2

# Déclencher manuellement le workflow
GitHub Actions → build-and-deploy → PROD → version: 1.0.2

# Résultat
Lambda PROD: version 1.0.2 (Git SHA: def5678)
```

### **Scénario 3 : Rollback**

```bash
# Problème en production détecté

# Option A : Rollback via S3 (rapide)
aws s3api list-object-versions \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --prefix client_profile_reader.jar

# Identifier la version précédente (v456def)
aws s3api copy-object \
  --copy-source "mcp-lambda-artifacts-ca-central-1/client_profile_reader.jar?versionId=v456def" \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --key client_profile_reader.jar

# Trigger Terraform pour update Lambda
cd environments/prod
terraform apply -target=module.lambda -auto-approve

# Option B : Rollback via Git + Redeploy
git revert <commit-sha>
git push
# GitHub Actions redeploy automatiquement
```

---

## 📋 Formats de Version Supportés

### **1. Semantic Versioning (Recommandé)**

```
Format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]

Exemples:
├─ 1.0.0           Production stable
├─ 1.0.1           Bug fix
├─ 1.1.0           Nouvelle feature
├─ 2.0.0           Breaking change
├─ 1.0.0-SNAPSHOT  Development
├─ 1.0.0-beta.1    Beta release
└─ 1.0.0+abc123    Build metadata
```

### **2. Git SHA (Automatique)**

```
Format: 7 premiers caractères du commit SHA

Exemple:
├─ a1b2c3d
└─ Permet de tracer exactement quel commit est déployé
```

### **3. Timestamp (Automatique)**

```
Format: ISO 8601

Exemple:
└─ 2024-09-30T12:00:00Z
```

---

## 🔍 Vérifier les Versions Déployées

### **1. Via AWS Console**

```
1. S3 → Bucket "mcp-lambda-artifacts-ca-central-1"
2. Fichier "client_profile_reader.jar"
3. Properties → Metadata
   ├─ version: 1.0.2
   ├─ git-sha: a1b2c3d
   └─ build-time: 2024-09-30T12:00:00Z
```

### **2. Via AWS CLI**

```bash
# Métadonnées du JAR actuel
aws s3api head-object \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --key client_profile_reader.jar \
  --query 'Metadata' \
  --output json

# Sortie :
{
  "version": "1.0.2",
  "git-sha": "a1b2c3d",
  "build-time": "2024-09-30T12:00:00Z"
}
```

### **3. Via Lambda Console**

```
1. Lambda → Function "dev-mcp-client_profile_reader"
2. Code → Runtime settings
3. Environment variables (si configuré)
   └─ APP_VERSION: 1.0.2
```

### **4. Via Terraform State**

```bash
cd environments/dev
terraform show | grep source_code_hash

# Sortie:
source_code_hash = "YWJjMTIzNA=="
```

---

## 📝 pom.xml Configuration

### **Configuration Maven pour Versioning**

```xml
<project>
    <groupId>com.bnc.mcp</groupId>
    <artifactId>mcp-local</artifactId>
    <version>1.0.2</version>   <!-- VERSION ICI -->

    <build>
        <finalName>${project.artifactId}</finalName>  <!-- Sans version dans nom -->

        <plugins>
            <!-- Build Info Plugin -->
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <executions>
                    <execution>
                        <goals>
                            <goal>build-info</goal>
                        </goals>
                        <configuration>
                            <additionalProperties>
                                <git.commit>${git.commit.id.abbrev}</git.commit>
                                <build.time>${maven.build.timestamp}</build.time>
                            </additionalProperties>
                        </configuration>
                    </execution>
                </executions>
            </plugin>

            <!-- Git Commit ID Plugin -->
            <plugin>
                <groupId>pl.project13.maven</groupId>
                <artifactId>git-commit-id-plugin</artifactId>
                <version>4.9.10</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>revision</goal>
                        </goals>
                    </execution>
                </executions>
                <configuration>
                    <dotGitDirectory>${project.basedir}/.git</dotGitDirectory>
                    <generateGitPropertiesFile>true</generateGitPropertiesFile>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
```

---

## 🚨 Gestion des Erreurs

### **Problème 1 : Version Conflict**

**Symptôme** : Deux builds avec même version mais code différent

**Solution** :
```bash
# Toujours incrémenter la version dans pom.xml avant merge
git diff main pom.xml

# Vérifier que la version a changé
```

### **Problème 2 : Métadonnées Manquantes**

**Symptôme** : JAR uploadé sans métadonnées

**Solution** :
```bash
# Re-upload avec métadonnées
aws s3 cp target/client_profile_reader.jar \
  s3://mcp-lambda-artifacts-ca-central-1/client_profile_reader.jar \
  --metadata "version=1.0.2,git-sha=$(git rev-parse --short HEAD)"
```

### **Problème 3 : Lambda Utilise Ancienne Version**

**Symptôme** : Terraform apply ne met pas à jour la Lambda

**Cause** : `source_code_hash` identique

**Solution** :
```bash
# Changer code_version dans dev.tfvars
code_version = "1.0.2"  # au lieu de 1.0.1

# Réappliquer
terraform apply -target=module.lambda -auto-approve
```

---

## 📊 Comparaison avec Autres Stratégies

### **Stratégie A : Versioning dans Nom (Rejetée)**

```
S3 Files:
├─ client_profile_reader-1.0.0.jar
├─ client_profile_reader-1.0.1.jar
├─ client_profile_reader-1.0.2.jar
└─ ... (100+ fichiers après 1 an)

Problèmes:
❌ Accumulation de fichiers
❌ Doit modifier s3_key dans Terraform
❌ Lifecycle policy complexe
```

### **Stratégie B : Tags Git Uniquement (Rejetée)**

```
Deployment process:
1. Tag Git
2. Build JAR
3. Upload sans metadata
4. Deploy

Problèmes:
❌ Impossible de savoir quelle version est déployée sans Git
❌ Pas de traçabilité dans S3/Lambda
```

### **Stratégie C : Hybride (Actuelle) ✅**

```
S3 Files:
└─ client_profile_reader.jar
   ├─ Versions: v1, v2, v3... (S3 versioning)
   └─ Metadata: version, git-sha, build-time

Avantages:
✅ Nom fixe (simple)
✅ Métadonnées riches
✅ S3 versioning automatique
✅ Rollback facile
✅ Traçabilité complète
```

---

## 🔐 Best Practices

### ✅ DO

1. **Toujours incrémenter la version** dans pom.xml avant merge
2. **Utiliser Semantic Versioning** (1.0.0, 1.0.1, 1.1.0, 2.0.0)
3. **Créer des tags Git** pour les releases production
4. **Vérifier les métadonnées S3** après upload
5. **Documenter les changements** dans CHANGELOG.md

### ❌ DON'T

1. **Ne jamais réutiliser un numéro de version** (ex: 1.0.0 → 1.0.1 → 1.0.0)
2. **Ne pas uploader manuellement sans métadonnées**
3. **Ne pas sauter de versions** (ex: 1.0.0 → 1.0.5)
4. **Ne pas modifier les fichiers S3 directement**

---

## 📞 Commandes Utiles

### **Lister toutes les versions d'un JAR**

```bash
aws s3api list-object-versions \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --prefix client_profile_reader.jar \
  --query 'Versions[*].[VersionId,LastModified,Size]' \
  --output table
```

### **Voir les métadonnées de chaque version**

```bash
for version_id in $(aws s3api list-object-versions \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --prefix client_profile_reader.jar \
  --query 'Versions[*].VersionId' \
  --output text); do

  echo "Version ID: $version_id"
  aws s3api head-object \
    --bucket mcp-lambda-artifacts-ca-central-1 \
    --key client_profile_reader.jar \
    --version-id $version_id \
    --query 'Metadata'
  echo "---"
done
```

### **Nettoyer les anciennes versions manuellement**

```bash
# Lister versions de plus de 90 jours
aws s3api list-object-versions \
  --bucket mcp-lambda-artifacts-ca-central-1 \
  --prefix client_profile_reader.jar \
  --query "Versions[?LastModified<'$(date -u -d '90 days ago' --iso-8601=seconds)'].[VersionId]" \
  --output text | \
while read version_id; do
  aws s3api delete-object \
    --bucket mcp-lambda-artifacts-ca-central-1 \
    --key client_profile_reader.jar \
    --version-id $version_id
done
```

---

## 🎯 Résumé

**Notre stratégie de versioning** :

1. ✅ **Nom de fichier S3 fixe** : `client_profile_reader.jar`
2. ✅ **S3 Versioning activé** : Versions automatiques avec IDs
3. ✅ **Métadonnées riches** : version applicative, Git SHA, timestamp
4. ✅ **Rétention 90 jours** : Anciennes versions supprimées auto
5. ✅ **GitHub Actions** : Build, upload, deploy automatisé
6. ✅ **Rollback facile** : Restaurer version S3 précédente
7. ✅ **Traçabilité complète** : Du code source au déploiement

**Avantages** : Simple, traçable, réversible, automatisé.

**Dernière mise à jour** : 2024-09-30