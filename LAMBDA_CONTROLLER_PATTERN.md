# Pattern Lambda Controller - Standard BNC/Bancaire

Ce document explique comment implémenter des **Lambda Controllers** pour exposer des workflows via API Gateway, selon les standards bancaires (BNC/MCP).

---

## Table des matières

1. [Pourquoi utiliser un Lambda Controller](#pourquoi-utiliser-un-lambda-controller)
2. [Architecture recommandée](#architecture-recommandée)
3. [Code Java complet - Exemple BNC](#code-java-complet---exemple-bnc)
4. [Validation stricte des données](#validation-stricte-des-données)
5. [Logging structuré (Datadog/Splunk)](#logging-structuré-datadog--splunk)
6. [Gestion des erreurs HTTP](#gestion-des-erreurs-http)
7. [Configuration Terraform](#configuration-terraform)
8. [Tests unitaires](#tests-unitaires)
9. [Métriques et observabilité](#métriques-et-observabilité)
10. [Checklist de production](#checklist-de-production)

---

## Pourquoi utiliser un Lambda Controller

### Approche 1 : Intégration directe (❌ Non recommandé pour banques)

```
API Gateway → Step Functions → Lambda Handlers
```

**Problèmes** :
- ❌ Pas de validation HTTP custom
- ❌ Logging insuffisant pour audit bancaire
- ❌ Pas de contrôle d'accès fin
- ❌ Gestion d'erreur limitée
- ❌ Pas d'enrichissement des données
- ❌ Pas de rate limiting

---

### Approche 2 : Lambda Controller (✅ Recommandé BNC)

```
API Gateway → Lambda Controller → Step Functions → Lambda Handlers
```

**Avantages** :
- ✅ **Validation stricte** : Rejette les requêtes invalides avant Step Functions
- ✅ **Logging exhaustif** : Datadog/Splunk pour audit bancaire
- ✅ **Enrichissement** : Ajoute requestId, userId, timestamp, source
- ✅ **Codes HTTP appropriés** : 400, 401, 403, 404, 500 avec détails
- ✅ **Sécurité** : Authentification, autorisation, rate limiting
- ✅ **Observabilité** : Métriques custom, tracing distribué
- ✅ **Séparation des responsabilités** : Controller ≠ Business logic

---

## Architecture recommandée

### Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FRONT-END (React)                            │
│                    Applications satellites BNC                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ HTTPS
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                        API GATEWAY (AWS)                             │
│  • Authentification AWS_IAM ou Cognito                              │
│  • Rate limiting (throttle)                                          │
│  • CORS                                                              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│              LAMBDA CONTROLLER (Couche Présentation)                 │
│                                                                       │
│  ClientNameUpdateController.java                                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. Extraction des paramètres (path, query, body, headers)   │   │
│  │ 2. Validation stricte (business rules + format)             │   │
│  │ 3. Enrichissement (requestId, userId, timestamp, source)    │   │
│  │ 4. Logging structuré (Datadog/Splunk)                       │   │
│  │ 5. Démarrage Step Functions                                 │   │
│  │ 6. Retour HTTP 202 Accepted (async) ou 200 OK (sync)        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  STEP FUNCTIONS (Orchestration)                      │
│                                                                       │
│  client-name-update.json.tpl                                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 1. ReadClientProfile        (Lambda)                         │   │
│  │ 2. ValidateName             (Lambda)                         │   │
│  │ 3. CheckMDMAE               (Lambda - éviter doublons)       │   │
│  │ 4. UpdateDynamoDB           (Lambda)                         │   │
│  │ 5. SendToFCC                (Lambda - IBM MQ)                │   │
│  │ 6. PublishKafkaEvent        (Lambda)                         │   │
│  │ 7. NotifySuccess            (Lambda)                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      LAMBDA HANDLERS (Métier)                        │
│                                                                       │
│  • ClientProfileReaderHandler.java                                  │
│  • NameValidatorHandler.java                                        │
│  • MdmaeClientHandler.java                                          │
│  • FccSenderHandler.java                                            │
│  • KafkaPublisherHandler.java                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    SYSTÈMES EXTERNES & STORAGE                       │
│                                                                       │
│  • DynamoDB (ClientProfile)                                          │
│  • MDMAE API (Matching/dédoublonnage)                               │
│  • FCC (IBM MQ/JMS - Système legacy)                                │
│  • Kafka (Événements)                                                │
│  • Datadog + Splunk (Logs/Métriques)                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Code Java complet - Exemple BNC

### 1. Lambda Controller principal

**`ClientNameUpdateController.java`**

```java
package com.bnc.mcp.controllers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.bnc.mcp.models.NameUpdateRequest;
import com.bnc.mcp.validators.ClientIdValidator;
import com.bnc.mcp.validators.NameValidator;
import com.bnc.mcp.utils.LoggingUtils;
import com.bnc.mcp.utils.MetricsUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Lambda Controller pour la mise à jour du nom client.
 *
 * Responsabilités:
 * - Validation stricte des inputs HTTP
 * - Enrichissement des données (metadata)
 * - Logging structuré pour Datadog/Splunk
 * - Démarrage du workflow Step Functions
 * - Retour de réponses HTTP appropriées
 *
 * @author Équipe MCP - Banque Nationale
 * @version 1.0
 */
@Slf4j
public class ClientNameUpdateController implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final ObjectMapper objectMapper;
    private final String stateMachineArn;
    private final ClientIdValidator clientIdValidator;
    private final NameValidator nameValidator;
    private final MetricsUtils metricsUtils;

    /**
     * Constructeur par défaut - Utilisé par AWS Lambda
     */
    public ClientNameUpdateController() {
        this.sfnClient = SfnClient.builder().build();
        this.objectMapper = new ObjectMapper();
        this.stateMachineArn = System.getenv("STATE_MACHINE_ARN");
        this.clientIdValidator = new ClientIdValidator();
        this.nameValidator = new NameValidator();
        this.metricsUtils = new MetricsUtils();

        if (stateMachineArn == null || stateMachineArn.isEmpty()) {
            throw new IllegalStateException("STATE_MACHINE_ARN environment variable is required");
        }
    }

    /**
     * Constructeur pour tests unitaires
     */
    public ClientNameUpdateController(SfnClient sfnClient, String stateMachineArn,
                                      ClientIdValidator clientIdValidator,
                                      NameValidator nameValidator,
                                      MetricsUtils metricsUtils) {
        this.sfnClient = sfnClient;
        this.objectMapper = new ObjectMapper();
        this.stateMachineArn = stateMachineArn;
        this.clientIdValidator = clientIdValidator;
        this.nameValidator = nameValidator;
        this.metricsUtils = metricsUtils;
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent request, Context context) {

        String requestId = context.getRequestId();
        long startTime = System.currentTimeMillis();

        // 1. LOGGING INITIAL - Requête reçue
        logRequestReceived(request, requestId);

        try {
            // 2. EXTRACTION - Client ID du path
            String clientId = extractClientId(request);
            if (clientId == null) {
                metricsUtils.incrementCounter("client_name_update.missing_client_id");
                return buildErrorResponse(400, "Missing clientId in path parameters", requestId);
            }

            // 3. VALIDATION - Client ID format
            if (!clientIdValidator.isValid(clientId)) {
                log.warn("INVALID_CLIENT_ID", LoggingUtils.buildLogContext(
                    "event", "VALIDATION_FAILED",
                    "requestId", requestId,
                    "clientId", clientId,
                    "error", "Invalid client ID format"
                ));
                metricsUtils.incrementCounter("client_name_update.invalid_client_id");
                return buildErrorResponse(400, "Invalid client ID format. Expected 9 digits.", requestId);
            }

            // 4. PARSING - Request body
            NameUpdateRequest nameUpdate = parseRequestBody(request.getBody());
            if (nameUpdate == null) {
                metricsUtils.incrementCounter("client_name_update.missing_body");
                return buildErrorResponse(400, "Missing or invalid request body", requestId);
            }

            // 5. VALIDATION - Name fields
            Map<String, String> validationErrors = nameValidator.validate(nameUpdate);
            if (!validationErrors.isEmpty()) {
                log.warn("NAME_VALIDATION_FAILED", LoggingUtils.buildLogContext(
                    "event", "VALIDATION_FAILED",
                    "requestId", requestId,
                    "clientId", clientId,
                    "errors", validationErrors
                ));
                metricsUtils.incrementCounter("client_name_update.validation_failed");
                return buildValidationErrorResponse(validationErrors, requestId);
            }

            // 6. ENRICHISSEMENT - Ajouter metadata
            Map<String, Object> stepFunctionInput = enrichInput(clientId, nameUpdate, request, requestId);

            // 7. DÉMARRAGE - Step Functions execution
            StartExecutionResponse execution = startStepFunctionExecution(stepFunctionInput, clientId);

            // 8. LOGGING SUCCÈS
            log.info("STEP_FUNCTION_STARTED", LoggingUtils.buildLogContext(
                "event", "STEP_FUNCTION_STARTED",
                "requestId", requestId,
                "clientId", clientId,
                "executionArn", execution.executionArn(),
                "stateMachine", stateMachineArn
            ));

            // 9. MÉTRIQUES
            metricsUtils.incrementCounter("client_name_update.success");
            metricsUtils.recordLatency("client_name_update.controller_latency",
                System.currentTimeMillis() - startTime);

            // 10. RETOUR HTTP 202 Accepted
            return buildSuccessResponse(202, Map.of(
                "message", "Name update request accepted and processing",
                "executionArn", execution.executionArn(),
                "clientId", clientId,
                "status", "PROCESSING",
                "requestId", requestId
            ));

        } catch (Exception e) {
            // LOGGING ERREUR
            log.error("CLIENT_NAME_UPDATE_ERROR", LoggingUtils.buildLogContext(
                "event", "CONTROLLER_ERROR",
                "requestId", requestId,
                "error", e.getMessage(),
                "errorType", e.getClass().getSimpleName()
            ), e);

            // MÉTRIQUES
            metricsUtils.incrementCounter("client_name_update.error");
            metricsUtils.recordLatency("client_name_update.controller_latency",
                System.currentTimeMillis() - startTime);

            return buildErrorResponse(500, "Internal server error. Please contact support.", requestId);
        }
    }

    /**
     * Extrait le clientId des path parameters
     */
    private String extractClientId(APIGatewayProxyRequestEvent request) {
        if (request.getPathParameters() == null) {
            return null;
        }
        return request.getPathParameters().get("clientId");
    }

    /**
     * Parse le body JSON en objet NameUpdateRequest
     */
    private NameUpdateRequest parseRequestBody(String body) {
        if (body == null || body.trim().isEmpty()) {
            return null;
        }
        try {
            return objectMapper.readValue(body, NameUpdateRequest.class);
        } catch (Exception e) {
            log.warn("Failed to parse request body", e);
            return null;
        }
    }

    /**
     * Enrichit les données avec metadata pour Step Functions
     */
    private Map<String, Object> enrichInput(String clientId, NameUpdateRequest nameUpdate,
                                            APIGatewayProxyRequestEvent request, String requestId) {
        Map<String, Object> enriched = new HashMap<>();

        // Données métier
        enriched.put("clientId", clientId);
        enriched.put("nameUpdate", nameUpdate);

        // Metadata technique
        enriched.put("requestId", requestId);
        enriched.put("timestamp", Instant.now().toString());
        enriched.put("source", "API_GATEWAY");

        // Metadata utilisateur (si disponible via JWT ou header)
        Map<String, String> requestContext = request.getRequestContext().getIdentity() != null
            ? Map.of(
                "sourceIp", request.getRequestContext().getIdentity().getSourceIp(),
                "userAgent", request.getRequestContext().getIdentity().getUserAgent()
            )
            : Map.of();
        enriched.put("requestContext", requestContext);

        // User ID (extraire du JWT si présent)
        String userId = extractUserId(request);
        if (userId != null) {
            enriched.put("userId", userId);
        }

        return enriched;
    }

    /**
     * Extrait le userId du JWT token (Cognito ou custom)
     */
    private String extractUserId(APIGatewayProxyRequestEvent request) {
        // Exemple pour Cognito
        if (request.getRequestContext().getAuthorizer() != null) {
            Map<String, Object> claims = request.getRequestContext().getAuthorizer().getClaims();
            if (claims != null && claims.containsKey("sub")) {
                return (String) claims.get("sub");
            }
        }

        // Exemple pour header custom
        if (request.getHeaders() != null && request.getHeaders().containsKey("X-User-Id")) {
            return request.getHeaders().get("X-User-Id");
        }

        return null;
    }

    /**
     * Démarre l'exécution Step Functions
     */
    private StartExecutionResponse startStepFunctionExecution(Map<String, Object> input, String clientId)
            throws Exception {

        String inputJson = objectMapper.writeValueAsString(input);
        String executionName = generateExecutionName(clientId);

        StartExecutionRequest executionRequest = StartExecutionRequest.builder()
            .stateMachineArn(stateMachineArn)
            .input(inputJson)
            .name(executionName)
            .build();

        return sfnClient.startExecution(executionRequest);
    }

    /**
     * Génère un nom unique pour l'exécution Step Functions
     */
    private String generateExecutionName(String clientId) {
        // Format: name-update-{clientId}-{timestamp}-{uuid}
        String timestamp = String.valueOf(System.currentTimeMillis());
        String shortUuid = UUID.randomUUID().toString().substring(0, 8);
        return String.format("name-update-%s-%s-%s", clientId, timestamp, shortUuid);
    }

    /**
     * Log la réception de la requête (audit bancaire)
     */
    private void logRequestReceived(APIGatewayProxyRequestEvent request, String requestId) {
        Map<String, Object> logContext = new HashMap<>();
        logContext.put("event", "REQUEST_RECEIVED");
        logContext.put("requestId", requestId);
        logContext.put("httpMethod", request.getHttpMethod());
        logContext.put("path", request.getPath());
        logContext.put("timestamp", Instant.now().toString());

        if (request.getRequestContext() != null && request.getRequestContext().getIdentity() != null) {
            logContext.put("sourceIp", request.getRequestContext().getIdentity().getSourceIp());
            logContext.put("userAgent", request.getRequestContext().getIdentity().getUserAgent());
        }

        if (request.getPathParameters() != null) {
            logContext.put("clientId", request.getPathParameters().get("clientId"));
        }

        log.info("CLIENT_NAME_UPDATE_REQUEST", LoggingUtils.buildLogContext(logContext));
    }

    /**
     * Construit une réponse de succès
     */
    private APIGatewayProxyResponseEvent buildSuccessResponse(int statusCode, Map<String, Object> body) {
        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(statusCode)
                .withHeaders(buildResponseHeaders())
                .withBody(objectMapper.writeValueAsString(body));
        } catch (Exception e) {
            log.error("Error building success response", e);
            return buildErrorResponse(500, "Error building response", UUID.randomUUID().toString());
        }
    }

    /**
     * Construit une réponse d'erreur
     */
    private APIGatewayProxyResponseEvent buildErrorResponse(int statusCode, String message, String requestId) {
        Map<String, Object> errorBody = new HashMap<>();
        errorBody.put("error", message);
        errorBody.put("statusCode", statusCode);
        errorBody.put("requestId", requestId);
        errorBody.put("timestamp", Instant.now().toString());

        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(statusCode)
                .withHeaders(buildResponseHeaders())
                .withBody(objectMapper.writeValueAsString(errorBody));
        } catch (Exception e) {
            log.error("Error building error response", e);
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(500)
                .withHeaders(buildResponseHeaders())
                .withBody("{\"error\":\"Internal server error\"}");
        }
    }

    /**
     * Construit une réponse d'erreur de validation
     */
    private APIGatewayProxyResponseEvent buildValidationErrorResponse(Map<String, String> errors, String requestId) {
        Map<String, Object> errorBody = new HashMap<>();
        errorBody.put("error", "Validation failed");
        errorBody.put("statusCode", 400);
        errorBody.put("validationErrors", errors);
        errorBody.put("requestId", requestId);
        errorBody.put("timestamp", Instant.now().toString());

        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(400)
                .withHeaders(buildResponseHeaders())
                .withBody(objectMapper.writeValueAsString(errorBody));
        } catch (Exception e) {
            log.error("Error building validation error response", e);
            return buildErrorResponse(500, "Error building response", requestId);
        }
    }

    /**
     * Headers HTTP standard
     */
    private Map<String, String> buildResponseHeaders() {
        Map<String, String> headers = new HashMap<>();
        headers.put("Content-Type", "application/json");
        headers.put("Access-Control-Allow-Origin", "*"); // Ajuster selon besoins CORS
        headers.put("Access-Control-Allow-Methods", "PUT, OPTIONS");
        headers.put("Access-Control-Allow-Headers", "Content-Type, Authorization");
        headers.put("X-Content-Type-Options", "nosniff");
        headers.put("X-Frame-Options", "DENY");
        headers.put("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
        return headers;
    }
}
```

---

### 2. Modèle de données

**`NameUpdateRequest.java`**

```java
package com.bnc.mcp.models;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Modèle de données pour une demande de mise à jour de nom client
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class NameUpdateRequest {

    @JsonProperty("firstName")
    private String firstName;

    @JsonProperty("lastName")
    private String lastName;

    @JsonProperty("middleName")
    private String middleName;

    @JsonProperty("preferredName")
    private String preferredName;

    @JsonProperty("nameType")
    private String nameType; // "LEGAL", "PREFERRED", "ALIAS"

    @JsonProperty("reason")
    private String reason; // Raison de la mise à jour (audit)
}
```

---

## Validation stricte des données

### Validators réutilisables

**`ClientIdValidator.java`**

```java
package com.bnc.mcp.validators;

import lombok.extern.slf4j.Slf4j;

import java.util.regex.Pattern;

/**
 * Validateur pour les identifiants clients BNC
 * Format attendu: 9 chiffres (ex: 123456789)
 */
@Slf4j
public class ClientIdValidator {

    private static final Pattern CLIENT_ID_PATTERN = Pattern.compile("^\\d{9}$");

    /**
     * Valide le format de l'identifiant client
     *
     * @param clientId L'identifiant à valider
     * @return true si valide, false sinon
     */
    public boolean isValid(String clientId) {
        if (clientId == null || clientId.trim().isEmpty()) {
            log.debug("Client ID is null or empty");
            return false;
        }

        boolean matches = CLIENT_ID_PATTERN.matcher(clientId.trim()).matches();

        if (!matches) {
            log.debug("Client ID does not match expected pattern: {}", clientId);
        }

        return matches;
    }
}
```

**`NameValidator.java`**

```java
package com.bnc.mcp.validators;

import com.bnc.mcp.models.NameUpdateRequest;
import lombok.extern.slf4j.Slf4j;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Validateur pour les données de nom client
 */
@Slf4j
public class NameValidator {

    private static final int MAX_NAME_LENGTH = 100;
    private static final Pattern NAME_PATTERN = Pattern.compile("^[a-zA-ZÀ-ÿ\\s\\-']+$");
    private static final List<String> VALID_NAME_TYPES = List.of("LEGAL", "PREFERRED", "ALIAS");

    /**
     * Valide les données de nom
     *
     * @param request La requête de mise à jour
     * @return Map vide si valide, sinon map des erreurs par champ
     */
    public Map<String, String> validate(NameUpdateRequest request) {
        Map<String, String> errors = new HashMap<>();

        // 1. Validation firstName
        if (request.getFirstName() == null || request.getFirstName().trim().isEmpty()) {
            errors.put("firstName", "First name is required");
        } else if (request.getFirstName().length() > MAX_NAME_LENGTH) {
            errors.put("firstName", "First name must not exceed " + MAX_NAME_LENGTH + " characters");
        } else if (!NAME_PATTERN.matcher(request.getFirstName()).matches()) {
            errors.put("firstName", "First name contains invalid characters");
        }

        // 2. Validation lastName
        if (request.getLastName() == null || request.getLastName().trim().isEmpty()) {
            errors.put("lastName", "Last name is required");
        } else if (request.getLastName().length() > MAX_NAME_LENGTH) {
            errors.put("lastName", "Last name must not exceed " + MAX_NAME_LENGTH + " characters");
        } else if (!NAME_PATTERN.matcher(request.getLastName()).matches()) {
            errors.put("lastName", "Last name contains invalid characters");
        }

        // 3. Validation middleName (optionnel)
        if (request.getMiddleName() != null && !request.getMiddleName().isEmpty()) {
            if (request.getMiddleName().length() > MAX_NAME_LENGTH) {
                errors.put("middleName", "Middle name must not exceed " + MAX_NAME_LENGTH + " characters");
            } else if (!NAME_PATTERN.matcher(request.getMiddleName()).matches()) {
                errors.put("middleName", "Middle name contains invalid characters");
            }
        }

        // 4. Validation nameType
        if (request.getNameType() != null && !VALID_NAME_TYPES.contains(request.getNameType())) {
            errors.put("nameType", "Invalid name type. Must be one of: " + String.join(", ", VALID_NAME_TYPES));
        }

        // 5. Validation reason (obligatoire pour audit bancaire)
        if (request.getReason() == null || request.getReason().trim().isEmpty()) {
            errors.put("reason", "Reason for name update is required");
        } else if (request.getReason().length() > 500) {
            errors.put("reason", "Reason must not exceed 500 characters");
        }

        return errors;
    }
}
```

---

## Logging structuré (Datadog / Splunk)

### Utilitaire de logging

**`LoggingUtils.java`**

```java
package com.bnc.mcp.utils;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.HashMap;
import java.util.Map;

/**
 * Utilitaire pour générer des logs structurés (JSON)
 * Compatible Datadog et Splunk
 */
public class LoggingUtils {

    private static final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * Construit un contexte de log structuré
     *
     * @param keyValuePairs Paires clé-valeur (nombre pair d'arguments)
     * @return String JSON représentant le contexte
     */
    public static String buildLogContext(Object... keyValuePairs) {
        if (keyValuePairs.length % 2 != 0) {
            throw new IllegalArgumentException("Key-value pairs must be even");
        }

        Map<String, Object> context = new HashMap<>();

        for (int i = 0; i < keyValuePairs.length; i += 2) {
            String key = String.valueOf(keyValuePairs[i]);
            Object value = keyValuePairs[i + 1];
            context.put(key, value);
        }

        return buildLogContext(context);
    }

    /**
     * Construit un contexte de log structuré depuis une Map
     */
    public static String buildLogContext(Map<String, Object> context) {
        try {
            return objectMapper.writeValueAsString(context);
        } catch (JsonProcessingException e) {
            return "{\"error\":\"Failed to serialize log context\"}";
        }
    }
}
```

### Exemples de logs générés

**Requête reçue** :
```json
{
  "event": "REQUEST_RECEIVED",
  "requestId": "abc-123-def",
  "httpMethod": "PUT",
  "path": "/api/clients/123456789/nom",
  "timestamp": "2026-09-23T10:30:00.000Z",
  "sourceIp": "192.168.1.100",
  "userAgent": "Mozilla/5.0...",
  "clientId": "123456789"
}
```

**Validation échouée** :
```json
{
  "event": "VALIDATION_FAILED",
  "requestId": "abc-123-def",
  "clientId": "123456789",
  "errors": {
    "firstName": "First name is required",
    "reason": "Reason for name update is required"
  }
}
```

**Step Functions démarré** :
```json
{
  "event": "STEP_FUNCTION_STARTED",
  "requestId": "abc-123-def",
  "clientId": "123456789",
  "executionArn": "arn:aws:states:ca-central-1:123:execution:...",
  "stateMachine": "arn:aws:states:ca-central-1:123:stateMachine:dev-mcp-client-name-update"
}
```

---

## Gestion des erreurs HTTP

### Codes HTTP utilisés

| Code | Signification | Quand l'utiliser |
|------|--------------|------------------|
| **200 OK** | Succès (sync) | Workflow synchrone terminé avec succès |
| **202 Accepted** | Accepté (async) | Workflow asynchrone démarré, traitement en cours |
| **400 Bad Request** | Requête invalide | Validation échouée, champs manquants/invalides |
| **401 Unauthorized** | Non authentifié | Token JWT manquant ou invalide |
| **403 Forbidden** | Non autorisé | Token valide mais permissions insuffisantes |
| **404 Not Found** | Ressource introuvable | Client ID n'existe pas |
| **409 Conflict** | Conflit | Mise à jour concurrente détectée |
| **429 Too Many Requests** | Trop de requêtes | Rate limit dépassé |
| **500 Internal Server Error** | Erreur serveur | Erreur non gérée côté serveur |
| **503 Service Unavailable** | Service indisponible | Système temporairement hors service |

### Exemples de réponses

**Succès (202 Accepted)** :
```json
{
  "message": "Name update request accepted and processing",
  "executionArn": "arn:aws:states:...:execution:name-update-123456789-1234567890-abc123de",
  "clientId": "123456789",
  "status": "PROCESSING",
  "requestId": "abc-123-def"
}
```

**Validation échouée (400 Bad Request)** :
```json
{
  "error": "Validation failed",
  "statusCode": 400,
  "validationErrors": {
    "firstName": "First name is required",
    "lastName": "Last name contains invalid characters",
    "reason": "Reason for name update is required"
  },
  "requestId": "abc-123-def",
  "timestamp": "2026-09-23T10:30:00.000Z"
}
```

**Erreur serveur (500 Internal Server Error)** :
```json
{
  "error": "Internal server error. Please contact support.",
  "statusCode": 500,
  "requestId": "abc-123-def",
  "timestamp": "2026-09-23T10:30:00.000Z"
}
```

---

## Configuration Terraform

### 1. Ajouter la Lambda Controller

**`environments/dev/main.tf`**

```hcl
module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn

  functions = {
    # ... autres Lambdas existantes ...

    # ← LAMBDA CONTROLLER
    client-name-update-controller = {
      handler          = "com.bnc.mcp.controllers.ClientNameUpdateController::handleRequest"
      runtime          = "java17"
      memory_size      = 512
      timeout          = 10  # Court timeout, juste pour démarrer Step Functions
      environment_vars = {
        STATE_MACHINE_ARN = module.step_functions.state_machine_arns["client-name-update"]
        LOG_LEVEL         = "INFO"
        DATADOG_API_KEY   = var.datadog_api_key  # Si Datadog utilisé
      }
      vpc_config = null  # Pas besoin de VPC pour appeler Step Functions
    }
  }
}
```

### 2. Configurer API Gateway

**`modules/api-gateway/main.tf`**

```hcl
# Ressource: /api/clients/{clientId}/nom
resource "aws_api_gateway_resource" "nom" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "nom"
}

# Méthode: PUT /api/clients/{clientId}/nom
resource "aws_api_gateway_method" "put_nom" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.nom.id
  http_method   = "PUT"
  authorization = "AWS_IAM"  # Ou "COGNITO_USER_POOLS" si Cognito

  request_parameters = {
    "method.request.path.clientId" = true
  }

  request_validator_id = aws_api_gateway_request_validator.body_validator.id
}

# Intégration: Lambda Proxy
resource "aws_api_gateway_integration" "put_nom_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"  # Lambda Proxy = passe tout l'événement HTTP
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.lambda_function_arns["client-name-update-controller"]}/invocations"
}

# Réponse: 202 Accepted
resource "aws_api_gateway_method_response" "put_nom_202" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method
  status_code = "202"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Réponse: 400 Bad Request
resource "aws_api_gateway_method_response" "put_nom_400" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method
  status_code = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Réponse: 500 Internal Server Error
resource "aws_api_gateway_method_response" "put_nom_500" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.put_nom.http_method
  status_code = "500"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Permission: API Gateway → Lambda
resource "aws_lambda_permission" "api_gateway_invoke_controller" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_arns["client-name-update-controller"]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# CORS: OPTIONS method
resource "aws_api_gateway_method" "options_nom" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.nom.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_nom" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.options_nom.http_method

  type = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_nom_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.options_nom.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_nom_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.nom.id
  http_method = aws_api_gateway_method.options_nom.http_method
  status_code = aws_api_gateway_method_response.options_nom_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}
```

### 3. Permissions IAM

**`modules/iam/main.tf`**

```hcl
resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.environment}-${var.project_name}-lambda-execution-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ... autres permissions existantes ...

      # Permission pour démarrer Step Functions
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution",
          "states:DescribeExecution",
          "states:StopExecution"
        ]
        Resource = values(var.state_machine_arns)
      },

      # CloudWatch Logs (pour tous les Lambdas)
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
```

---

## Tests unitaires

**`ClientNameUpdateControllerTest.java`**

```java
package com.bnc.mcp.controllers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.bnc.mcp.validators.ClientIdValidator;
import com.bnc.mcp.validators.NameValidator;
import com.bnc.mcp.utils.MetricsUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class ClientNameUpdateControllerTest {

    @Mock
    private SfnClient sfnClient;

    @Mock
    private Context context;

    @Mock
    private MetricsUtils metricsUtils;

    private ClientNameUpdateController controller;
    private ObjectMapper objectMapper;

    private static final String STATE_MACHINE_ARN = "arn:aws:states:ca-central-1:123:stateMachine:test";

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);

        ClientIdValidator clientIdValidator = new ClientIdValidator();
        NameValidator nameValidator = new NameValidator();

        controller = new ClientNameUpdateController(
            sfnClient,
            STATE_MACHINE_ARN,
            clientIdValidator,
            nameValidator,
            metricsUtils
        );

        objectMapper = new ObjectMapper();

        when(context.getRequestId()).thenReturn("test-request-id");
    }

    @Test
    void testSuccessfulNameUpdate() throws Exception {
        // Arrange
        APIGatewayProxyRequestEvent request = buildValidRequest();

        StartExecutionResponse mockResponse = StartExecutionResponse.builder()
            .executionArn("arn:aws:states:ca-central-1:123:execution:test:exec-123")
            .build();

        when(sfnClient.startExecution(any(StartExecutionRequest.class)))
            .thenReturn(mockResponse);

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(202, response.getStatusCode());

        Map<String, Object> body = objectMapper.readValue(response.getBody(), Map.class);
        assertEquals("Name update request accepted and processing", body.get("message"));
        assertEquals("arn:aws:states:ca-central-1:123:execution:test:exec-123", body.get("executionArn"));
        assertEquals("123456789", body.get("clientId"));
        assertEquals("PROCESSING", body.get("status"));

        verify(sfnClient, times(1)).startExecution(any(StartExecutionRequest.class));
        verify(metricsUtils).incrementCounter("client_name_update.success");
    }

    @Test
    void testMissingClientId() {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent()
            .withPathParameters(Map.of()) // Client ID absent
            .withBody(buildValidBody());

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(400, response.getStatusCode());
        assertTrue(response.getBody().contains("Missing clientId"));
        verify(sfnClient, never()).startExecution(any());
        verify(metricsUtils).incrementCounter("client_name_update.missing_client_id");
    }

    @Test
    void testInvalidClientIdFormat() {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent()
            .withPathParameters(Map.of("clientId", "ABC123")) // Format invalide
            .withBody(buildValidBody());

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(400, response.getStatusCode());
        assertTrue(response.getBody().contains("Invalid client ID format"));
        verify(sfnClient, never()).startExecution(any());
        verify(metricsUtils).incrementCounter("client_name_update.invalid_client_id");
    }

    @Test
    void testMissingRequestBody() {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent()
            .withPathParameters(Map.of("clientId", "123456789"))
            .withBody(null); // Body absent

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(400, response.getStatusCode());
        assertTrue(response.getBody().contains("Missing or invalid request body"));
        verify(sfnClient, never()).startExecution(any());
        verify(metricsUtils).incrementCounter("client_name_update.missing_body");
    }

    @Test
    void testValidationFailure_MissingFirstName() throws Exception {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent()
            .withPathParameters(Map.of("clientId", "123456789"))
            .withBody("{\"lastName\":\"Dupont\",\"reason\":\"Correction\"}"); // firstName manquant

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(400, response.getStatusCode());

        Map<String, Object> body = objectMapper.readValue(response.getBody(), Map.class);
        assertEquals("Validation failed", body.get("error"));

        Map<String, String> validationErrors = (Map<String, String>) body.get("validationErrors");
        assertTrue(validationErrors.containsKey("firstName"));
        assertEquals("First name is required", validationErrors.get("firstName"));

        verify(sfnClient, never()).startExecution(any());
        verify(metricsUtils).incrementCounter("client_name_update.validation_failed");
    }

    @Test
    void testStepFunctionExecutionParameters() throws Exception {
        // Arrange
        APIGatewayProxyRequestEvent request = buildValidRequest();

        StartExecutionResponse mockResponse = StartExecutionResponse.builder()
            .executionArn("arn:aws:states:ca-central-1:123:execution:test:exec-123")
            .build();

        when(sfnClient.startExecution(any(StartExecutionRequest.class)))
            .thenReturn(mockResponse);

        // Act
        controller.handleRequest(request, context);

        // Assert - Vérifier les paramètres passés à Step Functions
        ArgumentCaptor<StartExecutionRequest> captor = ArgumentCaptor.forClass(StartExecutionRequest.class);
        verify(sfnClient).startExecution(captor.capture());

        StartExecutionRequest executionRequest = captor.getValue();
        assertEquals(STATE_MACHINE_ARN, executionRequest.stateMachineArn());

        // Vérifier que l'input contient les données enrichies
        String inputJson = executionRequest.input();
        Map<String, Object> input = objectMapper.readValue(inputJson, Map.class);

        assertEquals("123456789", input.get("clientId"));
        assertNotNull(input.get("nameUpdate"));
        assertEquals("test-request-id", input.get("requestId"));
        assertNotNull(input.get("timestamp"));
        assertEquals("API_GATEWAY", input.get("source"));
    }

    @Test
    void testInternalServerError() {
        // Arrange
        APIGatewayProxyRequestEvent request = buildValidRequest();

        when(sfnClient.startExecution(any(StartExecutionRequest.class)))
            .thenThrow(new RuntimeException("Step Functions error"));

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(500, response.getStatusCode());
        assertTrue(response.getBody().contains("Internal server error"));
        verify(metricsUtils).incrementCounter("client_name_update.error");
    }

    // Helper methods

    private APIGatewayProxyRequestEvent buildValidRequest() {
        return new APIGatewayProxyRequestEvent()
            .withPathParameters(Map.of("clientId", "123456789"))
            .withBody(buildValidBody())
            .withRequestContext(new APIGatewayProxyRequestEvent.ProxyRequestContext()
                .withRequestId("test-request-id")
                .withIdentity(new APIGatewayProxyRequestEvent.RequestIdentity()
                    .withSourceIp("192.168.1.100")
                    .withUserAgent("Test-Agent")));
    }

    private String buildValidBody() {
        return "{\n" +
               "  \"firstName\": \"Jean\",\n" +
               "  \"lastName\": \"Dupont\",\n" +
               "  \"middleName\": \"Paul\",\n" +
               "  \"preferredName\": \"JP\",\n" +
               "  \"nameType\": \"LEGAL\",\n" +
               "  \"reason\": \"Correction suite à mariage\"\n" +
               "}";
    }
}
```

---

## Métriques et observabilité

### Utilitaire Datadog (optionnel)

**`MetricsUtils.java`**

```java
package com.bnc.mcp.utils;

import lombok.extern.slf4j.Slf4j;

import java.util.HashMap;
import java.util.Map;

/**
 * Utilitaire pour envoyer des métriques custom à Datadog
 */
@Slf4j
public class MetricsUtils {

    /**
     * Incrémente un compteur
     *
     * @param metricName Nom de la métrique (ex: "client_name_update.success")
     */
    public void incrementCounter(String metricName) {
        incrementCounter(metricName, 1, Map.of());
    }

    /**
     * Incrémente un compteur avec tags
     *
     * @param metricName Nom de la métrique
     * @param value Valeur à incrémenter
     * @param tags Tags Datadog (ex: environment=dev, service=mcp)
     */
    public void incrementCounter(String metricName, long value, Map<String, String> tags) {
        // Log structuré pour Datadog
        Map<String, Object> metric = new HashMap<>();
        metric.put("metric_type", "counter");
        metric.put("metric_name", metricName);
        metric.put("value", value);
        metric.put("tags", tags);

        log.info("METRIC", LoggingUtils.buildLogContext(metric));

        // Si SDK Datadog utilisé, envoyer directement
        // StatsDClient statsd = ...
        // statsd.incrementCounter(metricName, tags);
    }

    /**
     * Enregistre une latence (durée)
     *
     * @param metricName Nom de la métrique
     * @param durationMs Durée en millisecondes
     */
    public void recordLatency(String metricName, long durationMs) {
        Map<String, Object> metric = new HashMap<>();
        metric.put("metric_type", "histogram");
        metric.put("metric_name", metricName);
        metric.put("value", durationMs);
        metric.put("unit", "milliseconds");

        log.info("METRIC", LoggingUtils.buildLogContext(metric));

        // Si SDK Datadog utilisé
        // statsd.recordExecutionTime(metricName, durationMs);
    }
}
```

### Métriques recommandées

| Métrique | Type | Description |
|----------|------|-------------|
| `client_name_update.success` | Counter | Nombre de mises à jour réussies |
| `client_name_update.missing_client_id` | Counter | Client ID manquant |
| `client_name_update.invalid_client_id` | Counter | Client ID invalide |
| `client_name_update.missing_body` | Counter | Body manquant |
| `client_name_update.validation_failed` | Counter | Validation échouée |
| `client_name_update.error` | Counter | Erreurs serveur |
| `client_name_update.controller_latency` | Histogram | Latence du controller (ms) |

---

## Checklist de production

Avant de déployer un Lambda Controller en production :

### Code Java

- [ ] Controller implémente `RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent>`
- [ ] Validation stricte de tous les inputs (path, query, body, headers)
- [ ] Gestion d'erreur exhaustive (try-catch global)
- [ ] Logging structuré (JSON) à chaque étape clé
- [ ] Enrichissement des données (requestId, userId, timestamp, source)
- [ ] Codes HTTP appropriés (200, 202, 400, 401, 403, 404, 500)
- [ ] Headers de sécurité (CORS, CSP, X-Frame-Options, etc.)
- [ ] Tests unitaires couvrant tous les scénarios (succès + erreurs)
- [ ] Tests d'intégration avec Step Functions

### Terraform

- [ ] Lambda controller créée dans `environments/dev/main.tf`
- [ ] Timeout approprié (généralement 10s pour un controller)
- [ ] Memory optimisée (512 MB généralement suffisant)
- [ ] Variables d'environnement configurées (`STATE_MACHINE_ARN`, etc.)
- [ ] API Gateway configuré avec Lambda Proxy integration (`AWS_PROXY`)
- [ ] Méthodes HTTP appropriées (PUT, POST, GET, DELETE, OPTIONS)
- [ ] CORS configuré si nécessaire
- [ ] Permissions IAM : Lambda → Step Functions
- [ ] Permissions IAM : API Gateway → Lambda
- [ ] CloudWatch Logs activés

### Sécurité

- [ ] Authentification configurée (AWS_IAM, Cognito, JWT)
- [ ] Autorisation vérifiée (userId, permissions)
- [ ] Rate limiting configuré (throttle, burst)
- [ ] Validation anti-injection (SQL, XSS, etc.)
- [ ] Secrets stockés dans AWS Secrets Manager (jamais hardcodés)
- [ ] Logs ne contiennent pas de données sensibles
- [ ] Headers de sécurité HTTP appropriés

### Observabilité

- [ ] Logs structurés (JSON) pour Datadog/Splunk
- [ ] Métriques custom envoyées (compteurs, latences)
- [ ] Request ID tracé dans tous les logs
- [ ] Alarmes CloudWatch configurées (erreurs, latence)
- [ ] Dashboard Datadog/Splunk créé
- [ ] Tracing distribué configuré (X-Ray ou Datadog APM)

### Documentation

- [ ] OpenAPI/Swagger spec créée
- [ ] README mis à jour avec exemple de requête
- [ ] Runbook d'opérations créé
- [ ] Diagramme d'architecture à jour
- [ ] Variables d'environnement documentées

---

## Résumé

### Pattern Lambda Controller BNC

```
┌──────────────────────────────────────────────────────────────┐
│                    RESPONSABILITÉS                            │
├──────────────────────────────────────────────────────────────┤
│ 1. VALIDATION   → Rejeter requêtes invalides (400)           │
│ 2. LOGGING      → Audit complet (Datadog/Splunk)             │
│ 3. ENRICHMENT   → Ajouter metadata (requestId, userId, etc.)  │
│ 4. ORCHESTRATION → Démarrer Step Functions                   │
│ 5. HTTP RESPONSE → Retourner réponse appropriée (202, 400...)│
└──────────────────────────────────────────────────────────────┘
```

### Avantages pour la BNC

✅ **Qualité des données** : Validation stricte avant traitement
✅ **Traçabilité** : Logs exhaustifs pour audit bancaire
✅ **Sécurité** : Authentification, autorisation, validation anti-injection
✅ **Observabilité** : Métriques custom, tracing distribué
✅ **Découplage** : API HTTP ≠ Step Functions ≠ Business logic
✅ **Évolutivité** : Facile d'ajouter validation, transformation, etc.
✅ **Conformité** : Répond aux standards bancaires

---

**Dernière mise à jour** : 2026-09-23
**Auteur** : Claude Code
**Version** : 1.0