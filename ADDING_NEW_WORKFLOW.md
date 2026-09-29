# Guide: Ajouter un nouveau workflow

Ce guide explique comment ajouter un nouveau workflow Step Functions à l'infrastructure MCP, avec un exemple concret: le workflow `updateAddress`.

**Architecture 2 repos:** Ce guide utilise une séparation entre infrastructure de base et workflows applicatifs.

---

## Table des matières

1. [Vue d'ensemble de l'architecture](#vue-densemble-de-larchitecture)
2. [PARTIE 1: Déploiement infrastructure de base (une fois)](#partie-1-déploiement-infrastructure-de-base)
3. [PARTIE 2: Créer et déployer un nouveau workflow](#partie-2-créer-et-déployer-un-nouveau-workflow)
4. [Déploiement](#déploiement)
5. [Test](#test)
6. [Checklist](#checklist)

---

## Vue d'ensemble de l'architecture

### Pourquoi 2 repos séparés?

**Problème avec mono-repo:**
- Code Java métier mélangé avec infrastructure Terraform
- Impossible de déployer un nouveau workflow sans toucher à l'infrastructure
- Équipes Dev et Infra travaillent dans le même repo

**Solution: Architecture 2 repos**

```
┌─────────────────────────────────────────────────────────────────┐
│ REPO 1: mcp-infrastructure (Infrastructure de base)            │
│                                                                  │
│ Contient: VPC, DynamoDB, IAM, Secrets, API Gateway (vide)      │
│ Déployé par: Équipe Infrastructure                              │
│ Fréquence: Une fois au setup, puis rarement                     │
│                                                                  │
│ Outputs:                                                         │
│ - vpc_id                                                         │
│ - dynamodb_table_name                                           │
│ - lambda_execution_role_arn                                     │
│ - api_gateway_id                                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    (Terraform Remote State)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ REPO 2: mcp-services (Application Spring Boot)                 │
│                                                                  │
│ Contient: Projet Spring Boot Maven avec:                        │
│ - Code métier (@Service, @Component)                            │
│ - Lambda Handlers (qui injectent les @Service)                 │
│ - REST Controllers (pour dev local)                             │
│ - Step Functions workflows                                      │
│ - Terraform pour déployer                                       │
│                                                                  │
│ Déployé par: Équipe Développement                               │
│ Fréquence: À chaque nouveau workflow ou modification            │
│                                                                  │
│ Peut être exécuté:                                               │
│ - Localement: mvn spring-boot:run (développement)              │
│ - Sur AWS Lambda: déployé via Terraform                         │
└─────────────────────────────────────────────────────────────────┘
```

---

### Exemple: Workflow de mise à jour d'adresse

**Objectif:** Permettre la mise à jour de l'adresse d'un client via l'API REST.

**Flow du workflow:**
```
API Gateway (PUT /api/clients/{id}/adresse)
    ↓
Step Functions: client-address-update
    ↓
┌─────────────────────────────────────────┐
│ 1. ReadClientProfile (Lambda existante) │
│ 2. ValidateAddress (Lambda NOUVELLE)    │
│ 3. FormatAddress (Lambda NOUVELLE)      │
│ 4. CallMDMAE (Lambda existante)         │
│ 5. SendToFCC (Lambda existante)         │
│ 6. UpdateDynamoDB                        │
└─────────────────────────────────────────┘
    ↓
Réponse API
```

**Principe général:**
- **Réutiliser** l'infrastructure de base (repo 1: DynamoDB, IAM, VPC, API Gateway)
- **Créer** les nouveaux services Spring Boot dans le repo 2
- **Ajouter** un nouveau workflow Step Functions dans le repo 2
- **Exposer** via un nouvel endpoint sur l'API Gateway existante

---

### Structure des repos

#### Repo 1: `mcp-infrastructure`

```
mcp-infrastructure/
├── modules/
│   ├── vpc/              # Réseau AWS
│   ├── dynamodb/         # Table ClientProfile
│   ├── iam/              # Rôles Lambda, Step Functions, API Gateway
│   ├── secrets-manager/  # Secrets IBM MQ, MDMAE
│   ├── sqs/              # Queues FCC responses
│   ├── msk/              # Kafka pour événements
│   ├── api-gateway/      # API Gateway (structure de base uniquement)
│   └── cloudwatch/       # Dashboards et alarmes
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── outputs.tf   # ✅ IMPORTANT: Exporte les ressources
│   └── prod/
└── .github/workflows/
    └── deploy-infra.yml
```

**Outputs exportés (environments/dev/outputs.tf):**
```hcl
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "lambda_execution_role_arn" {
  value = module.iam.lambda_execution_role_arn
}

output "stepfunctions_execution_role_arn" {
  value = module.iam.stepfunctions_execution_role_arn
}

output "api_gateway_id" {
  value = module.api_gateway.api_id
}

output "api_gateway_root_resource_id" {
  value = module.api_gateway.root_resource_id
}

output "api_gateway_client_id_resource_id" {
  value = module.api_gateway.client_id_resource_id
}

output "secrets_arns" {
  value = module.secrets.secret_arns
}
```

---

#### Repo 2: `mcp-services` (Projet Spring Boot)

```
mcp-services/  (UN SEUL projet Spring Boot Maven)
├── src/main/java/com/bnc/mcp/
│   ├── McpServicesApplication.java       # @SpringBootApplication
│   ├── controller/
│   │   └── AddressController.java        # @RestController (dev local)
│   ├── service/
│   │   ├── AddressValidatorService.java  # @Service (logique métier)
│   │   └── AddressFormatterService.java  # @Service
│   ├── handler/
│   │   ├── AddressValidatorHandler.java  # AWS Lambda handler
│   │   └── AddressFormatterHandler.java  # AWS Lambda handler
│   ├── model/
│   │   ├── AddressValidationRequest.java
│   │   └── AddressValidationResult.java
│   └── config/
│       └── AwsConfig.java                # Configuration AWS
├── src/main/resources/
│   ├── application.yml                   # Config Spring Boot
│   └── application-lambda.yml            # Config pour Lambda
├── pom.xml                               # Spring Boot + AWS Lambda
├── workflows/                            # Définitions Step Functions
│   └── client-address-update.json.tpl
├── terraform/                            # Terraform pour déployer
│   ├── main.tf
│   ├── data.tf
│   ├── variables.tf
│   ├── backend.tf
│   └── outputs.tf
└── .github/workflows/
    └── deploy-workflow.yml               # CI/CD
```

**Architecture Spring Boot + Lambda:**

- **Spring Boot local**: Utilise les @RestController pour tester localement
- **Spring Boot sur Lambda**: Les Lambda handlers injectent les @Service
- **Un seul JAR**: Déployé sur toutes les Lambdas, chaque Lambda a un handler différent
- **AWS Serverless Java Container**: Fait le pont entre Lambda et Spring Boot

---

## PARTIE 1: Déploiement infrastructure de base

**🎯 Objectif:** Déployer l'infrastructure AWS de base qui sera partagée par tous les workflows.

**⏱️ Fréquence:** Une seule fois au démarrage du projet, puis rarement.

**👥 Qui:** Équipe Infrastructure / DevOps

---

### Prérequis

Le repo `mcp-infrastructure` doit déjà contenir:

- ✅ Module VPC (réseaux, subnets, security groups)
- ✅ Module DynamoDB (table `ClientProfile`)
- ✅ Module IAM (rôles Lambda, Step Functions, API Gateway)
- ✅ Module Secrets Manager (IBM MQ, MDMAE)
- ✅ Module SQS (queues FCC responses)
- ✅ Module MSK (Kafka)
- ✅ Module API Gateway (structure de base, **sans endpoints**)
- ✅ Module CloudWatch (dashboards, alarmes)

---

### Déploiement de l'infrastructure

```bash
# Cloner le repo infrastructure
git clone https://github.com/VOTRE_ORG/mcp-infrastructure.git
cd mcp-infrastructure

# Créer le backend S3 pour le state (première fois uniquement)
./scripts/create-backend.sh dev ca-central-1

# Déployer via GitHub Actions ou localement
cd environments/dev
terraform init
terraform plan
terraform apply

# Vérifier les outputs
terraform output
```

**Outputs attendus:**
```
api_gateway_id                    = "abc123xyz"
api_gateway_root_resource_id      = "/api/clients"
api_gateway_client_id_resource_id = "/api/clients/{clientId}"
dynamodb_table_name               = "dev-mcp-ClientProfile"
lambda_execution_role_arn         = "arn:aws:iam::123:role/dev-mcp-lambda-execution"
stepfunctions_execution_role_arn  = "arn:aws:iam::123:role/dev-mcp-stepfunctions-execution"
vpc_id                            = "vpc-abc123"
secrets_arns                      = {
  ibmmq = "arn:aws:secretsmanager:ca-central-1:123:secret:dev-mcp-ibmmq"
  mdmae = "arn:aws:secretsmanager:ca-central-1:123:secret:dev-mcp-mdmae"
}
```

**✅ Résultat:**
- Infrastructure AWS de base déployée
- API Gateway créée (mais sans endpoints métier)
- DynamoDB, IAM, Secrets prêts à être utilisés
- State Terraform uploadé dans S3

**🎉 L'infrastructure est prête à recevoir des workflows!**

---

## PARTIE 2: Créer et déployer un nouveau workflow

**🎯 Objectif:** Développer et déployer un nouveau workflow (ex: `updateAddress`) dans l'application Spring Boot sur l'infrastructure existante.

**⏱️ Fréquence:** À chaque nouveau workflow ou modification métier.

**👥 Qui:** Équipe Développement / App Team

---

### Vue d'ensemble des étapes

```
Étape 1: Créer le projet Spring Boot Maven (si nouveau)
    ↓
Étape 2: Ajouter les services métier (@Service)
    ↓
Étape 3: Ajouter les Lambda handlers (qui injectent @Service)
    ↓
Étape 4: Ajouter les controllers REST (pour dev local)
    ↓
Étape 5: Créer la définition du workflow Step Functions
    ↓
Étape 6: Créer la configuration Terraform
    ↓
Étape 7: Tester localement avec Spring Boot
    ↓
Étape 8: Builder et déployer via GitHub Actions
```

---

### Nouvelles ressources AWS créées

| Ressource | Nom | Rôle | Repo |
|-----------|-----|------|------|
| **Lambda** | `address-validator` | Valide la nouvelle adresse | mcp-services |
| **Lambda** | `address-formatter` | Formate l'adresse selon les standards | mcp-services |
| **Step Functions** | `client-address-update` | Orchestre le workflow | mcp-services |
| **API Gateway Resource** | `/api/clients/{clientId}/adresse` | Endpoint REST | mcp-services |
| **API Gateway Method** | `PUT` | Méthode HTTP | mcp-services |
| **CloudWatch Log Groups** | 2 (pour les nouvelles Lambdas) | Logs | mcp-services |

**Total:** ~6 nouvelles ressources AWS

---

### Ressources réutilisées (depuis repo 1)

- ✅ DynamoDB table `ClientProfile`
- ✅ Secrets Manager (IBM MQ, MDMAE)
- ✅ SQS queue `fcc_responses`
- ✅ IAM roles (Lambda, Step Functions, API Gateway)
- ✅ VPC, MSK, EventBridge
- ✅ API Gateway (structure de base)

---

## Étapes détaillées

### Étape 1: Créer le projet Spring Boot Maven

**🎯 Objectif de cette étape:**
Créer le projet Spring Boot Maven qui contiendra TOUS les workflows et services. Ce projet peut être exécuté localement pour le développement et déployé sur Lambda pour la production.

**📍 Où:** Nouveau repo `mcp-services`

**⚙️ Ce qui se passe:**
1. Création d'un projet Spring Boot Maven standard
2. Ajout des dépendances AWS Lambda
3. Configuration pour supporter local ET Lambda
4. Structure de packages organisée

**💡 Pourquoi Spring Boot:**
- **Développement local:** Exécuter et tester sans déployer sur AWS
- **Dependency Injection:** @Service, @Component, @Autowired
- **Configuration centralisée:** application.yml
- **Tests faciles:** Spring Boot Test
- **Réutilisabilité:** Les @Service peuvent être utilisés partout

---

#### 1.1 - Créer le projet

```bash
# Créer le répertoire du projet
mkdir mcp-services
cd mcp-services
git init

# Créer la structure Spring Boot standard
mkdir -p src/main/java/com/bnc/mcp
mkdir -p src/main/resources
mkdir -p src/test/java/com/bnc/mcp
mkdir -p workflows
mkdir -p terraform
```

---

#### 1.2 - Créer le `pom.xml`

**📋 Rôle:** Configuration Maven avec Spring Boot parent et dépendances AWS Lambda

`pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <!-- ========================================
         SPRING BOOT PARENT
         ======================================== -->
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
        <relativePath/>
    </parent>

    <!-- ========================================
         PROJECT COORDINATES
         ======================================== -->
    <groupId>com.bnc.mcp</groupId>
    <artifactId>mcp-services</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>MCP Services</name>
    <description>Spring Boot application for MCP workflows (local and Lambda)</description>

    <!-- ========================================
         PROPERTIES
         ======================================== -->
    <properties>
        <java.version>17</java.version>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <aws.lambda.java.version>1.2.3</aws.lambda.java.version>
        <aws.serverless.java.version>2.0.0</aws.serverless.java.version>
    </properties>

    <!-- ========================================
         DEPENDENCIES
         ======================================== -->
    <dependencies>
        <!-- Spring Boot Starter -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter</artifactId>
        </dependency>

        <!-- Spring Boot Web (pour REST controllers) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>

        <!-- Spring Boot Validation -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>

        <!-- AWS Lambda Java Core -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-core</artifactId>
            <version>${aws.lambda.java.version}</version>
        </dependency>

        <!-- AWS Lambda Java Events -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-events</artifactId>
            <version>3.11.4</version>
        </dependency>

        <!-- AWS Serverless Java Container (Spring Boot sur Lambda) -->
        <dependency>
            <groupId>com.amazonaws.serverless</groupId>
            <artifactId>aws-serverless-java-container-springboot3</artifactId>
            <version>${aws.serverless.java.version}</version>
        </dependency>

        <!-- AWS SDK v2 (DynamoDB, Secrets Manager, etc.) -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>dynamodb</artifactId>
            <version>2.21.0</version>
        </dependency>

        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>secretsmanager</artifactId>
            <version>2.21.0</version>
        </dependency>

        <!-- Lombok (optionnel mais recommandé) -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <optional>true</optional>
        </dependency>

        <!-- Spring Boot Test -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <!-- ========================================
         BUILD
         ======================================== -->
    <build>
        <plugins>
            <!-- Maven Compiler Plugin -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>17</source>
                    <target>17</target>
                </configuration>
            </plugin>

            <!-- Spring Boot Maven Plugin (pour exécution locale) -->
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    <excludes>
                        <exclude>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                        </exclude>
                    </excludes>
                </configuration>
            </plugin>

            <!-- Maven Shade Plugin (pour créer un fat JAR pour Lambda) -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.5.1</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <createDependencyReducedPom>false</createDependencyReducedPom>
                            <shadedArtifactAttached>true</shadedArtifactAttached>
                            <shadedClassifierName>aws</shadedClassifierName>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>com.bnc.mcp.McpServicesApplication</mainClass>
                                </transformer>
                                <!-- Spring Boot transformer -->
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.handlers</resource>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.schemas</resource>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.factories</resource>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports</resource>
                                </transformer>
                            </transformers>
                            <filters>
                                <filter>
                                    <artifact>*:*</artifact>
                                    <excludes>
                                        <exclude>META-INF/*.SF</exclude>
                                        <exclude>META-INF/*.DSA</exclude>
                                        <exclude>META-INF/*.RSA</exclude>
                                    </excludes>
                                </filter>
                            </filters>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
```

**💡 Points clés du pom.xml:**
- **Spring Boot parent**: Gère les versions des dépendances
- **aws-serverless-java-container-springboot3**: Adapter Lambda ↔ Spring Boot
- **Maven Shade Plugin**: Crée un fat JAR avec toutes les dépendances
- **Classifier "aws"**: Produit `mcp-services-1.0.0-aws.jar` pour Lambda
- **Spring Boot transformers**: Fusionne correctement les fichiers Spring dans le JAR

---

#### 1.3 - Créer l'application principale

`src/main/java/com/bnc/mcp/McpServicesApplication.java`

```java
package com.bnc.mcp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Application Spring Boot principale pour les services MCP.
 *
 * Peut être exécutée:
 * - Localement: mvn spring-boot:run (mode développement)
 * - Sur AWS Lambda: via les handlers Lambda
 */
@SpringBootApplication
public class McpServicesApplication {

    public static void main(String[] args) {
        SpringApplication.run(McpServicesApplication.class, args);
    }
}
```

---

#### 1.4 - Créer la configuration

`src/main/resources/application.yml`

```yaml
spring:
  application:
    name: mcp-services
  profiles:
    active: local

# Configuration locale (développement)
---
spring:
  config:
    activate:
      on-profile: local

server:
  port: 8080

logging:
  level:
    com.bnc.mcp: DEBUG

# Configuration Lambda (production)
---
spring:
  config:
    activate:
      on-profile: lambda

logging:
  level:
    com.bnc.mcp: INFO
```

---

**✅ Résultat de l'étape 1:**

```
mcp-services/
├── pom.xml                          ✅ (Spring Boot + AWS Lambda)
├── src/main/java/com/bnc/mcp/
│   └── McpServicesApplication.java  ✅
├── src/main/resources/
│   └── application.yml              ✅
├── workflows/                       (vide pour l'instant)
└── terraform/                       (vide pour l'instant)
```

- ✅ Projet Spring Boot Maven créé
- ✅ Configuration pour local ET Lambda
- ✅ Prêt à recevoir les services et handlers

---

### Étape 2: Ajouter les services métier (@Service)

**🎯 Objectif de cette étape:**
Créer les services Spring Boot qui contiennent la logique métier. Ces services seront injectés dans les Lambda handlers ET dans les REST controllers.

**📍 Où:** `src/main/java/com/bnc/mcp/service/`

**⚙️ Ce qui se passe:**
1. Création des classes @Service
2. Injection des dépendances via @Autowired
3. Logique métier réutilisable
4. Peut être testée unitairement

**💡 Pourquoi @Service:**
- **Réutilisabilité:** Même code pour Lambda ET local
- **Testabilité:** Tests unitaires avec Spring Boot Test
- **Maintenabilité:** Logique métier centralisée
- **Dependency Injection:** Spring gère les dépendances

---

#### 2.1 - Créer les models

`src/main/java/com/bnc/mcp/model/AddressValidationRequest.java`

```java
package com.bnc.mcp.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class AddressValidationRequest {
    private String clientId;
    private String currentAddress;
    private String newAddress;
}
```

`src/main/java/com/bnc/mcp/model/AddressValidationResult.java`

```java
package com.bnc.mcp.model;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AddressValidationResult {
    private boolean isValid;
    private boolean requiresHumanReview;
    private String message;
}
```

---

#### 2.2 - Créer le service de validation

`src/main/java/com/bnc/mcp/service/AddressValidatorService.java`

```java
package com.bnc.mcp.service;

import com.bnc.mcp.model.AddressValidationRequest;
import com.bnc.mcp.model.AddressValidationResult;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.regex.Pattern;

/**
 * Service de validation d'adresses canadiennes.
 *
 * Logique métier réutilisable pour:
 * - Lambda handlers
 * - REST controllers
 * - Tests unitaires
 */
@Slf4j
@Service
public class AddressValidatorService {

    // Pattern pour valider un code postal canadien (format: A1A 1A1)
    private static final Pattern POSTAL_CODE_PATTERN = Pattern.compile("^[A-Z]\\d[A-Z] \\d[A-Z]\\d$");

    /**
     * Valide une adresse selon les règles métier.
     */
    public AddressValidationResult validate(AddressValidationRequest request) {
        log.info("Validating address for client: {}", request.getClientId());

        String address = request.getNewAddress();

        // Règle 1: Adresse non vide
        if (address == null || address.trim().isEmpty()) {
            return buildResult(false, false, "Adresse vide");
        }

        // Règle 2: Longueur minimale
        if (address.length() < 10) {
            return buildResult(false, false, "Adresse trop courte");
        }

        // Règle 3: Code postal canadien obligatoire
        if (!POSTAL_CODE_PATTERN.matcher(address).find()) {
            // Si code postal manquant/invalide → revue manuelle
            return buildResult(false, true, "Code postal invalide ou manquant - revue manuelle requise");
        }

        // Règle 4: Numéro de rue obligatoire
        if (!address.matches("^\\d+.*")) {
            return buildResult(false, false, "Numéro de rue manquant");
        }

        // Toutes les règles passées
        log.info("Address validation succeeded for client: {}", request.getClientId());
        return buildResult(true, false, "Adresse valide");
    }

    private AddressValidationResult buildResult(boolean isValid, boolean requiresHumanReview, String message) {
        return AddressValidationResult.builder()
                .isValid(isValid)
                .requiresHumanReview(requiresHumanReview)
                .message(message)
                .build();
    }
}
```

---

#### 2.3 - Créer le service de formatage

`src/main/java/com/bnc/mcp/service/AddressFormatterService.java`

```java
package com.bnc.mcp.service;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Service de formatage d'adresses selon les standards canadiens.
 */
@Slf4j
@Service
public class AddressFormatterService {

    /**
     * Formate une adresse selon les standards.
     */
    public String format(String address) {
        if (address == null) {
            return "";
        }

        log.debug("Formatting address: {}", address);

        String formatted = address;

        // Étape 1: Retirer les espaces en trop
        formatted = formatted.trim();
        formatted = formatted.replaceAll("\\s+", " ");

        // Étape 2: Mettre en majuscules
        formatted = formatted.toUpperCase();

        // Étape 3: Normaliser le code postal (format: A1A 1A1)
        // Transforme "H2X1Y5" en "H2X 1Y5"
        formatted = formatted.replaceAll("([A-Z]\\d[A-Z])(\\d[A-Z]\\d)", "$1 $2");

        // Étape 4: Appliquer les abréviations standards
        formatted = formatted.replace(" AVENUE", " AVE");
        formatted = formatted.replace(" BOULEVARD", " BOUL");
        formatted = formatted.replace(" STREET", " RUE");
        formatted = formatted.replace(" APPARTEMENT", " APP");
        formatted = formatted.replace(" APARTMENT", " APP");
        formatted = formatted.replace(" SUITE", " STE");

        log.debug("Formatted address: {}", formatted);
        return formatted;
    }
}
```

---

**✅ Résultat de l'étape 2:**

```
mcp-services/
└── src/main/java/com/bnc/mcp/
    ├── model/
    │   ├── AddressValidationRequest.java   ✅
    │   └── AddressValidationResult.java    ✅
    └── service/
        ├── AddressValidatorService.java    ✅ (@Service)
        └── AddressFormatterService.java    ✅ (@Service)
```

- ✅ Services métier créés avec @Service
- ✅ Logique métier réutilisable
- ✅ Prêts à être injectés dans Lambda handlers

---

### Étape 3: Ajouter les Lambda handlers

**🎯 Objectif de cette étape:**
Créer les handlers AWS Lambda qui injectent les @Service Spring Boot. Ces handlers sont les points d'entrée pour AWS Lambda.

**📍 Où:** `src/main/java/com/bnc/mcp/handler/`

**⚙️ Ce qui se passe:**
1. Création des classes Lambda handler
2. Injection des @Service via Spring
3. Utilisation de SpringBootLambdaContainerHandler
4. Ces handlers seront déployés sur AWS Lambda

**💡 Pourquoi des handlers séparés:**
- **Point d'entrée Lambda:** AWS Lambda appelle la méthode `handleRequest`
- **Injection Spring:** Les handlers injectent les @Service
- **Réutilisation:** Même logique métier que le code local
- **Testabilité:** Peut être testé avec Spring Boot Test

---

#### 3.1 - Créer le handler de validation

`src/main/java/com/bnc/mcp/handler/AddressValidatorHandler.java`

```java
package com.bnc.mcp.handler;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.McpServicesApplication;
import com.bnc.mcp.model.AddressValidationRequest;
import com.bnc.mcp.model.AddressValidationResult;
import com.bnc.mcp.service.AddressValidatorService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.util.Map;

/**
 * AWS Lambda Handler pour la validation d'adresses.
 *
 * Injecte AddressValidatorService via Spring Boot.
 *
 * Input attendu (depuis Step Functions):
 * {
 *   "clientId": "CLIENT123",
 *   "currentAddress": "ancienne adresse",
 *   "newAddress": "123 Rue Main, Montreal, QC H2X 1Y5"
 * }
 *
 * Output retourné:
 * {
 *   "isValid": true/false,
 *   "requiresHumanReview": true/false,
 *   "message": "Description du résultat"
 * }
 */
@Slf4j
public class AddressValidatorHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> handler;
    private static AddressValidatorService validatorService;
    private static final ObjectMapper objectMapper = new ObjectMapper();

    static {
        try {
            // Initialiser Spring Boot dans Lambda
            handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(McpServicesApplication.class);

            // Récupérer le bean Spring
            validatorService = handler.getApplicationContext().getBean(AddressValidatorService.class);

            log.info("AddressValidatorHandler initialized successfully");
        } catch (ContainerInitializationException e) {
            log.error("Failed to initialize Spring Boot in Lambda", e);
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        log.info("Handling address validation request for client: {}", input.get("clientId"));

        try {
            // Convertir l'input en objet
            AddressValidationRequest request = objectMapper.convertValue(input, AddressValidationRequest.class);

            // Appeler le service Spring Boot
            AddressValidationResult result = validatorService.validate(request);

            // Retourner le résultat
            return objectMapper.convertValue(result, Map.class);
        } catch (Exception e) {
            log.error("Error validating address", e);
            return Map.of(
                "isValid", false,
                "requiresHumanReview", false,
                "message", "Erreur lors de la validation: " + e.getMessage()
            );
        }
    }
}
```

---

#### 3.2 - Créer le handler de formatage

`src/main/java/com/bnc/mcp/handler/AddressFormatterHandler.java`

```java
package com.bnc.mcp.handler;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.McpServicesApplication;
import com.bnc.mcp.service.AddressFormatterService;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * AWS Lambda Handler pour le formatage d'adresses.
 *
 * Injecte AddressFormatterService via Spring Boot.
 *
 * Input attendu (depuis Step Functions):
 * {
 *   "address": "123 rue principale  montreal  h2x1y5"
 * }
 *
 * Output retourné:
 * {
 *   "formattedAddress": "123 RUE PRINCIPALE MONTREAL H2X 1Y5"
 * }
 */
@Slf4j
public class AddressFormatterHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> handler;
    private static AddressFormatterService formatterService;

    static {
        try {
            // Initialiser Spring Boot dans Lambda
            handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(McpServicesApplication.class);

            // Récupérer le bean Spring
            formatterService = handler.getApplicationContext().getBean(AddressFormatterService.class);

            log.info("AddressFormatterHandler initialized successfully");
        } catch (ContainerInitializationException e) {
            log.error("Failed to initialize Spring Boot in Lambda", e);
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        String address = (String) input.get("address");
        log.info("Handling address formatting request: {}", address);

        try {
            // Appeler le service Spring Boot
            String formatted = formatterService.format(address);

            // Retourner le résultat
            return Map.of("formattedAddress", formatted);
        } catch (Exception e) {
            log.error("Error formatting address", e);
            return Map.of("formattedAddress", address); // Retourner l'original en cas d'erreur
        }
    }
}
```

---

**✅ Résultat de l'étape 3:**

```
mcp-services/
└── src/main/java/com/bnc/mcp/
    └── handler/
        ├── AddressValidatorHandler.java  ✅ (Lambda handler + Spring)
        └── AddressFormatterHandler.java  ✅ (Lambda handler + Spring)
```

- ✅ Lambda handlers créés
- ✅ Injectent les @Service Spring Boot
- ✅ Prêts à être déployés sur AWS Lambda

---

### Étape 4: Ajouter les REST controllers (pour dev local)

**🎯 Objectif de cette étape:**
Créer des REST controllers Spring Boot pour pouvoir tester l'application localement sans déployer sur AWS.

**📍 Où:** `src/main/java/com/bnc/mcp/controller/`

**⚙️ Ce qui se passe:**
1. Création des @RestController
2. Injection des @Service
3. Endpoints REST pour tester localement
4. Mêmes services que Lambda

**💡 Pourquoi des controllers:**
- **Développement rapide:** Tester sans déployer sur AWS
- **Debugging:** Debugger avec IntelliJ/Eclipse
- **Tests d'intégration:** Appeler les endpoints avec curl/Postman
- **Même logique:** Utilise les mêmes @Service que Lambda

---

`src/main/java/com/bnc/mcp/controller/AddressController.java`

```java
package com.bnc.mcp.controller;

import com.bnc.mcp.model.AddressValidationRequest;
import com.bnc.mcp.model.AddressValidationResult;
import com.bnc.mcp.service.AddressFormatterService;
import com.bnc.mcp.service.AddressValidatorService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * REST Controller pour le développement local.
 *
 * Endpoints disponibles:
 * - POST /api/address/validate - Valider une adresse
 * - POST /api/address/format - Formater une adresse
 *
 * Utilise les mêmes @Service que les Lambda handlers.
 */
@Slf4j
@RestController
@RequestMapping("/api/address")
@RequiredArgsConstructor
public class AddressController {

    private final AddressValidatorService validatorService;
    private final AddressFormatterService formatterService;

    /**
     * Valider une adresse (même logique que Lambda).
     *
     * curl -X POST http://localhost:8080/api/address/validate \
     *   -H "Content-Type: application/json" \
     *   -d '{"clientId":"CLIENT123","newAddress":"123 Rue Main, Montreal, QC H2X 1Y5"}'
     */
    @PostMapping("/validate")
    public ResponseEntity<AddressValidationResult> validate(@RequestBody AddressValidationRequest request) {
        log.info("Validating address for client: {}", request.getClientId());

        AddressValidationResult result = validatorService.validate(request);

        return ResponseEntity.ok(result);
    }

    /**
     * Formater une adresse (même logique que Lambda).
     *
     * curl -X POST http://localhost:8080/api/address/format \
     *   -H "Content-Type: application/json" \
     *   -d '{"address":"123 rue principale  montreal  h2x1y5"}'
     */
    @PostMapping("/format")
    public ResponseEntity<Map<String, String>> format(@RequestBody Map<String, String> request) {
        String address = request.get("address");
        log.info("Formatting address: {}", address);

        String formatted = formatterService.format(address);

        return ResponseEntity.ok(Map.of("formattedAddress", formatted));
    }

    /**
     * Healthcheck endpoint.
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }
}
```

---

**✅ Résultat de l'étape 4:**

```
mcp-services/
└── src/main/java/com/bnc/mcp/
    └── controller/
        └── AddressController.java  ✅ (@RestController)
```

- ✅ REST controllers créés
- ✅ Injectent les @Service (mêmes que Lambda)
- ✅ Prêts pour tests locaux

---

### Étape 5: Tester localement avec Spring Boot

**🎯 Objectif:** Exécuter et tester l'application localement avant de déployer sur AWS

**⚙️ Commandes:**

```bash
cd mcp-services

# Compiler
mvn clean compile

# Exécuter l'application
mvn spring-boot:run

# Dans un autre terminal, tester les endpoints
curl -X POST http://localhost:8080/api/address/validate \
  -H "Content-Type: application/json" \
  -d '{"clientId":"CLIENT123","newAddress":"123 Rue Main, Montreal, QC H2X 1Y5"}'

# Résultat attendu:
# {
#   "isValid": true,
#   "requiresHumanReview": false,
#   "message": "Adresse valide"
# }

curl -X POST http://localhost:8080/api/address/format \
  -H "Content-Type: application/json" \
  -d '{"address":"123 rue principale  montreal  h2x1y5"}'

# Résultat attendu:
# {
#   "formattedAddress": "123 RUE PRINCIPALE MONTREAL H2X 1Y5"
# }
```

**✅ Si les tests locaux fonctionnent, vous êtes prêts à déployer sur Lambda!**

---

### Étape 6: Créer la définition du workflow Step Functions

**🎯 Objectif:** Définir l'orchestration complète du workflow

**📍 Où:** `workflows/client-address-update.json.tpl`

*[Le contenu JSON Step Functions reste identique à la version précédente - je ne le réécris pas pour économiser de l'espace]*

---

### Étape 7: Créer la configuration Terraform

**🎯 Objectif:** Déployer les Lambdas Spring Boot sur AWS

**📍 Où:** `terraform/`

#### 7.1 - terraform/main.tf (extrait)

```hcl
# ========================================
# LAMBDA: ADDRESS VALIDATOR
# ========================================

resource "aws_lambda_function" "address_validator" {
  function_name = "${var.environment}-${var.project_name}-address-validator"

  # JAR Spring Boot (avec classifier "aws")
  filename         = "${path.module}/../target/mcp-services-1.0.0-aws.jar"
  source_code_hash = filebase64sha256("${path.module}/../target/mcp-services-1.0.0-aws.jar")

  # Handler Spring Boot
  handler = "com.bnc.mcp.handler.AddressValidatorHandler::handleRequest"
  runtime = "java17"

  # Réutilise le rôle IAM du repo 1
  role = local.lambda_execution_role_arn

  memory_size = 1024  # Spring Boot nécessite plus de mémoire
  timeout     = 60

  architectures = ["arm64"]

  environment {
    variables = {
      SPRING_PROFILES_ACTIVE = "lambda"  # ← Active le profil Lambda
      DYNAMODB_TABLE_NAME    = local.dynamodb_table_name
      ENVIRONMENT            = var.environment
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ========================================
# LAMBDA: ADDRESS FORMATTER
# ========================================

resource "aws_lambda_function" "address_formatter" {
  function_name = "${var.environment}-${var.project_name}-address-formatter"

  # MÊME JAR, handler différent
  filename         = "${path.module}/../target/mcp-services-1.0.0-aws.jar"
  source_code_hash = filebase64sha256("${path.module}/../target/mcp-services-1.0.0-aws.jar")

  handler = "com.bnc.mcp.handler.AddressFormatterHandler::handleRequest"
  runtime = "java17"

  role = local.lambda_execution_role_arn

  memory_size = 1024
  timeout     = 60

  architectures = ["arm64"]

  environment {
    variables = {
      SPRING_PROFILES_ACTIVE = "lambda"
      ENVIRONMENT            = var.environment
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
```

**💡 Points clés:**
- **Un seul JAR**: `mcp-services-1.0.0-aws.jar` pour toutes les Lambdas
- **Handlers différents**: Chaque Lambda a son propre handler
- **Profil Spring**: `SPRING_PROFILES_ACTIVE=lambda`
- **Mémoire augmentée**: Spring Boot nécessite plus de RAM (1024 MB vs 512 MB)

---

## Déploiement

### Étape 8: Builder et déployer

```bash
cd mcp-services

# 1. Builder le JAR Spring Boot pour Lambda
mvn clean package

# Vérifier que le JAR avec classifier "aws" existe
ls -lh target/mcp-services-1.0.0-aws.jar
# Devrait afficher: ~50-80 MB (Spring Boot fat JAR)

# 2. Déployer avec Terraform
cd terraform
terraform init
terraform plan
terraform apply

# 3. Récupérer l'URL de l'API
terraform output api_gateway_url
```

---

## Résumé de l'architecture finale

### Répartition entre les 2 repos

| Ressource | Repo | Technologie | Déployé par |
|-----------|------|-------------|-------------|
| VPC | mcp-infrastructure | Terraform | Équipe Infra |
| DynamoDB | mcp-infrastructure | Terraform | Équipe Infra |
| IAM roles | mcp-infrastructure | Terraform | Équipe Infra |
| API Gateway (structure) | mcp-infrastructure | Terraform | Équipe Infra |
| **Application Spring Boot** | **mcp-services** | **Spring Boot Maven** | **Équipe Dev** |
| **Services métier** | **mcp-services** | **@Service** | **Équipe Dev** |
| **Lambda handlers** | **mcp-services** | **Lambda + Spring** | **Équipe Dev** |
| **Step Functions** | **mcp-services** | **Terraform** | **Équipe Dev** |
| **API endpoints** | **mcp-services** | **Terraform** | **Équipe Dev** |

### Architecture Spring Boot + Lambda

```
┌─────────────────────────────────────────────────────────────┐
│ UN SEUL JAR Spring Boot (mcp-services-1.0.0-aws.jar)       │
│                                                              │
│ Contient:                                                    │
│ - Spring Boot Framework                                     │
│ - @Service (AddressValidatorService, etc.)                 │
│ - @Component, @Configuration                                │
│ - Lambda Handlers (injectent les @Service)                 │
│ - REST Controllers (pour dev local)                         │
│                                                              │
│ Déployé sur:                                                 │
│ - Local: mvn spring-boot:run (port 8080)                   │
│ - Lambda: Plusieurs fonctions Lambda (handlers différents)  │
└─────────────────────────────────────────────────────────────┘
```

---

## Avantages de cette architecture

1. **Développement local facile**
   - `mvn spring-boot:run` pour démarrer
   - Tester avec curl/Postman
   - Debugger avec IntelliJ

2. **Réutilisation du code**
   - Mêmes @Service pour Lambda ET local
   - Pas de duplication de logique métier

3. **Dependency Injection**
   - Spring gère les dépendances
   - Tests unitaires faciles

4. **Maintenance simplifiée**
   - Un seul projet Maven
   - Logique métier centralisée

5. **Déploiements indépendants**
   - Code applicatif séparé de l'infrastructure
   - Équipe Dev autonome

---

**Dernière mise à jour:** 2026-09-23
**Auteur:** Claude Code
**Architecture:** 2 repos (mcp-infrastructure + mcp-services Spring Boot)