# 🚀 Guide Complet: Ajouter un Nouveau Endpoint à l'API MCP

Ce guide explique **étape par étape** comment ajouter un nouveau endpoint à l'API MCP, depuis l'implémentation métier jusqu'à l'exposition dans Swagger UI.

## 📋 Exemple: Mise à Jour de la Date de Naissance

Nous allons créer un endpoint `PUT /api/clients/{clientId}/birthdate` qui permet de mettre à jour la date de naissance d'un client.

---

## 📖 Table des Matières

1. [Vue d'Ensemble de l'Architecture](#1-vue-densemble-de-larchitecture)
2. [Étape 1: Implémentation Métier (Lambda Java)](#étape-1-implémentation-métier-lambda-java)
3. [Étape 2: Définition du Workflow Step Functions](#étape-2-définition-du-workflow-step-functions)
4. [Étape 3: Configuration Terraform Lambda](#étape-3-configuration-terraform-lambda)
5. [Étape 4: Configuration Terraform Step Functions](#étape-4-configuration-terraform-step-functions)
6. [Étape 5: Configuration API Gateway](#étape-5-configuration-api-gateway)
7. [Étape 6: Mise à Jour Swagger/OpenAPI](#étape-6-mise-à-jour-swaggeropenapi)
8. [Étape 7: Build et Upload des JARs](#étape-7-build-et-upload-des-jars)
9. [Étape 8: Déploiement Terraform](#étape-8-déploiement-terraform)
10. [Étape 9: Tests et Validation](#étape-9-tests-et-validation)
11. [Checklist Complète](#checklist-complète)

---

## 1. Vue d'Ensemble de l'Architecture

### Flux Complet

```
┌──────────────────────────────────────────────────────────────┐
│ CLIENT                                                        │
│ PUT /api/clients/TEST123/birthdate                          │
│ Body: {"newBirthdate": "1990-05-15", "reason": "CORRECTION"}│
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ API GATEWAY (Terraform: api-gateway/main.tf)                │
│ - Reçoit la requête HTTP                                     │
│ - Valide les paramètres                                      │
│ - Transforme en input Step Functions (VTL)                  │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ STEP FUNCTIONS (Terraform: step-functions/)                 │
│ State Machine: client_birthdate_update                      │
│ - Orchestre les étapes du workflow                          │
└──────────────────────────────────────────────────────────────┘
                           ↓
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ Lambda 1:     │  │ Lambda 2:     │  │ Lambda 3:     │
│ Validation    │→ │ Update        │→ │ Event         │
│               │  │ DynamoDB      │  │ Publishing    │
└───────────────┘  └───────────────┘  └───────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ DynamoDB Table: dev-ClientProfile                           │
│ - Stockage persistant                                        │
└──────────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│ Kafka Topic: client.birthdate.updated                       │
│ - Propagation de l'événement                                │
└──────────────────────────────────────────────────────────────┘
```

---

## Étape 1: Implémentation Métier (Lambda Java)

### 1.1 Créer le Handler de Validation

**Fichier**: `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateValidationHandler.java`

```java
package com.bnc.mcp.orchestration.handler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.GetItemRequest;
import software.amazon.awssdk.services.dynamodb.model.GetItemResponse;

import java.time.LocalDate;
import java.time.Period;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.HashMap;
import java.util.Map;

import static net.logstash.logback.argument.StructuredArguments.keyValue;

/**
 * Étape 1 — Valide la nouvelle date de naissance.
 *
 * Vérifie:
 * - Que le client existe
 * - Que la date est au format valide (YYYY-MM-DD)
 * - Que la date est cohérente (pas dans le futur, âge raisonnable)
 */
@Component
public class BirthdateValidationHandler implements McpHandler {

    private static final Logger log = LoggerFactory.getLogger(BirthdateValidationHandler.class);
    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ISO_LOCAL_DATE;

    private final DynamoDbClient dynamoDb;
    private final String tableName;

    public BirthdateValidationHandler(
            DynamoDbClient dynamoDb,
            @Value("${dynamodb.table.name}") String tableName) {
        this.dynamoDb = dynamoDb;
        this.tableName = tableName;
    }

    @Override
    public String functionName() {
        return "BirthdateValidationLambda";
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        String clientId = String.valueOf(input.get("clientId"));
        String newBirthdate = String.valueOf(input.get("newBirthdate"));

        log.info("Validation de la date de naissance",
                keyValue("event", "VALIDATION_BIRTHDATE_START"),
                keyValue("clientId", clientId),
                keyValue("newBirthdate", newBirthdate));

        // 1. Vérifier que le client existe
        GetItemRequest getItemRequest = GetItemRequest.builder()
                .tableName(tableName)
                .key(Map.of("clientId", software.amazon.awssdk.services.dynamodb.model.AttributeValue.builder()
                        .s(clientId)
                        .build()))
                .build();

        GetItemResponse response = dynamoDb.getItem(getItemRequest);

        if (!response.hasItem()) {
            String errorMsg = "Client introuvable dans MCP : " + clientId;
            log.error(errorMsg,
                    keyValue("event", "CLIENT_NOT_FOUND"),
                    keyValue("clientId", clientId));
            throw new RuntimeException("Validation failed: " + errorMsg);
        }

        // Récupérer l'ancienne date de naissance
        String currentBirthdate = response.item().containsKey("dateOfBirth")
                ? response.item().get("dateOfBirth").s()
                : null;

        // 2. Valider le format de la nouvelle date
        LocalDate newDate;
        try {
            newDate = LocalDate.parse(newBirthdate, DATE_FORMAT);
        } catch (DateTimeParseException e) {
            String errorMsg = "Format de date invalide. Attendu: YYYY-MM-DD";
            log.error(errorMsg,
                    keyValue("event", "INVALID_DATE_FORMAT"),
                    keyValue("newBirthdate", newBirthdate));
            throw new RuntimeException("Validation failed: " + errorMsg);
        }

        // 3. Vérifier que la date n'est pas dans le futur
        if (newDate.isAfter(LocalDate.now())) {
            String errorMsg = "La date de naissance ne peut pas être dans le futur";
            log.error(errorMsg,
                    keyValue("event", "BIRTHDATE_IN_FUTURE"),
                    keyValue("newBirthdate", newBirthdate));
            throw new RuntimeException("Validation failed: " + errorMsg);
        }

        // 4. Vérifier l'âge (doit être entre 0 et 150 ans)
        int age = Period.between(newDate, LocalDate.now()).getYears();
        if (age < 0 || age > 150) {
            String errorMsg = "Âge calculé non valide : " + age + " ans";
            log.error(errorMsg,
                    keyValue("event", "INVALID_AGE"),
                    keyValue("age", age));
            throw new RuntimeException("Validation failed: " + errorMsg);
        }

        log.info("Validation réussie",
                keyValue("event", "VALIDATION_BIRTHDATE_SUCCESS"),
                keyValue("clientId", clientId),
                keyValue("currentBirthdate", currentBirthdate),
                keyValue("newBirthdate", newBirthdate),
                keyValue("age", age));

        // Retourner les données enrichies pour les prochaines étapes
        Map<String, Object> output = new HashMap<>(input);
        output.put("currentBirthdate", currentBirthdate);
        output.put("validatedBirthdate", newBirthdate);
        output.put("age", age);
        output.put("validationStatus", "PASSED");

        return output;
    }
}
```

### 1.2 Créer le Handler de Mise à Jour

**Fichier**: `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateUpdateHandler.java`

```java
package com.bnc.mcp.orchestration.handler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.UpdateItemRequest;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import static net.logstash.logback.argument.StructuredArguments.keyValue;

/**
 * Étape 2 — Met à jour la date de naissance dans DynamoDB.
 */
@Component
public class BirthdateUpdateHandler implements McpHandler {

    private static final Logger log = LoggerFactory.getLogger(BirthdateUpdateHandler.class);

    private final DynamoDbClient dynamoDb;
    private final String tableName;

    public BirthdateUpdateHandler(
            DynamoDbClient dynamoDb,
            @Value("${dynamodb.table.name}") String tableName) {
        this.dynamoDb = dynamoDb;
        this.tableName = tableName;
    }

    @Override
    public String functionName() {
        return "BirthdateUpdateLambda";
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        String clientId = String.valueOf(input.get("clientId"));
        String newBirthdate = String.valueOf(input.get("validatedBirthdate"));
        String reason = String.valueOf(input.getOrDefault("reason", "NON_PRECISE"));

        log.info("Mise à jour de la date de naissance",
                keyValue("event", "UPDATE_BIRTHDATE_START"),
                keyValue("clientId", clientId),
                keyValue("newBirthdate", newBirthdate));

        String timestamp = Instant.now().toString();

        UpdateItemRequest updateRequest = UpdateItemRequest.builder()
                .tableName(tableName)
                .key(Map.of("clientId", AttributeValue.builder().s(clientId).build()))
                .updateExpression("SET dateOfBirth = :newDate, updatedAt = :timestamp, updateReason = :reason")
                .expressionAttributeValues(Map.of(
                        ":newDate", AttributeValue.builder().s(newBirthdate).build(),
                        ":timestamp", AttributeValue.builder().s(timestamp).build(),
                        ":reason", AttributeValue.builder().s(reason).build()
                ))
                .build();

        dynamoDb.updateItem(updateRequest);

        log.info("Date de naissance mise à jour avec succès",
                keyValue("event", "UPDATE_BIRTHDATE_SUCCESS"),
                keyValue("clientId", clientId),
                keyValue("newBirthdate", newBirthdate));

        Map<String, Object> output = new HashMap<>(input);
        output.put("updatedAt", timestamp);
        output.put("updateStatus", "COMPLETED");

        return output;
    }
}
```

### 1.3 Créer le Handler de Publication d'Événement

**Fichier**: `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateEventPublisher.java`

```java
package com.bnc.mcp.orchestration.handler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

import static net.logstash.logback.argument.StructuredArguments.keyValue;

/**
 * Étape 3 — Publie un événement Kafka pour propager le changement.
 */
@Component
public class BirthdateEventPublisher implements McpHandler {

    private static final Logger log = LoggerFactory.getLogger(BirthdateEventPublisher.class);

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final String topicName;
    private final boolean useMockMode;

    public BirthdateEventPublisher(
            @Autowired(required = false) KafkaTemplate<String, Object> kafkaTemplate,
            @Value("${mcp.kafka.topic.birthdate:client.birthdate.updated}") String topicName) {
        this.kafkaTemplate = kafkaTemplate;
        this.topicName = topicName;
        this.useMockMode = (kafkaTemplate == null);

        if (useMockMode) {
            log.warn("KAFKA MOCK MODE ENABLED - Events will be logged only");
        }
    }

    @Override
    public String functionName() {
        return "BirthdateEventPublisherLambda";
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        String clientId = String.valueOf(input.get("clientId"));
        String correlationId = String.valueOf(input.getOrDefault("correlationId", "N/A"));

        Map<String, Object> event = new HashMap<>();
        event.put("eventType", "BIRTHDATE_UPDATED");
        event.put("correlationId", correlationId);
        event.put("clientId", clientId);
        event.put("previousBirthdate", input.get("currentBirthdate"));
        event.put("newBirthdate", input.get("validatedBirthdate"));
        event.put("age", input.get("age"));
        event.put("reason", input.getOrDefault("reason", "NON_PRECISE"));
        event.put("source", input.getOrDefault("source", "mcp-api"));
        event.put("timestamp", input.get("updatedAt"));

        if (useMockMode) {
            log.warn("KAFKA MOCK MODE - Event would have been published",
                    keyValue("event", "EVENT_MOCK_PUBLISH"),
                    keyValue("topic", topicName),
                    keyValue("payload", event));
        } else {
            kafkaTemplate.send(topicName, clientId, event).get();
            log.info("Événement publié sur Kafka",
                    keyValue("event", "EVENT_PUBLISHED"),
                    keyValue("topic", topicName),
                    keyValue("clientId", clientId));
        }

        Map<String, Object> output = new HashMap<>(input);
        output.put("eventPublished", true);
        output.put("kafkaTopic", topicName);
        output.put("mockMode", useMockMode);

        return output;
    }
}
```

### 1.4 Enregistrer les Fonctions dans LambdaFunctionConfiguration

**Fichier**: `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/lambda/LambdaFunctionConfiguration.java`

Ajouter les nouvelles fonctions:

```java
@Bean
public Function<Map<String, Object>, Map<String, Object>> birthdateValidationFunction(
        BirthdateValidationHandler handler) {
    return input -> {
        try {
            return (Map<String, Object>) handler.handle(input);
        } catch (Exception e) {
            log.error("Erreur validation birthdate", e);
            throw new RuntimeException(e);
        }
    };
}

@Bean
public Function<Map<String, Object>, Map<String, Object>> birthdateUpdateFunction(
        BirthdateUpdateHandler handler) {
    return input -> {
        try {
            return (Map<String, Object>) handler.handle(input);
        } catch (Exception e) {
            log.error("Erreur update birthdate", e);
            throw new RuntimeException(e);
        }
    };
}

@Bean
public Function<Map<String, Object>, Map<String, Object>> birthdateEventFunction(
        BirthdateEventPublisher handler) {
    return input -> {
        try {
            return (Map<String, Object>) handler.handle(input);
        } catch (Exception e) {
            log.error("Erreur event birthdate", e);
            throw new RuntimeException(e);
        }
    };
}
```

---

## Étape 2: Définition du Workflow Step Functions

### 2.1 Créer le Template de State Machine

**Fichier**: `mcp-infrastructure/modules/step-functions/definitions/client-birthdate-update.json.tpl`

```json
{
  "Comment": "Workflow de mise à jour de la date de naissance d'un client",
  "StartAt": "ValidateBirthdate",
  "States": {
    "ValidateBirthdate": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${birthdate_validation_arn}",
        "Payload.$": "$"
      },
      "ResultSelector": {
        "output.$": "$.Payload"
      },
      "ResultPath": "$.validationResult",
      "OutputPath": "$.validationResult.output",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.TooManyRequestsException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "ValidationFailed"
        }
      ],
      "Next": "UpdateBirthdate"
    },

    "UpdateBirthdate": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${birthdate_update_arn}",
        "Payload.$": "$"
      },
      "ResultSelector": {
        "output.$": "$.Payload"
      },
      "ResultPath": "$.updateResult",
      "OutputPath": "$.updateResult.output",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "UpdateFailed"
        }
      ],
      "Next": "PublishEvent"
    },

    "PublishEvent": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${birthdate_event_arn}",
        "Payload.$": "$"
      },
      "ResultSelector": {
        "output.$": "$.Payload"
      },
      "ResultPath": "$.publishResult",
      "OutputPath": "$.publishResult.output",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Success"
    },

    "Success": {
      "Type": "Succeed"
    },

    "ValidationFailed": {
      "Type": "Fail",
      "Error": "ValidationError",
      "Cause": "La validation de la date de naissance a échoué"
    },

    "UpdateFailed": {
      "Type": "Fail",
      "Error": "UpdateError",
      "Cause": "La mise à jour de la date de naissance a échoué"
    }
  }
}
```

---

## Étape 3: Configuration Terraform Lambda

### 3.1 Ajouter les Nouvelles Lambda Functions

**Fichier**: `mcp-infrastructure/environments/dev/main.tf`

Dans la section `module "lambda"`, ajouter les 3 nouvelles fonctions:

```hcl
module "lambda" {
  source = "../../modules/lambda"

  # ... configuration existante ...

  functions = {
    # ... fonctions existantes ...

    # Nouvelle fonction 1: Validation de la date de naissance
    birthdate_validator = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateValidationFunction"
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }

    # Nouvelle fonction 2: Mise à jour DynamoDB
    birthdate_updater = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateUpdateFunction"
        DYNAMODB_TABLE                   = module.dynamodb.table_name
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }

    # Nouvelle fonction 3: Publication d'événement
    birthdate_event_publisher = {
      handler     = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
      runtime     = "java21"
      memory_size = var.lambda_memory_size
      timeout     = var.lambda_timeout
      environment_vars = {
        SPRING_PROFILES_ACTIVE           = "lambda"
        SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateEventFunction"
        KAFKA_TOPIC                      = "client.birthdate.updated"
        LOG_LEVEL                        = "INFO"
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
  }
}
```

---

## Étape 4: Configuration Terraform Step Functions

### 4.1 Ajouter la Nouvelle State Machine

**Fichier**: `mcp-infrastructure/environments/dev/main.tf`

Dans la section `module "step_functions"`, ajouter:

```hcl
module "step_functions" {
  source = "../../modules/step-functions"

  # ... configuration existante ...

  state_machines = {
    # ... state machines existantes ...

    # Nouvelle state machine pour birthdate update
    client_birthdate_update = {
      definition_template = "client-birthdate-update.json.tpl"
      role_arn           = module.iam.stepfunctions_execution_role_arn

      template_vars = {
        birthdate_validation_arn = module.lambda.function_arns["birthdate_validator"]
        birthdate_update_arn     = module.lambda.function_arns["birthdate_updater"]
        birthdate_event_arn      = module.lambda.function_arns["birthdate_event_publisher"]
      }
    }
  }
}
```

---

## Étape 5: Configuration API Gateway

### 5.1 Ajouter le Endpoint dans API Gateway

**Fichier**: `mcp-infrastructure/modules/api-gateway/birthdate.tf`

Créer un nouveau fichier pour les ressources birthdate:

```hcl
# /api/clients/{clientId}/birthdate resource
resource "aws_api_gateway_resource" "birthdate" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "birthdate"
}

# PUT /api/clients/{clientId}/birthdate method
resource "aws_api_gateway_method" "put_birthdate" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.birthdate.id
  http_method   = "PUT"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.clientId" = true
  }
}

# Integration avec Step Functions
resource "aws_api_gateway_integration" "put_birthdate" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.birthdate.id
  http_method = aws_api_gateway_method.put_birthdate.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials             = aws_iam_role.api_stepfunctions.arn

  request_templates = {
    "application/json" = <<EOF
{
  "stateMachineArn": "${var.birthdate_state_machine_arn}",
  "input": "{\"clientId\": \"$util.escapeJavaScript($input.params('clientId'))\", \"newBirthdate\": \"$util.escapeJavaScript($input.path('$.newBirthdate'))\", \"reason\": \"$util.escapeJavaScript($input.path('$.reason'))\"}"
}
EOF
  }

  passthrough_behavior = "NEVER"
}

# Method response
resource "aws_api_gateway_method_response" "put_birthdate_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.birthdate.id
  http_method = aws_api_gateway_method.put_birthdate.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response
resource "aws_api_gateway_integration_response" "put_birthdate" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.birthdate.id
  http_method = aws_api_gateway_method.put_birthdate.http_method
  status_code = aws_api_gateway_method_response.put_birthdate_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Birthdate update initiated",
  "executionArn": $input.json('$.executionArn')
}
EOF
  }

  depends_on = [aws_api_gateway_integration.put_birthdate]
}
```

### 5.2 Ajouter la Variable pour State Machine ARN

**Fichier**: `mcp-infrastructure/modules/api-gateway/variables.tf`

```hcl
variable "birthdate_state_machine_arn" {
  description = "ARN of the birthdate update state machine"
  type        = string
  default     = ""
}
```

### 5.3 Passer l'ARN depuis le Module Principal

**Fichier**: `mcp-infrastructure/environments/dev/main.tf`

```hcl
module "api_gateway" {
  source = "../../modules/api-gateway"

  # ... configuration existante ...

  # Ajouter l'ARN de la state machine birthdate
  birthdate_state_machine_arn = module.step_functions.state_machine_arns["client_birthdate_update"]
}
```

### 5.4 Mettre à Jour les Dépendances de Déploiement

**Fichier**: `mcp-infrastructure/modules/api-gateway/main.tf`

```hcl
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.stepfunctions,
    aws_api_gateway_integration_response.stepfunctions,
    aws_api_gateway_method_response.put_nom_200,
    aws_api_gateway_integration.get_docs,
    aws_api_gateway_integration_response.get_swagger_json,
    # Ajouter les nouvelles dépendances:
    aws_api_gateway_integration.put_birthdate,
    aws_api_gateway_integration_response.put_birthdate
  ]

  # ... reste de la configuration ...
}
```

---

## Étape 6: Mise à Jour Swagger/OpenAPI

### 6.1 Ajouter l'Endpoint dans la Spécification OpenAPI

**Fichier**: `mcp-infrastructure/modules/api-gateway/openapi-spec.json.tpl`

Dans la section `paths`, ajouter:

```json
"/api/clients/{clientId}/birthdate": {
  "put": {
    "tags": ["Clients"],
    "summary": "Mise à jour de la date de naissance d'un client",
    "description": "Met à jour la date de naissance d'un client existant. Cette opération déclenche un workflow Step Functions qui:\n\n1. Valide la nouvelle date de naissance\n2. Vérifie la cohérence (format, âge raisonnable)\n3. Met à jour le profil dans DynamoDB\n4. Publie un événement Kafka",
    "operationId": "updateClientBirthdate",
    "parameters": [
      {
        "name": "clientId",
        "in": "path",
        "description": "Identifiant unique du client",
        "required": true,
        "schema": {
          "type": "string",
          "example": "TEST123"
        }
      }
    ],
    "requestBody": {
      "description": "Nouvelle date de naissance",
      "required": true,
      "content": {
        "application/json": {
          "schema": {
            "$ref": "#/components/schemas/UpdateBirthdateRequest"
          },
          "examples": {
            "correction": {
              "summary": "Correction d'une date de naissance erronée",
              "value": {
                "newBirthdate": "1990-05-15",
                "reason": "CORRECTION"
              }
            },
            "autre": {
              "summary": "Autre raison",
              "value": {
                "newBirthdate": "1985-12-31",
                "reason": "AUTRE"
              }
            }
          }
        }
      }
    },
    "responses": {
      "200": {
        "description": "Demande de mise à jour acceptée et workflow démarré",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/UpdateBirthdateResponse"
            },
            "example": {
              "message": "Birthdate update initiated",
              "executionArn": "arn:aws:states:${region}:123456789012:execution:${environment}-mcp-client_birthdate_update:abc123-def456"
            }
          }
        }
      },
      "400": {
        "description": "Requête invalide (format de date incorrect, date dans le futur, etc.)",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorResponse"
            },
            "example": {
              "error": "BadRequest",
              "message": "Format de date invalide. Attendu: YYYY-MM-DD"
            }
          }
        }
      },
      "404": {
        "description": "Client non trouvé",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorResponse"
            },
            "example": {
              "error": "NotFound",
              "message": "Client INVALID123 introuvable dans MCP"
            }
          }
        }
      }
    }
  }
}
```

### 6.2 Ajouter les Schémas dans components/schemas

```json
"UpdateBirthdateRequest": {
  "type": "object",
  "required": ["newBirthdate"],
  "properties": {
    "newBirthdate": {
      "type": "string",
      "format": "date",
      "description": "Nouvelle date de naissance au format YYYY-MM-DD",
      "example": "1990-05-15",
      "pattern": "^\\d{4}-\\d{2}-\\d{2}$"
    },
    "reason": {
      "type": "string",
      "description": "Raison de la modification",
      "enum": [
        "CORRECTION",
        "AUTRE"
      ],
      "example": "CORRECTION"
    }
  }
},
"UpdateBirthdateResponse": {
  "type": "object",
  "properties": {
    "message": {
      "type": "string",
      "description": "Message de confirmation",
      "example": "Birthdate update initiated"
    },
    "executionArn": {
      "type": "string",
      "description": "ARN de l'exécution Step Functions démarrée",
      "example": "arn:aws:states:ca-central-1:123456789012:execution:dev-mcp-client_birthdate_update:abc123-def456"
    }
  }
}
```

---

## Étape 7: Build et Upload des JARs

### 7.1 Builder le Projet Java

```bash
cd ~/Downloads/mcp-local/mcp-orchestration

# Clean et build
mvn clean package -DskipTests

# Vérifier que les JARs sont créés
ls -lh target/*Lambda.jar
```

### 7.2 Uploader vers S3

```bash
cd /path/to/mcp-infrastructure

# Utiliser le script d'upload automatique
./scripts/upload-lambda-jars.sh ~/Downloads/mcp-local/mcp-orchestration/target
```

**OU manuellement**:

```bash
# Upload les 3 nouveaux JARs
aws s3 cp target/BirthdateValidationLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp target/BirthdateUpdateLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp target/BirthdateEventPublisherLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1

# Vérifier
aws s3 ls s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
```

---

## Étape 8: Déploiement Terraform

### 8.1 Valider la Configuration

```bash
cd environments/dev

# Initialiser (si nécessaire)
terraform init

# Valider la syntaxe
terraform validate

# Voir le plan
terraform plan -var-file=dev.tfvars
```

### 8.2 Déployer les Lambdas

```bash
# Déployer uniquement les Lambda functions
terraform apply -var-file=dev.tfvars -target=module.lambda -auto-approve
```

### 8.3 Déployer Step Functions

```bash
# Déployer la state machine
terraform apply -var-file=dev.tfvars -target=module.step_functions -auto-approve
```

### 8.4 Déployer API Gateway

```bash
# Déployer l'API Gateway avec le nouveau endpoint
terraform apply -var-file=dev.tfvars -target=module.api_gateway -auto-approve

# Forcer un nouveau déploiement pour activer les changements
terraform apply -var-file=dev.tfvars \
  -target=module.api_gateway \
  -replace=module.api_gateway.aws_api_gateway_deployment.main \
  -auto-approve
```

### 8.5 Déploiement Complet (Alternative)

```bash
# Appliquer tous les changements d'un coup
terraform apply -var-file=dev.tfvars -auto-approve
```

---

## Étape 9: Tests et Validation

### 9.1 Tester via Swagger UI

1. **Ouvrir Swagger UI**:
   ```
   https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/docs
   ```

2. **Rafraîchir la page** (Ctrl+F5)

3. **Tester le nouvel endpoint**:
   - Cliquer sur `PUT /api/clients/{clientId}/birthdate`
   - Cliquer sur "Try it out"
   - Remplir:
     - **clientId**: `TEST123`
     - **Request body**:
       ```json
       {
         "newBirthdate": "1990-05-15",
         "reason": "CORRECTION"
       }
       ```
   - Cliquer sur "Execute"
   - Vérifier la réponse:
     ```json
     {
       "message": "Birthdate update initiated",
       "executionArn": "arn:aws:states:..."
     }
     ```

### 9.2 Tester via cURL

```bash
# Test de base
curl -X PUT "https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/birthdate" \
  -H "Content-Type: application/json" \
  -d '{
    "newBirthdate": "1990-05-15",
    "reason": "CORRECTION"
  }' | jq .

# Test avec date invalide (dans le futur)
curl -X PUT "https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/birthdate" \
  -H "Content-Type: application/json" \
  -d '{
    "newBirthdate": "2030-01-01",
    "reason": "CORRECTION"
  }' | jq .

# Test avec format invalide
curl -X PUT "https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/birthdate" \
  -H "Content-Type: application/json" \
  -d '{
    "newBirthdate": "15-05-1990",
    "reason": "CORRECTION"
  }' | jq .
```

### 9.3 Vérifier l'Exécution Step Functions

```bash
# Lister les exécutions récentes
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw state_machine_arns | jq -r '.client_birthdate_update') \
  --max-results 5 \
  --region ca-central-1

# Voir les détails d'une exécution
aws stepfunctions describe-execution \
  --execution-arn "[EXECUTION-ARN]" \
  --region ca-central-1 | jq '{status, startDate, stopDate}'

# Voir l'historique complet
aws stepfunctions get-execution-history \
  --execution-arn "[EXECUTION-ARN]" \
  --region ca-central-1 | jq .
```

### 9.4 Vérifier DynamoDB

```bash
# Lire le profil client
aws dynamodb get-item \
  --table-name dev-ClientProfile \
  --key '{"clientId":{"S":"TEST123"}}' \
  --region ca-central-1 | jq '.Item'
```

### 9.5 Vérifier les Logs CloudWatch

```bash
# Logs de validation
aws logs tail /aws/lambda/dev-mcp-birthdate_validator --follow --region ca-central-1

# Logs de mise à jour
aws logs tail /aws/lambda/dev-mcp-birthdate_updater --follow --region ca-central-1

# Logs de publication d'événement
aws logs tail /aws/lambda/dev-mcp-birthdate_event_publisher --follow --region ca-central-1

# Logs Step Functions
aws logs tail /aws/states/dev-mcp-client_birthdate_update --follow --region ca-central-1
```

---

## Checklist Complète

Cochez chaque étape au fur et à mesure:

### ✅ Implémentation Java

- [ ] Créer `BirthdateValidationHandler.java`
- [ ] Créer `BirthdateUpdateHandler.java`
- [ ] Créer `BirthdateEventPublisher.java`
- [ ] Enregistrer les 3 fonctions dans `LambdaFunctionConfiguration.java`
- [ ] Ajouter les tests unitaires (optionnel mais recommandé)

### ✅ Définition Step Functions

- [ ] Créer `client-birthdate-update.json.tpl`
- [ ] Définir les states: Validation → Update → Publish
- [ ] Ajouter error handling et retry logic

### ✅ Configuration Terraform

- [ ] Ajouter les 3 Lambda functions dans `environments/dev/main.tf`
- [ ] Ajouter la state machine dans `module.step_functions`
- [ ] Créer `modules/api-gateway/birthdate.tf`
- [ ] Ajouter la variable `birthdate_state_machine_arn`
- [ ] Mettre à jour les dépendances de déploiement

### ✅ Documentation Swagger

- [ ] Ajouter l'endpoint dans `openapi-spec.json.tpl`
- [ ] Créer les schémas `UpdateBirthdateRequest` et `UpdateBirthdateResponse`
- [ ] Ajouter des exemples de requêtes

### ✅ Build et Déploiement

- [ ] Build Maven: `mvn clean package`
- [ ] Upload JARs vers S3
- [ ] `terraform validate`
- [ ] `terraform plan`
- [ ] `terraform apply`
- [ ] Forcer redéploiement API Gateway

### ✅ Tests

- [ ] Tester via Swagger UI
- [ ] Tester via cURL
- [ ] Vérifier Step Functions execution
- [ ] Vérifier DynamoDB
- [ ] Vérifier CloudWatch Logs
- [ ] Tests de cas d'erreur (date invalide, client inexistant, etc.)

### ✅ Documentation et Commit

- [ ] Documenter le nouveau endpoint dans README
- [ ] Commit du code Java
- [ ] Commit de l'infrastructure Terraform
- [ ] Push vers GitHub

---

## 📝 Résumé des Fichiers Créés/Modifiés

### Nouveaux Fichiers Java (3)
1. `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateValidationHandler.java`
2. `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateUpdateHandler.java`
3. `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/handler/BirthdateEventPublisher.java`

### Fichiers Java Modifiés (1)
1. `mcp-orchestration/src/main/java/com/bnc/mcp/orchestration/lambda/LambdaFunctionConfiguration.java`

### Nouveaux Fichiers Terraform (2)
1. `mcp-infrastructure/modules/step-functions/definitions/client-birthdate-update.json.tpl`
2. `mcp-infrastructure/modules/api-gateway/birthdate.tf`

### Fichiers Terraform Modifiés (3)
1. `mcp-infrastructure/environments/dev/main.tf`
2. `mcp-infrastructure/modules/api-gateway/variables.tf`
3. `mcp-infrastructure/modules/api-gateway/openapi-spec.json.tpl`

### Total
- **Nouveaux fichiers**: 5
- **Fichiers modifiés**: 4

---

## 🎓 Conseils et Bonnes Pratiques

### 1. Nommage Cohérent

- **Lambda functions**: `[resource]_[action]` (ex: `birthdate_validator`)
- **Handlers Java**: `[Resource][Action]Handler` (ex: `BirthdateValidationHandler`)
- **State machines**: `client_[resource]_update` (ex: `client_birthdate_update`)
- **API paths**: `/api/clients/{id}/[resource]` (ex: `/api/clients/{id}/birthdate`)

### 2. Gestion des Erreurs

Toujours implémenter:
- Retry logic dans Step Functions
- Catch blocks pour error handling
- Logs structurés avec corrélation IDs
- Messages d'erreur clairs pour l'utilisateur

### 3. Tests

Tester **tous** les scénarios:
- ✅ Cas nominal (succès)
- ❌ Client inexistant
- ❌ Format de données invalide
- ❌ Valeurs hors limites
- ❌ Timeouts
- ❌ Erreurs DynamoDB/Kafka

### 4. Monitoring

Configurer:
- CloudWatch Alarms pour les erreurs Lambda
- CloudWatch Alarms pour les échecs Step Functions
- Dashboards CloudWatch pour visualiser les métriques
- X-Ray tracing pour le debugging

### 5. Déploiement Progressif

1. **DEV**: Déployer et tester complètement
2. **STAGING**: Valider avec données réelles
3. **PROD**: Déployer pendant une fenêtre de maintenance

---

## 🔗 Ressources Utiles

- [Documentation Step Functions](https://docs.aws.amazon.com/step-functions/)
- [Documentation API Gateway](https://docs.aws.amazon.com/apigateway/)
- [OpenAPI Specification 3.0](https://swagger.io/specification/)
- [Spring Cloud Function](https://spring.io/projects/spring-cloud-function)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)

---

**Dernière mise à jour**: 2026-09-29
**Version**: 1.0.0