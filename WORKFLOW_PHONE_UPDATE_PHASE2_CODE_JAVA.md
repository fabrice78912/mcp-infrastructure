# Workflow Phone Update - Phase 2 : Code Java Complet

## 📋 Vue d'ensemble Phase 2

Cette phase contient le code Java complet pour toutes les Lambdas du workflow de mise à jour de téléphone.

---

## Étape 2.3 : Lambda Controller

### Fichier : `src/main/java/com/bnc/mcp/controllers/ClientPhoneUpdateController.java`

```java
package com.bnc.mcp.controllers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

/**
 * Lambda Controller - Point d'entrée pour mise à jour numéro de téléphone
 *
 * Responsabilités :
 * 1. Valider la requête HTTP
 * 2. Enrichir avec metadata
 * 3. Démarrer le workflow Step Functions
 * 4. Retourner HTTP 202 Accepted
 */
@Slf4j
public class ClientPhoneUpdateController
    implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final String stateMachineArn;
    private final ObjectMapper objectMapper;

    public ClientPhoneUpdateController() {
        this.sfnClient = SfnClient.builder().build();
        this.stateMachineArn = System.getenv("STATE_MACHINE_ARN");
        this.objectMapper = new ObjectMapper();

        log.info("ClientPhoneUpdateController initialized with state machine: {}", stateMachineArn);
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(
            APIGatewayProxyRequestEvent request,
            Context context) {

        String requestId = context.getRequestId();
        log.info("Received phone update request. RequestId: {}", requestId);

        try {
            // 1. Extraire clientId depuis path parameters
            Map<String, String> pathParams = request.getPathParameters();
            if (pathParams == null || !pathParams.containsKey("clientId")) {
                log.error("Missing clientId in path parameters");
                return buildErrorResponse(400, "Missing clientId in path");
            }
            String clientId = pathParams.get("clientId");

            // 2. Parser le body
            Map<String, Object> body = objectMapper.readValue(request.getBody(), Map.class);
            if (!body.containsKey("phoneNumber")) {
                log.error("Missing phoneNumber in request body");
                return buildErrorResponse(400, "Missing phoneNumber in body");
            }

            String phoneNumber = (String) body.get("phoneNumber");
            String country = (String) body.getOrDefault("country", "CA");

            // 3. Validation basique
            if (phoneNumber == null || phoneNumber.trim().isEmpty()) {
                log.error("Phone number is empty");
                return buildErrorResponse(400, "Phone number cannot be empty");
            }

            // 4. Enrichir avec metadata
            Map<String, Object> stepFunctionInput = new HashMap<>();
            stepFunctionInput.put("clientId", clientId);
            stepFunctionInput.put("phoneNumber", phoneNumber);
            stepFunctionInput.put("country", country);
            stepFunctionInput.put("requestId", requestId);
            stepFunctionInput.put("timestamp", Instant.now().toString());

            // Metadata
            Map<String, String> metadata = new HashMap<>();
            metadata.put("userId", extractUserId(request));
            metadata.put("userAgent", request.getHeaders().getOrDefault("User-Agent", "unknown"));
            metadata.put("sourceIp", request.getHeaders().getOrDefault("X-Forwarded-For", "unknown"));
            stepFunctionInput.put("metadata", metadata);

            // 5. Démarrer Step Functions
            StartExecutionResponse execution = startStepFunctionWorkflow(stepFunctionInput, clientId);

            log.info("Step Functions workflow started. ExecutionArn: {}", execution.executionArn());

            // 6. Retourner HTTP 202 Accepted
            return buildSuccessResponse(202, Map.of(
                "message", "Phone update request accepted",
                "executionArn", execution.executionArn(),
                "status", "PROCESSING",
                "requestId", requestId
            ));

        } catch (Exception e) {
            log.error("Error processing phone update request", e);
            return buildErrorResponse(500, "Internal server error: " + e.getMessage());
        }
    }

    /**
     * Démarre le workflow Step Functions
     */
    private StartExecutionResponse startStepFunctionWorkflow(
            Map<String, Object> input,
            String clientId) throws Exception {

        String inputJson = objectMapper.writeValueAsString(input);
        String executionName = String.format("phone-update-%s-%d",
            clientId, System.currentTimeMillis());

        StartExecutionRequest request = StartExecutionRequest.builder()
            .stateMachineArn(stateMachineArn)
            .input(inputJson)
            .name(executionName)
            .build();

        return sfnClient.startExecution(request);
    }

    /**
     * Extrait le userId depuis les headers d'authentification
     */
    private String extractUserId(APIGatewayProxyRequestEvent request) {
        Map<String, String> headers = request.getHeaders();
        if (headers != null && headers.containsKey("X-User-Id")) {
            return headers.get("X-User-Id");
        }
        return "anonymous";
    }

    /**
     * Construit une réponse HTTP de succès
     */
    private APIGatewayProxyResponseEvent buildSuccessResponse(
            int statusCode,
            Map<String, Object> body) {

        try {
            APIGatewayProxyResponseEvent response = new APIGatewayProxyResponseEvent();
            response.setStatusCode(statusCode);
            response.setBody(objectMapper.writeValueAsString(body));
            response.setHeaders(Map.of(
                "Content-Type", "application/json",
                "X-Request-Id", body.getOrDefault("requestId", "unknown").toString()
            ));
            return response;
        } catch (Exception e) {
            log.error("Error building success response", e);
            return buildErrorResponse(500, "Error building response");
        }
    }

    /**
     * Construit une réponse HTTP d'erreur
     */
    private APIGatewayProxyResponseEvent buildErrorResponse(int statusCode, String message) {
        APIGatewayProxyResponseEvent response = new APIGatewayProxyResponseEvent();
        response.setStatusCode(statusCode);
        response.setBody(String.format("{\"error\": \"%s\"}", message));
        response.setHeaders(Map.of("Content-Type", "application/json"));
        return response;
    }
}
```

---

## Étape 2.4 : Lambda Handler - Phone Validator

### Fichier : `src/main/java/com/bnc/mcp/handlers/PhoneValidatorHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.PhoneValidationResult;
import com.bnc.mcp.services.PhoneValidationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * Lambda Handler - Valide le format et la légitimité d'un numéro de téléphone
 */
@Slf4j
public class PhoneValidatorHandler implements RequestHandler<Map<String, Object>, PhoneValidationResult> {

    private final PhoneValidationService phoneValidationService;
    private final ObjectMapper objectMapper;

    public PhoneValidatorHandler() {
        this.phoneValidationService = new PhoneValidationService();
        this.objectMapper = new ObjectMapper();
    }

    @Override
    public PhoneValidationResult handleRequest(Map<String, Object> input, Context context) {
        log.info("Validating phone number. RequestId: {}", context.getRequestId());

        try {
            String phoneNumber = (String) input.get("phoneNumber");
            String country = (String) input.getOrDefault("country", "CA");
            String clientId = (String) input.get("clientId");

            log.info("Validating phone: {} for country: {}, clientId: {}", phoneNumber, country, clientId);

            // Valider le numéro de téléphone
            PhoneValidationResult result = phoneValidationService.validatePhone(phoneNumber, country);

            log.info("Validation result: isValid={}, normalizedPhone={}",
                result.isValid(), result.getNormalizedPhone());

            return result;

        } catch (Exception e) {
            log.error("Error validating phone number", e);

            PhoneValidationResult errorResult = new PhoneValidationResult();
            errorResult.setValid(false);
            errorResult.addError("VALIDATION_ERROR", "An error occurred during validation: " + e.getMessage());
            return errorResult;
        }
    }
}
```

---

## Étape 2.5 : Lambda Handler - Check Phone History

### Fichier : `src/main/java/com/bnc/mcp/handlers/CheckPhoneHistoryHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.PhoneHistoryCheck;
import com.bnc.mcp.services.PhoneHistoryService;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * Lambda Handler - Vérifie l'historique des changements de téléphone pour détecter fraude
 */
@Slf4j
public class CheckPhoneHistoryHandler implements RequestHandler<Map<String, Object>, PhoneHistoryCheck> {

    private final PhoneHistoryService phoneHistoryService;

    public CheckPhoneHistoryHandler() {
        this.phoneHistoryService = new PhoneHistoryService();
    }

    @Override
    public PhoneHistoryCheck handleRequest(Map<String, Object> input, Context context) {
        log.info("Checking phone history. RequestId: {}", context.getRequestId());

        try {
            String clientId = (String) input.get("clientId");
            String newPhoneNumber = (String) input.get("newPhoneNumber");
            String currentPhoneNumber = (String) input.get("currentPhoneNumber");

            log.info("Checking history for clientId: {}, current: {}, new: {}",
                clientId, currentPhoneNumber, newPhoneNumber);

            // Analyser l'historique
            PhoneHistoryCheck result = phoneHistoryService.analyzePhoneHistory(
                clientId,
                currentPhoneNumber,
                newPhoneNumber
            );

            log.info("History check result: suspiciousScore={}, changeCount={}",
                result.getSuspiciousScore(), result.getChangeCount());

            return result;

        } catch (Exception e) {
            log.error("Error checking phone history", e);

            PhoneHistoryCheck errorResult = new PhoneHistoryCheck();
            errorResult.setSuspiciousScore(0.0);
            errorResult.setChangeCount(0);
            errorResult.setReason("Error analyzing history: " + e.getMessage());
            return errorResult;
        }
    }
}
```

---

## Étape 2.6 : Lambda Handler - Send OTP SMS

### Fichier : `src/main/java/com/bnc/mcp/handlers/SendOTPSMSHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.SMSClient;
import com.bnc.mcp.models.OTPCode;
import com.bnc.mcp.services.OTPService;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * Lambda Handler - Envoie un code OTP par SMS au nouveau numéro
 */
@Slf4j
public class SendOTPSMSHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final OTPService otpService;
    private final SMSClient smsClient;

    public SendOTPSMSHandler() {
        this.otpService = new OTPService();
        this.smsClient = new SMSClient();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        log.info("Sending OTP SMS. RequestId: {}", context.getRequestId());

        try {
            String phoneNumber = (String) input.get("phoneNumber");
            String clientId = (String) input.get("clientId");
            String executionId = (String) input.get("executionId");

            log.info("Generating OTP for phone: {}, clientId: {}", phoneNumber, clientId);

            // 1. Générer le code OTP
            OTPCode otpCode = otpService.generateOTP(clientId, executionId);

            // 2. Envoyer SMS
            String message = String.format(
                "BNC: Votre code de vérification est %s. Valide pendant 5 minutes. Ne partagez pas ce code.",
                otpCode.getCode()
            );

            boolean smsSent = smsClient.sendSMS(phoneNumber, message);

            if (!smsSent) {
                log.error("Failed to send OTP SMS to {}", phoneNumber);
                throw new RuntimeException("SMS delivery failed");
            }

            log.info("OTP SMS sent successfully to {}", phoneNumber);

            return Map.of(
                "otpSent", true,
                "phoneNumber", phoneNumber,
                "expiresAt", otpCode.getExpiresAt().toString()
            );

        } catch (Exception e) {
            log.error("Error sending OTP SMS", e);
            throw new RuntimeException("Failed to send OTP: " + e.getMessage(), e);
        }
    }
}
```

---

## Étape 2.7 : Lambda Handler - Check OTP Status

### Fichier : `src/main/java/com/bnc/mcp/handlers/CheckOTPStatusHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.services.OTPService;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * Lambda Handler - Vérifie si l'OTP a été validé par le client
 */
@Slf4j
public class CheckOTPStatusHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final OTPService otpService;

    public CheckOTPStatusHandler() {
        this.otpService = new OTPService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        log.info("Checking OTP status. RequestId: {}", context.getRequestId());

        try {
            String clientId = (String) input.get("clientId");
            String executionId = (String) input.get("executionId");

            log.info("Checking OTP status for clientId: {}, executionId: {}", clientId, executionId);

            // Vérifier si l'OTP a été validé
            boolean isValidated = otpService.isOTPValidated(clientId, executionId);

            log.info("OTP validation status: {}", isValidated);

            return Map.of(
                "isValidated", isValidated,
                "clientId", clientId,
                "executionId", executionId
            );

        } catch (Exception e) {
            log.error("Error checking OTP status", e);

            // En cas d'erreur, on considère que l'OTP n'est pas validé
            return Map.of(
                "isValidated", false,
                "error", e.getMessage()
            );
        }
    }
}
```

---

## Étape 2.8 : Lambda Handler - Phone MDMAE Client

### Fichier : `src/main/java/com/bnc/mcp/handlers/PhoneMDMAEClientHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.MDMAEClient;
import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

/**
 * Lambda Handler - Met à jour le numéro de téléphone dans MDMAE
 */
@Slf4j
public class PhoneMDMAEClientHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final MDMAEClient mdmaeClient;

    public PhoneMDMAEClientHandler() {
        this.mdmaeClient = new MDMAEClient();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        log.info("Updating phone in MDMAE. RequestId: {}", context.getRequestId());

        try {
            String clientId = (String) input.get("clientId");
            String oldPhoneNumber = (String) input.get("oldPhoneNumber");
            String newPhoneNumber = (String) input.get("newPhoneNumber");
            String updatedBy = (String) input.get("updatedBy");

            log.info("MDMAE update - clientId: {}, old: {}, new: {}",
                clientId, oldPhoneNumber, newPhoneNumber);

            // Créer la requête MDMAE
            MDMAEPhoneUpdateRequest request = MDMAEPhoneUpdateRequest.builder()
                .clientId(clientId)
                .oldPhoneNumber(oldPhoneNumber)
                .newPhoneNumber(newPhoneNumber)
                .updatedBy(updatedBy)
                .build();

            // Appeler MDMAE
            Map<String, Object> result = mdmaeClient.updatePhoneNumber(request);

            log.info("MDMAE update successful. TransactionId: {}", result.get("transactionId"));

            return Map.of(
                "status", "SUCCESS",
                "transactionId", result.get("transactionId"),
                "timestamp", result.get("timestamp")
            );

        } catch (Exception e) {
            log.error("Error updating phone in MDMAE", e);

            // Distinguer erreur temporaire vs permanente
            if (e.getMessage().contains("timeout") || e.getMessage().contains("503")) {
                throw new RuntimeException("MDMAETemporaryError: " + e.getMessage(), e);
            } else {
                throw new RuntimeException("MDMAEPermanentError: " + e.getMessage(), e);
            }
        }
    }
}
```

---

## Étape 2.9 : Models (POJOs)

### Fichier : `src/main/java/com/bnc/mcp/models/PhoneValidationResult.java`

```java
package com.bnc.mcp.models;

import lombok.Data;

import java.util.ArrayList;
import java.util.List;

@Data
public class PhoneValidationResult {
    private boolean isValid;
    private String normalizedPhone;
    private String country;
    private String phoneType; // MOBILE, FIXED_LINE, VOIP
    private List<ValidationError> errors = new ArrayList<>();
    private List<String> warnings = new ArrayList<>();

    public void addError(String code, String message) {
        this.errors.add(new ValidationError(code, message));
    }

    public void addWarning(String warning) {
        this.warnings.add(warning);
    }

    @Data
    public static class ValidationError {
        private final String code;
        private final String message;
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/models/PhoneHistoryCheck.java`

```java
package com.bnc.mcp.models;

import lombok.Data;

import java.util.ArrayList;
import java.util.List;

@Data
public class PhoneHistoryCheck {
    private double suspiciousScore; // 0.0 à 1.0
    private int changeCount; // Nombre de changements dans les 30 derniers jours
    private String reason;
    private List<PhoneHistoryEntry> history = new ArrayList<>();

    @Data
    public static class PhoneHistoryEntry {
        private String phoneNumber;
        private String changedAt;
        private String changedBy;
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/models/OTPCode.java`

```java
package com.bnc.mcp.models;

import lombok.Builder;
import lombok.Data;

import java.time.Instant;

@Data
@Builder
public class OTPCode {
    private String code; // 6 chiffres
    private String clientId;
    private String executionId;
    private Instant createdAt;
    private Instant expiresAt; // 5 minutes après createdAt
    private boolean validated;
    private Instant validatedAt;
}
```

### Fichier : `src/main/java/com/bnc/mcp/models/MDMAEPhoneUpdateRequest.java`

```java
package com.bnc.mcp.models;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class MDMAEPhoneUpdateRequest {
    private String clientId;
    private String oldPhoneNumber;
    private String newPhoneNumber;
    private String updatedBy;
}
```

---

## Étape 2.10 : Services

### Fichier : `src/main/java/com/bnc/mcp/services/PhoneValidationService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.models.PhoneValidationResult;
import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber;
import lombok.extern.slf4j.Slf4j;

@Slf4j
public class PhoneValidationService {

    private final PhoneNumberUtil phoneNumberUtil;

    public PhoneValidationService() {
        this.phoneNumberUtil = PhoneNumberUtil.getInstance();
    }

    public PhoneValidationResult validatePhone(String phoneNumber, String countryCode) {
        PhoneValidationResult result = new PhoneValidationResult();
        result.setCountry(countryCode);

        try {
            // Parser le numéro avec libphonenumber
            Phonenumber.PhoneNumber parsedNumber = phoneNumberUtil.parse(phoneNumber, countryCode);

            // Vérifier si le numéro est valide
            boolean isValid = phoneNumberUtil.isValidNumber(parsedNumber);

            if (!isValid) {
                result.setValid(false);
                result.addError("INVALID_FORMAT", "Phone number format is invalid for country " + countryCode);
                return result;
            }

            // Normaliser le format
            String normalizedPhone = phoneNumberUtil.format(
                parsedNumber,
                PhoneNumberUtil.PhoneNumberFormat.E164
            );

            // Déterminer le type de téléphone
            PhoneNumberUtil.PhoneNumberType type = phoneNumberUtil.getNumberType(parsedNumber);
            String phoneType = type.name();

            // Vérifier si c'est un VoIP (suspect pour fraude)
            if (type == PhoneNumberUtil.PhoneNumberType.VOIP) {
                result.addWarning("Phone number is VoIP - potential fraud risk");
            }

            result.setValid(true);
            result.setNormalizedPhone(normalizedPhone);
            result.setPhoneType(phoneType);

            log.info("Phone validation successful: {} -> {}", phoneNumber, normalizedPhone);

        } catch (NumberParseException e) {
            log.error("Failed to parse phone number: {}", phoneNumber, e);
            result.setValid(false);
            result.addError("PARSE_ERROR", "Failed to parse phone number: " + e.getMessage());
        }

        return result;
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/services/PhoneHistoryService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.clients.DynamoDBClient;
import com.bnc.mcp.models.PhoneHistoryCheck;
import lombok.extern.slf4j.Slf4j;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

@Slf4j
public class PhoneHistoryService {

    private final DynamoDBClient dynamoDBClient;

    public PhoneHistoryService() {
        this.dynamoDBClient = new DynamoDBClient();
    }

    public PhoneHistoryCheck analyzePhoneHistory(
            String clientId,
            String currentPhone,
            String newPhone) {

        PhoneHistoryCheck result = new PhoneHistoryCheck();

        try {
            // Lire l'historique des 30 derniers jours
            Instant thirtyDaysAgo = Instant.now().minus(30, ChronoUnit.DAYS);
            List<PhoneHistoryCheck.PhoneHistoryEntry> history =
                dynamoDBClient.getPhoneHistory(clientId, thirtyDaysAgo);

            result.setHistory(history);
            result.setChangeCount(history.size());

            // Calculer le score de suspicion
            double score = calculateSuspiciousScore(history, currentPhone, newPhone);
            result.setSuspiciousScore(score);

            // Générer la raison
            String reason = generateReason(history.size(), score);
            result.setReason(reason);

            log.info("Phone history analyzed: clientId={}, changes={}, score={}",
                clientId, history.size(), score);

        } catch (Exception e) {
            log.error("Error analyzing phone history for clientId: {}", clientId, e);
            result.setSuspiciousScore(0.0);
            result.setChangeCount(0);
            result.setReason("Error analyzing history: " + e.getMessage());
        }

        return result;
    }

    private double calculateSuspiciousScore(
            List<PhoneHistoryCheck.PhoneHistoryEntry> history,
            String currentPhone,
            String newPhone) {

        int changeCount = history.size();

        // Règles de calcul du score
        if (changeCount == 0) {
            return 0.1; // Safe - aucun changement récent
        } else if (changeCount == 1) {
            return 0.3; // Low risk - 1 changement
        } else if (changeCount == 2) {
            return 0.6; // Medium risk - 2 changements
        } else if (changeCount >= 3) {
            return 0.9; // High risk - 3+ changements
        }

        return 0.5;
    }

    private String generateReason(int changeCount, double score) {
        if (changeCount == 0) {
            return "Low risk - No recent phone changes";
        } else if (changeCount == 1) {
            return "Low risk - 1 phone change in last 30 days";
        } else if (changeCount == 2) {
            return "Medium risk - 2 phone changes in last 30 days";
        } else {
            return String.format("High risk - %d phone changes in last 30 days (suspicious pattern)", changeCount);
        }
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/services/OTPService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.clients.DynamoDBClient;
import com.bnc.mcp.models.OTPCode;
import lombok.extern.slf4j.Slf4j;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;

@Slf4j
public class OTPService {

    private final DynamoDBClient dynamoDBClient;
    private final SecureRandom secureRandom;

    public OTPService() {
        this.dynamoDBClient = new DynamoDBClient();
        this.secureRandom = new SecureRandom();
    }

    /**
     * Génère un code OTP à 6 chiffres
     */
    public OTPCode generateOTP(String clientId, String executionId) {
        // Générer code à 6 chiffres
        int code = secureRandom.nextInt(900000) + 100000; // 100000 à 999999

        Instant now = Instant.now();
        Instant expiresAt = now.plus(5, ChronoUnit.MINUTES);

        OTPCode otpCode = OTPCode.builder()
            .code(String.valueOf(code))
            .clientId(clientId)
            .executionId(executionId)
            .createdAt(now)
            .expiresAt(expiresAt)
            .validated(false)
            .build();

        // Sauvegarder dans DynamoDB avec TTL
        dynamoDBClient.saveOTPCode(otpCode);

        log.info("OTP generated for clientId: {}, executionId: {}, expiresAt: {}",
            clientId, executionId, expiresAt);

        return otpCode;
    }

    /**
     * Vérifie si l'OTP a été validé
     */
    public boolean isOTPValidated(String clientId, String executionId) {
        OTPCode otpCode = dynamoDBClient.getOTPCode(clientId, executionId);

        if (otpCode == null) {
            log.warn("No OTP found for clientId: {}, executionId: {}", clientId, executionId);
            return false;
        }

        boolean isValidated = otpCode.isValidated();
        log.info("OTP validation status for clientId: {}, executionId: {} -> {}",
            clientId, executionId, isValidated);

        return isValidated;
    }
}
```

---

## Étape 2.11 : Clients

### Fichier : `src/main/java/com/bnc/mcp/clients/DynamoDBClient.java`

```java
package com.bnc.mcp.clients;

import com.bnc.mcp.models.OTPCode;
import com.bnc.mcp.models.PhoneHistoryCheck;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Slf4j
public class DynamoDBClient {

    private final DynamoDbClient dynamoDb;
    private final String phoneHistoryTable;
    private final String otpTable;

    public DynamoDBClient() {
        this.dynamoDb = DynamoDbClient.builder().build();
        this.phoneHistoryTable = System.getenv("PHONE_HISTORY_TABLE");
        this.otpTable = System.getenv("OTP_TABLE");
    }

    public List<PhoneHistoryCheck.PhoneHistoryEntry> getPhoneHistory(
            String clientId,
            Instant since) {

        List<PhoneHistoryCheck.PhoneHistoryEntry> history = new ArrayList<>();

        try {
            QueryRequest request = QueryRequest.builder()
                .tableName(phoneHistoryTable)
                .keyConditionExpression("PK = :pk AND SK > :since")
                .expressionAttributeValues(Map.of(
                    ":pk", AttributeValue.builder().s(clientId).build(),
                    ":since", AttributeValue.builder().s(since.toString()).build()
                ))
                .build();

            QueryResponse response = dynamoDb.query(request);

            for (Map<String, AttributeValue> item : response.items()) {
                PhoneHistoryCheck.PhoneHistoryEntry entry = new PhoneHistoryCheck.PhoneHistoryEntry();
                entry.setPhoneNumber(item.get("newPhoneNumber").s());
                entry.setChangedAt(item.get("timestamp").s());
                entry.setChangedBy(item.get("updatedBy").s());
                history.add(entry);
            }

            log.info("Retrieved {} phone history entries for clientId: {}", history.size(), clientId);

        } catch (Exception e) {
            log.error("Error getting phone history for clientId: {}", clientId, e);
        }

        return history;
    }

    public void saveOTPCode(OTPCode otpCode) {
        try {
            PutItemRequest request = PutItemRequest.builder()
                .tableName(otpTable)
                .item(Map.of(
                    "PK", AttributeValue.builder().s(otpCode.getClientId()).build(),
                    "SK", AttributeValue.builder().s(otpCode.getExecutionId()).build(),
                    "code", AttributeValue.builder().s(otpCode.getCode()).build(),
                    "createdAt", AttributeValue.builder().s(otpCode.getCreatedAt().toString()).build(),
                    "expiresAt", AttributeValue.builder().n(String.valueOf(otpCode.getExpiresAt().getEpochSecond())).build(),
                    "validated", AttributeValue.builder().bool(false).build()
                ))
                .build();

            dynamoDb.putItem(request);

            log.info("OTP saved for clientId: {}, executionId: {}",
                otpCode.getClientId(), otpCode.getExecutionId());

        } catch (Exception e) {
            log.error("Error saving OTP code", e);
            throw new RuntimeException("Failed to save OTP", e);
        }
    }

    public OTPCode getOTPCode(String clientId, String executionId) {
        try {
            GetItemRequest request = GetItemRequest.builder()
                .tableName(otpTable)
                .key(Map.of(
                    "PK", AttributeValue.builder().s(clientId).build(),
                    "SK", AttributeValue.builder().s(executionId).build()
                ))
                .build();

            GetItemResponse response = dynamoDb.getItem(request);

            if (!response.hasItem()) {
                return null;
            }

            Map<String, AttributeValue> item = response.item();

            return OTPCode.builder()
                .code(item.get("code").s())
                .clientId(clientId)
                .executionId(executionId)
                .createdAt(Instant.parse(item.get("createdAt").s()))
                .expiresAt(Instant.ofEpochSecond(Long.parseLong(item.get("expiresAt").n())))
                .validated(item.get("validated").bool())
                .build();

        } catch (Exception e) {
            log.error("Error getting OTP code for clientId: {}, executionId: {}", clientId, executionId, e);
            return null;
        }
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/clients/SMSClient.java`

```java
package com.bnc.mcp.clients;

import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sns.model.PublishResponse;

@Slf4j
public class SMSClient {

    private final SnsClient snsClient;

    public SMSClient() {
        this.snsClient = SnsClient.builder().build();
    }

    public boolean sendSMS(String phoneNumber, String message) {
        try {
            PublishRequest request = PublishRequest.builder()
                .phoneNumber(phoneNumber)
                .message(message)
                .build();

            PublishResponse response = snsClient.publish(request);

            log.info("SMS sent successfully to {}. MessageId: {}", phoneNumber, response.messageId());
            return true;

        } catch (Exception e) {
            log.error("Failed to send SMS to {}", phoneNumber, e);
            return false;
        }
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/clients/MDMAEClient.java`

```java
package com.bnc.mcp.clients;

import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Instant;
import java.util.Map;

@Slf4j
public class MDMAEClient {

    private final HttpClient httpClient;
    private final String mdmaeApiUrl;
    private final ObjectMapper objectMapper;

    public MDMAEClient() {
        this.httpClient = HttpClient.newHttpClient();
        this.mdmaeApiUrl = System.getenv("MDMAE_API_URL");
        this.objectMapper = new ObjectMapper();
    }

    public Map<String, Object> updatePhoneNumber(MDMAEPhoneUpdateRequest request) throws Exception {
        log.info("Calling MDMAE API to update phone for clientId: {}", request.getClientId());

        String endpoint = mdmaeApiUrl + "/clients/" + request.getClientId() + "/phone";

        Map<String, Object> body = Map.of(
            "oldPhoneNumber", request.getOldPhoneNumber(),
            "newPhoneNumber", request.getNewPhoneNumber(),
            "updatedBy", request.getUpdatedBy()
        );

        String jsonBody = objectMapper.writeValueAsString(body);

        HttpRequest httpRequest = HttpRequest.newBuilder()
            .uri(URI.create(endpoint))
            .header("Content-Type", "application/json")
            .header("X-API-Key", System.getenv("MDMAE_API_KEY"))
            .PUT(HttpRequest.BodyPublishers.ofString(jsonBody))
            .build();

        HttpResponse<String> response = httpClient.send(
            httpRequest,
            HttpResponse.BodyHandlers.ofString()
        );

        if (response.statusCode() != 200) {
            log.error("MDMAE API error: status={}, body={}", response.statusCode(), response.body());
            throw new RuntimeException("MDMAE API returned status " + response.statusCode());
        }

        Map<String, Object> result = objectMapper.readValue(response.body(), Map.class);

        log.info("MDMAE update successful. TransactionId: {}", result.get("transactionId"));

        return Map.of(
            "status", "SUCCESS",
            "transactionId", result.get("transactionId"),
            "timestamp", Instant.now().toString()
        );
    }
}
```

---

## Étape 2.12 : Build et déploiement

```bash
# 1. Aller dans le repo mcp-local
cd /Users/fabricefoko/Downloads/mcp-local

# 2. Build tous les JARs
mvn clean package

# 3. Vérifier que les JARs sont créés
ls -lh target/*.jar

# Output attendu :
# client-phone-update-controller-1.0.0.jar
# phone-validator-1.0.0.jar
# check-phone-history-1.0.0.jar
# send-otp-sms-1.0.0.jar
# check-otp-status-1.0.0.jar
# phone-mdmae-client-1.0.0.jar

# 4. Déployer via GitHub Actions
git add .
git commit -m "feat: implement phone update workflow"
git push origin main

# 5. Déclencher le workflow GitHub Actions
# Aller sur GitHub → Actions → Deploy Lambda Code
# Run workflow avec environment: dev
```

**Fichiers créés dans Phase 2 :**

✅ **Controllers :** 1 fichier (250 lignes)
✅ **Handlers :** 5 fichiers (500 lignes)
✅ **Models :** 4 fichiers (150 lignes)
✅ **Services :** 3 fichiers (400 lignes)
✅ **Clients :** 3 fichiers (300 lignes)

**Total :** ~16 fichiers Java, ~1600 lignes de code

---

## Phase 3 : Tests et validation

Voir fichier séparé : `WORKFLOW_PHONE_UPDATE_PHASE3_TESTS.md`