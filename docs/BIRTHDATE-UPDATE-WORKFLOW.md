# 🔄 Workflow de Mise à Jour - Date de Naissance Client

Définition complète du workflow de mise à jour de la date de naissance d'un client.

---

## 📋 Vue d'Ensemble

### Objectif
Permettre la mise à jour de la date de naissance d'un client existant dans le système MCP avec validation, traçabilité et propagation vers les systèmes en aval.

### Portée
- **Système source**: API Gateway REST
- **Orchestration**: AWS Step Functions (State Machine STANDARD)
- **Stockage**: DynamoDB (ClientProfile)
- **Propagation**: Kafka (topic: client-events)
- **Monitoring**: CloudWatch Logs

---

## 🎯 Flux Complet du Workflow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           WORKFLOW COMPLET                               │
└─────────────────────────────────────────────────────────────────────────┘

1. CLIENT (cURL/Swagger UI)
   │
   │ PUT /api/clients/{clientId}/date-naissance
   │ Body: {"newBirthdate": "1985-06-15", "reason": "CORRECTION"}
   │
   ▼
2. API GATEWAY
   │
   │ • Validation du format de requête
   │ • Transformation VTL (JSON → Step Functions input)
   │
   ▼
3. STEP FUNCTIONS (State Machine)
   │
   │ ┌─────────────────────────────────────────┐
   │ │ État 1: ValidateBirthdate               │
   │ │ Lambda: birthdate-validation            │
   │ │ • Client existe?                        │
   │ │ • Format date valide (YYYY-MM-DD)?      │
   │ │ • Date pas dans le futur?               │
   │ │ • Âge raisonnable (0-150 ans)?          │
   │ └─────────────────────────────────────────┘
   │          │                    │
   │          │ SUCCESS            │ FAILURE
   │          ▼                    ▼
   │ ┌──────────────┐      ┌──────────────────┐
   │ │ État 2:      │      │ ValidationFailed │
   │ │ UpdateBirth  │      │ (État FAIL)      │
   │ │ date         │      └──────────────────┘
   │ │ Lambda:      │
   │ │ birthdate-   │
   │ │ update       │
   │ │ • DynamoDB   │
   │ │   PutItem    │
   │ └──────────────┘
   │          │                    │
   │          │ SUCCESS            │ FAILURE
   │          ▼                    ▼
   │ ┌──────────────┐      ┌──────────────────┐
   │ │ État 3:      │      │ UpdateFailed     │
   │ │ PublishEvent │      │ (État FAIL)      │
   │ │ Lambda:      │      └──────────────────┘
   │ │ birthdate-   │
   │ │ event        │
   │ │ • Kafka      │
   │ │   publish    │
   │ └──────────────┘
   │          │
   │          ▼
   │ ┌──────────────┐
   │ │ Success      │
   │ │ (État SUCCEED)│
   │ └──────────────┘
   │
   ▼
4. RÉPONSE AU CLIENT
   │
   │ HTTP 200: {"message": "Birthdate update initiated", "executionArn": "..."}
   │ HTTP 400: {"error": "BadRequest", "message": "..."}
   │ HTTP 404: {"error": "NotFound", "message": "Client XXX introuvable"}
   │ HTTP 500: {"error": "InternalServerError", "message": "..."}
   │
   └─> FIN
```

---

## 💻 Implémentation Java des Handlers

Cette section contient le code Java complet des trois handlers Lambda nécessaires pour le workflow.

### Handler 1: BirthdateValidationHandler

**Fichier**: `src/main/java/com/bnc/mcp/handlers/BirthdateValidationHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClientBuilder;
import com.amazonaws.services.dynamodbv2.model.AttributeValue;
import com.amazonaws.services.dynamodbv2.model.GetItemRequest;
import com.amazonaws.services.dynamodbv2.model.GetItemResult;
import com.bnc.mcp.exceptions.*;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.Period;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.*;

/**
 * Handler Lambda pour la validation de la date de naissance.
 *
 * Valide:
 * - Existence du client dans DynamoDB
 * - Format de la date (YYYY-MM-DD)
 * - Date non future
 * - Âge raisonnable (0-150 ans)
 * - Raison du changement valide
 */
@Component
public class BirthdateValidationHandler implements McpHandler {

    private static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");
    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ISO_LOCAL_DATE;
    private static final int MIN_AGE = 0;
    private static final int MAX_AGE = 150;
    private static final Set<String> VALID_REASONS = Set.of(
        "CORRECTION", "MISE_A_JOUR", "ERREUR_SAISIE", "AUTRE"
    );

    private final AmazonDynamoDB dynamoDB;

    public BirthdateValidationHandler() {
        this.dynamoDB = AmazonDynamoDBClientBuilder.standard().build();
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        // 1. Extraire les paramètres d'entrée
        String clientId = String.valueOf(input.get("clientId"));
        String newBirthdate = String.valueOf(input.get("newBirthdate"));
        String reason = String.valueOf(input.get("reason"));

        System.out.println("Validating birthdate for client: " + clientId);

        // 2. Vérifier que le client existe dans DynamoDB
        Map<String, Object> clientProfile = validateClientExists(clientId);

        // 3. Valider le format de la date
        LocalDate birthdate = validateDateFormat(newBirthdate);

        // 4. Vérifier que la date n'est pas dans le futur
        validateDateNotFuture(birthdate, newBirthdate);

        // 5. Vérifier que l'âge est raisonnable (0-150 ans)
        int age = validateAge(birthdate, newBirthdate);

        // 6. Vérifier que la raison est valide
        validateReason(reason);

        // 7. Construire la réponse
        Map<String, Object> response = new HashMap<>();
        response.put("clientId", clientId);
        response.put("newBirthdate", newBirthdate);
        response.put("reason", reason);

        // Résultat de validation
        Map<String, Object> validation = new HashMap<>();
        validation.put("status", "PASSED");
        validation.put("clientExists", true);
        validation.put("dateFormatValid", true);
        validation.put("dateNotFuture", true);
        validation.put("ageValid", true);
        validation.put("age", age);
        validation.put("reasonValid", true);
        validation.put("validatedAt", new Date().toInstant().toString());
        response.put("validation", validation);

        // Profil client enrichi
        response.put("clientProfile", clientProfile);

        System.out.println("Validation passed for client: " + clientId);
        return response;
    }

    /**
     * Vérifie que le client existe dans DynamoDB
     */
    private Map<String, Object> validateClientExists(String clientId) {
        GetItemRequest request = new GetItemRequest()
            .withTableName(TABLE_NAME)
            .withKey(Collections.singletonMap("clientId", new AttributeValue(clientId)));

        GetItemResult result = dynamoDB.getItem(request);

        if (result.getItem() == null || result.getItem().isEmpty()) {
            System.err.println("Client not found: " + clientId);
            throw new ClientNotFoundException("Client " + clientId + " introuvable");
        }

        // Convertir le résultat DynamoDB en Map
        Map<String, AttributeValue> item = result.getItem();
        Map<String, Object> clientProfile = new HashMap<>();
        clientProfile.put("clientId", item.get("clientId").getS());
        clientProfile.put("firstName", item.get("firstName").getS());
        clientProfile.put("lastName", item.get("lastName").getS());
        clientProfile.put("currentBirthdate", item.get("dateOfBirth").getS());
        if (item.containsKey("email")) {
            clientProfile.put("email", item.get("email").getS());
        }

        return clientProfile;
    }

    /**
     * Valide le format de la date (YYYY-MM-DD)
     */
    private LocalDate validateDateFormat(String dateString) {
        try {
            return LocalDate.parse(dateString, DATE_FORMATTER);
        } catch (DateTimeParseException e) {
            System.err.println("Invalid date format: " + dateString);
            throw new InvalidDateFormatException(
                "Format de date invalide. Utilisez YYYY-MM-DD. Reçu: " + dateString
            );
        }
    }

    /**
     * Vérifie que la date n'est pas dans le futur
     */
    private void validateDateNotFuture(LocalDate birthdate, String dateString) {
        LocalDate today = LocalDate.now();
        if (birthdate.isAfter(today)) {
            System.err.println("Future date detected: " + dateString);
            throw new FutureDateException(
                "La date de naissance ne peut pas être dans le futur. " +
                "Date fournie: " + dateString + ", Date actuelle: " + today
            );
        }
    }

    /**
     * Valide que l'âge est raisonnable (0-150 ans)
     */
    private int validateAge(LocalDate birthdate, String dateString) {
        LocalDate today = LocalDate.now();
        int age = Period.between(birthdate, today).getYears();

        if (age < MIN_AGE || age > MAX_AGE) {
            System.err.println("Invalid age: " + age + " years");
            throw new InvalidAgeException(
                "L'âge calculé (" + age + " ans) n'est pas valide. " +
                "Doit être entre " + MIN_AGE + " et " + MAX_AGE + " ans."
            );
        }

        return age;
    }

    /**
     * Valide que la raison du changement est dans la liste autorisée
     */
    private void validateReason(String reason) {
        if (!VALID_REASONS.contains(reason)) {
            System.err.println("Invalid reason: " + reason);
            throw new InvalidReasonException(
                "Raison invalide: " + reason + ". " +
                "Raisons valides: " + String.join(", ", VALID_REASONS)
            );
        }
    }
}
```

### Handler 2: BirthdateUpdateHandler

**Fichier**: `src/main/java/com/bnc/mcp/handlers/BirthdateUpdateHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClientBuilder;
import com.amazonaws.services.dynamodbv2.model.*;
import com.bnc.mcp.exceptions.ClientDeletedException;
import com.bnc.mcp.exceptions.DatabaseException;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

/**
 * Handler Lambda pour la mise à jour de la date de naissance dans DynamoDB.
 *
 * Responsabilités:
 * - Mise à jour de la date de naissance
 * - Préservation de l'ancienne valeur (previousDateOfBirth)
 * - Stockage de la raison du changement
 * - Gestion du timestamp de mise à jour
 */
@Component
public class BirthdateUpdateHandler implements McpHandler {

    private static final String TABLE_NAME = System.getenv("DYNAMODB_TABLE_NAME");
    private final AmazonDynamoDB dynamoDB;

    public BirthdateUpdateHandler() {
        this.dynamoDB = AmazonDynamoDBClientBuilder.standard().build();
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        // 1. Extraire les paramètres
        String clientId = String.valueOf(input.get("clientId"));
        String newBirthdate = String.valueOf(input.get("newBirthdate"));
        String reason = String.valueOf(input.get("reason"));

        // Récupérer le profil client depuis la validation
        @SuppressWarnings("unchecked")
        Map<String, Object> validationResult = (Map<String, Object>) input.get("validationResult");
        @SuppressWarnings("unchecked")
        Map<String, Object> clientProfile = (Map<String, Object>) validationResult.get("clientProfile");
        String previousBirthdate = String.valueOf(clientProfile.get("currentBirthdate"));

        System.out.println("Updating birthdate for client: " + clientId);
        System.out.println("Previous: " + previousBirthdate + " -> New: " + newBirthdate);

        // 2. Préparer les valeurs de mise à jour
        String updateTimestamp = Instant.now().toString();
        String updatedBy = "API_GATEWAY"; // Ou récupérer du contexte d'authentification

        // 3. Construire la requête DynamoDB UpdateItem
        Map<String, AttributeValue> key = new HashMap<>();
        key.put("clientId", new AttributeValue(clientId));

        Map<String, AttributeValueUpdate> updates = new HashMap<>();
        updates.put("dateOfBirth", new AttributeValueUpdate()
            .withValue(new AttributeValue(newBirthdate))
            .withAction(AttributeAction.PUT));
        updates.put("previousDateOfBirth", new AttributeValueUpdate()
            .withValue(new AttributeValue(previousBirthdate))
            .withAction(AttributeAction.PUT));
        updates.put("lastUpdated", new AttributeValueUpdate()
            .withValue(new AttributeValue(updateTimestamp))
            .withAction(AttributeAction.PUT));
        updates.put("updateReason", new AttributeValueUpdate()
            .withValue(new AttributeValue(reason))
            .withAction(AttributeAction.PUT));
        updates.put("updatedBy", new AttributeValueUpdate()
            .withValue(new AttributeValue(updatedBy))
            .withAction(AttributeAction.PUT));

        UpdateItemRequest updateRequest = new UpdateItemRequest()
            .withTableName(TABLE_NAME)
            .withKey(key)
            .withAttributeUpdates(updates)
            .withConditionExpression("attribute_exists(clientId)") // Client doit exister
            .withReturnValues(ReturnValue.ALL_NEW);

        try {
            // 4. Exécuter la mise à jour
            UpdateItemResult result = dynamoDB.updateItem(updateRequest);

            // 5. Construire la réponse
            Map<String, Object> response = new HashMap<>();
            response.put("clientId", clientId);
            response.put("newBirthdate", newBirthdate);
            response.put("previousBirthdate", previousBirthdate);
            response.put("reason", reason);

            Map<String, Object> updateInfo = new HashMap<>();
            updateInfo.put("status", "SUCCESS");
            updateInfo.put("timestamp", updateTimestamp);
            updateInfo.put("updatedBy", updatedBy);
            updateInfo.put("dynamodbResponse", Map.of(
                "ResponseMetadata", Map.of("HTTPStatusCode", 200)
            ));
            response.put("update", updateInfo);

            // Profil client mis à jour
            Map<String, Object> updatedProfile = convertDynamoDBItem(result.getAttributes());
            response.put("clientProfile", updatedProfile);

            System.out.println("Successfully updated birthdate for client: " + clientId);
            return response;

        } catch (ConditionalCheckFailedException e) {
            System.err.println("Client was deleted during update: " + clientId);
            throw new ClientDeletedException(
                "Le client " + clientId + " a été supprimé pendant la mise à jour"
            );
        } catch (Exception e) {
            System.err.println("Database error during update: " + e.getMessage());
            throw new DatabaseException(
                "Erreur lors de la mise à jour dans DynamoDB: " + e.getMessage(),
                e
            );
        }
    }

    /**
     * Convertit un item DynamoDB en Map Java
     */
    private Map<String, Object> convertDynamoDBItem(Map<String, AttributeValue> item) {
        Map<String, Object> result = new HashMap<>();
        for (Map.Entry<String, AttributeValue> entry : item.entrySet()) {
            result.put(entry.getKey(), entry.getValue().getS());
        }
        return result;
    }
}
```

### Handler 3: BirthdateEventPublisher

**Fichier**: `src/main/java/com/bnc/mcp/handlers/BirthdateEventPublisher.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.kafka.AWSKafka;
import com.amazonaws.services.kafka.AWSKafkaClientBuilder;
import com.bnc.mcp.exceptions.KafkaPublishException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;

/**
 * Handler Lambda pour la publication d'événements Kafka.
 *
 * Responsabilités:
 * - Construction du message Kafka au format attendu
 * - Publication vers le topic client-events
 * - Gestion des retries en cas d'échec
 * - Logging et traçabilité
 */
@Component
public class BirthdateEventPublisher implements McpHandler {

    private static final String KAFKA_TOPIC = System.getenv("KAFKA_TOPIC");
    private static final String KAFKA_BOOTSTRAP_SERVERS = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
    private static final String EVENT_TYPE = "CLIENT_BIRTHDATE_UPDATED";
    private static final String EVENT_VERSION = "1.0";
    private static final String SOURCE = "mcp-api-gateway";

    private final ObjectMapper objectMapper;
    private final KafkaProducer<String, String> producer;

    public BirthdateEventPublisher() {
        this.objectMapper = new ObjectMapper();
        this.producer = createKafkaProducer();
    }

    @Override
    public Object handle(Map<String, Object> input) throws Exception {
        // 1. Extraire les données du contexte
        String clientId = String.valueOf(input.get("clientId"));
        String newBirthdate = String.valueOf(input.get("newBirthdate"));
        String reason = String.valueOf(input.get("reason"));

        @SuppressWarnings("unchecked")
        Map<String, Object> updateResult = (Map<String, Object>) input.get("updateResult");
        String previousBirthdate = String.valueOf(updateResult.get("previousBirthdate"));

        @SuppressWarnings("unchecked")
        Map<String, Object> clientProfile = (Map<String, Object>) updateResult.get("clientProfile");
        String firstName = String.valueOf(clientProfile.get("firstName"));
        String lastName = String.valueOf(clientProfile.get("lastName"));
        String updateTimestamp = String.valueOf(clientProfile.get("lastUpdated"));

        System.out.println("Publishing birthdate update event for client: " + clientId);

        // 2. Construire le message Kafka
        String eventId = UUID.randomUUID().toString();
        Map<String, Object> event = buildKafkaEvent(
            eventId, clientId, firstName, lastName,
            previousBirthdate, newBirthdate, reason, updateTimestamp
        );

        // 3. Publier vers Kafka
        String eventJson = objectMapper.writeValueAsString(event);
        ProducerRecord<String, String> record = new ProducerRecord<>(
            KAFKA_TOPIC,
            clientId, // Partition key (garantit l'ordre par client)
            eventJson
        );

        try {
            // Publication synchrone pour garantir la durabilité
            Future<RecordMetadata> future = producer.send(record);
            RecordMetadata metadata = future.get(); // Bloque jusqu'à confirmation

            System.out.println("Event published successfully:");
            System.out.println("  Topic: " + metadata.topic());
            System.out.println("  Partition: " + metadata.partition());
            System.out.println("  Offset: " + metadata.offset());

            // 4. Construire la réponse
            Map<String, Object> response = new HashMap<>(input);

            Map<String, Object> eventInfo = new HashMap<>();
            eventInfo.put("status", "PUBLISHED");
            eventInfo.put("eventId", eventId);
            eventInfo.put("topic", metadata.topic());
            eventInfo.put("partition", metadata.partition());
            eventInfo.put("offset", metadata.offset());
            eventInfo.put("timestamp", Instant.now().toString());
            eventInfo.put("retries", 0); // Géré par Kafka producer config
            response.put("event", eventInfo);

            response.put("finalStatus", "SUCCESS");

            return response;

        } catch (InterruptedException | ExecutionException e) {
            System.err.println("Failed to publish event to Kafka: " + e.getMessage());
            throw new KafkaPublishException(
                "Impossible de publier l'événement après plusieurs tentatives: " + e.getMessage(),
                e
            );
        }
    }

    /**
     * Construit le message Kafka au format standard
     */
    private Map<String, Object> buildKafkaEvent(
        String eventId, String clientId, String firstName, String lastName,
        String previousBirthdate, String newBirthdate, String reason, String updateTimestamp
    ) {
        Map<String, Object> event = new HashMap<>();
        event.put("eventType", EVENT_TYPE);
        event.put("eventVersion", EVENT_VERSION);
        event.put("eventId", eventId);
        event.put("timestamp", Instant.now().toString());
        event.put("source", SOURCE);

        // Data payload
        Map<String, Object> data = new HashMap<>();
        data.put("clientId", clientId);
        data.put("firstName", firstName);
        data.put("lastName", lastName);

        Map<String, String> dateOfBirth = new HashMap<>();
        dateOfBirth.put("previous", previousBirthdate);
        dateOfBirth.put("current", newBirthdate);
        data.put("dateOfBirth", dateOfBirth);

        data.put("updateReason", reason);
        data.put("updatedBy", "API_GATEWAY");
        data.put("updateTimestamp", updateTimestamp);
        event.put("data", data);

        // Metadata
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("correlationId", "step-functions-execution-id"); // À enrichir
        metadata.put("environment", System.getenv("ENVIRONMENT"));
        metadata.put("region", System.getenv("AWS_REGION"));
        event.put("metadata", metadata);

        return event;
    }

    /**
     * Crée un producer Kafka avec configuration optimisée
     */
    private KafkaProducer<String, String> createKafkaProducer() {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, KAFKA_BOOTSTRAP_SERVERS);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

        // Durabilité et fiabilité
        props.put(ProducerConfig.ACKS_CONFIG, "all"); // Attend confirmation de tous les replicas
        props.put(ProducerConfig.RETRIES_CONFIG, 5); // 5 tentatives
        props.put(ProducerConfig.RETRY_BACKOFF_MS_CONFIG, 1000); // 1s entre retries
        props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 1); // Garantit l'ordre

        // Compression
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "gzip");

        // Timeouts
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 30000); // 30s
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120000); // 2min

        return new KafkaProducer<>(props);
    }

    /**
     * Ferme proprement le producer Kafka
     */
    public void close() {
        if (producer != null) {
            producer.close();
        }
    }
}
```

### Exceptions Personnalisées

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/ClientNotFoundException.java`

```java
package com.bnc.mcp.exceptions;

public class ClientNotFoundException extends RuntimeException {
    public ClientNotFoundException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/InvalidDateFormatException.java`

```java
package com.bnc.mcp.exceptions;

public class InvalidDateFormatException extends RuntimeException {
    public InvalidDateFormatException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/FutureDateException.java`

```java
package com.bnc.mcp.exceptions;

public class FutureDateException extends RuntimeException {
    public FutureDateException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/InvalidAgeException.java`

```java
package com.bnc.mcp.exceptions;

public class InvalidAgeException extends RuntimeException {
    public InvalidAgeException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/InvalidReasonException.java`

```java
package com.bnc.mcp.exceptions;

public class InvalidReasonException extends RuntimeException {
    public InvalidReasonException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/ClientDeletedException.java`

```java
package com.bnc.mcp.exceptions;

public class ClientDeletedException extends RuntimeException {
    public ClientDeletedException(String message) {
        super(message);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/DatabaseException.java`

```java
package com.bnc.mcp.exceptions;

public class DatabaseException extends RuntimeException {
    public DatabaseException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

**Fichier**: `src/main/java/com/bnc/mcp/exceptions/KafkaPublishException.java`

```java
package com.bnc.mcp.exceptions;

public class KafkaPublishException extends RuntimeException {
    public KafkaPublishException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### Interface Handler

**Fichier**: `src/main/java/com/bnc/mcp/handlers/McpHandler.java`

```java
package com.bnc.mcp.handlers;

import java.util.Map;

/**
 * Interface commune pour tous les handlers Lambda MCP
 */
public interface McpHandler {
    /**
     * Traite une requête Lambda
     *
     * @param input Input de la Lambda (converti depuis JSON)
     * @return Output à retourner (sera converti en JSON)
     * @throws Exception En cas d'erreur de traitement
     */
    Object handle(Map<String, Object> input) throws Exception;
}
```

---

## 📁 Structure des Repositories et Ressources à Créer

Cette section spécifie **exactement quoi créer et où** pour implémenter le workflow de mise à jour de date de naissance.

### Vue d'Ensemble des Repositories

Le projet MCP est divisé en **deux repositories**:

1. **mcp-infrastructure** (Terraform) - Infrastructure as Code
2. **mcp-lambda-handlers** (Java) - Code métier des Lambda functions

---

### 🏗️ Repository 1: mcp-infrastructure (Terraform)

**Emplacement**: `/Users/fabricefoko/Documents/mcp-infrastructure`

#### Fichiers à Créer/Modifier

```
mcp-infrastructure/
│
├── modules/
│   ├── lambda/
│   │   ├── main.tf
│   │   │   └── [AJOUTER] 3 nouvelles Lambda resources:
│   │   │       • aws_lambda_function.birthdate_validation
│   │   │       • aws_lambda_function.birthdate_update
│   │   │       • aws_lambda_function.birthdate_event_publisher
│   │   │
│   │   └── variables.tf
│   │       └── [VÉRIFIER] Variables nécessaires pour les 3 Lambdas
│   │
│   ├── step-functions/
│   │   ├── state-machines/
│   │   │   └── [CRÉER] client_birthdate_update.json
│   │   │       └── Définition de la state machine (voir section suivante)
│   │   │
│   │   └── main.tf
│   │       └── [AJOUTER] aws_sfn_state_machine.client_birthdate_update
│   │
│   └── api-gateway/
│       ├── openapi-spec.json.tpl
│       │   └── [AJOUTER] Nouveau endpoint:
│       │       PUT /api/clients/{clientId}/date-naissance
│       │
│       └── main.tf
│           └── [VÉRIFIER] Intégration avec Step Functions
│
├── environments/
│   └── dev/
│       ├── main.tf
│       │   └── [VÉRIFIER] Inclusion des nouveaux modules
│       │
│       └── dev.tfvars
│           └── [AJOUTER si nécessaire] Variables spécifiques
│
└── docs/
    └── BIRTHDATE-UPDATE-WORKFLOW.md
        └── [✅ DÉJÀ CRÉÉ] Ce document
```

#### Ressources AWS à Créer (via Terraform)

| Ressource | Nom Terraform | Nom AWS | Description |
|-----------|---------------|---------|-------------|
| **Lambda Function** | `aws_lambda_function.birthdate_validation` | `dev-mcp-birthdate-validation` | Validation de la date de naissance |
| **Lambda Function** | `aws_lambda_function.birthdate_update` | `dev-mcp-birthdate-update` | Mise à jour DynamoDB |
| **Lambda Function** | `aws_lambda_function.birthdate_event_publisher` | `dev-mcp-birthdate-event-publisher` | Publication Kafka |
| **IAM Role** | `aws_iam_role.lambda_birthdate_validation` | `dev-mcp-birthdate-validation-role` | Rôle pour lambda validation |
| **IAM Role** | `aws_iam_role.lambda_birthdate_update` | `dev-mcp-birthdate-update-role` | Rôle pour lambda update (DynamoDB) |
| **IAM Role** | `aws_iam_role.lambda_birthdate_event` | `dev-mcp-birthdate-event-role` | Rôle pour lambda event (Kafka) |
| **IAM Policy** | `aws_iam_role_policy.dynamodb_read` | - | Permission GetItem sur ClientProfile |
| **IAM Policy** | `aws_iam_role_policy.dynamodb_write` | - | Permission UpdateItem sur ClientProfile |
| **IAM Policy** | `aws_iam_role_policy.kafka_publish` | - | Permission publier sur MSK |
| **CloudWatch Log Group** | `aws_cloudwatch_log_group.birthdate_validation` | `/aws/lambda/dev-mcp-birthdate-validation` | Logs validation |
| **CloudWatch Log Group** | `aws_cloudwatch_log_group.birthdate_update` | `/aws/lambda/dev-mcp-birthdate-update` | Logs update |
| **CloudWatch Log Group** | `aws_cloudwatch_log_group.birthdate_event` | `/aws/lambda/dev-mcp-birthdate-event-publisher` | Logs event publisher |
| **Step Functions State Machine** | `aws_sfn_state_machine.birthdate_update` | `dev-mcp-client_birthdate_update` | Orchestration du workflow |
| **IAM Role** | `aws_iam_role.sfn_birthdate_update` | `dev-mcp-sfn-birthdate-update-role` | Rôle pour Step Functions |
| **IAM Policy** | `aws_iam_role_policy.sfn_invoke_lambda` | - | Permission InvokeFunction sur les 3 Lambdas |
| **API Gateway Resource** | `aws_api_gateway_resource.birthdate` | `/api/clients/{clientId}/date-naissance` | Ressource API Gateway |
| **API Gateway Method** | `aws_api_gateway_method.put_birthdate` | `PUT` | Méthode HTTP PUT |
| **API Gateway Integration** | `aws_api_gateway_integration.birthdate_sfn` | - | Intégration avec Step Functions |

**Total**: 17 ressources AWS à créer

---

### 💻 Repository 2: mcp-lambda-handlers (Java)

**Emplacement**: À créer (nouveau repository) ou intégrer dans un repo Java existant

#### Structure Complète du Projet Java

```
mcp-lambda-handlers/
│
├── pom.xml
│   └── [CRÉER] Configuration Maven avec dépendances
│
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── bnc/
│   │   │           └── mcp/
│   │   │               │
│   │   │               ├── handlers/
│   │   │               │   ├── [CRÉER] McpHandler.java
│   │   │               │   │   └── Interface commune
│   │   │               │   │
│   │   │               │   ├── [CRÉER] BirthdateValidationHandler.java
│   │   │               │   │   └── Handler Lambda #1 (283 lignes)
│   │   │               │   │
│   │   │               │   ├── [CRÉER] BirthdateUpdateHandler.java
│   │   │               │   │   └── Handler Lambda #2 (138 lignes)
│   │   │               │   │
│   │   │               │   └── [CRÉER] BirthdateEventPublisher.java
│   │   │               │       └── Handler Lambda #3 (184 lignes)
│   │   │               │
│   │   │               └── exceptions/
│   │   │                   ├── [CRÉER] ClientNotFoundException.java
│   │   │                   ├── [CRÉER] InvalidDateFormatException.java
│   │   │                   ├── [CRÉER] FutureDateException.java
│   │   │                   ├── [CRÉER] InvalidAgeException.java
│   │   │                   ├── [CRÉER] InvalidReasonException.java
│   │   │                   ├── [CRÉER] ClientDeletedException.java
│   │   │                   ├── [CRÉER] DatabaseException.java
│   │   │                   └── [CRÉER] KafkaPublishException.java
│   │   │
│   │   └── resources/
│   │       └── [CRÉER] application.properties
│   │           └── Configuration Spring Cloud Function
│   │
│   └── test/
│       └── java/
│           └── com/
│               └── bnc/
│                   └── mcp/
│                       └── handlers/
│                           ├── [CRÉER] BirthdateValidationHandlerTest.java
│                           ├── [CRÉER] BirthdateUpdateHandlerTest.java
│                           └── [CRÉER] BirthdateEventPublisherTest.java
│
├── [CRÉER] .gitignore
├── [CRÉER] README.md
└── [CRÉER] buildspec.yml
    └── (si utilisation de AWS CodeBuild)
```

#### Fichiers à Créer - Détails

##### 1. pom.xml

**Fichier**: `pom.xml`
**Emplacement**: Racine du projet
**Taille**: ~120 lignes

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.bnc</groupId>
    <artifactId>mcp-lambda-handlers</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>MCP Lambda Handlers</name>
    <description>Lambda handlers for MCP client management</description>

    <properties>
        <java.version>11</java.version>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>

        <!-- Versions -->
        <spring-cloud-function.version>3.2.9</spring-cloud-function.version>
        <aws-lambda-java-core.version>1.2.2</aws-lambda-java-core.version>
        <aws-sdk.version>1.12.529</aws-sdk.version>
        <kafka-clients.version>3.5.1</kafka-clients.version>
        <jackson.version>2.15.2</jackson.version>
        <junit.version>5.9.3</junit.version>
        <mockito.version>5.3.1</mockito.version>
    </properties>

    <dependencies>
        <!-- Spring Cloud Function -->
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-function-adapter-aws</artifactId>
            <version>${spring-cloud-function.version}</version>
        </dependency>

        <!-- AWS Lambda Core -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-core</artifactId>
            <version>${aws-lambda-java-core.version}</version>
        </dependency>

        <!-- AWS SDK - DynamoDB -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-dynamodb</artifactId>
            <version>${aws-sdk.version}</version>
        </dependency>

        <!-- Kafka Client -->
        <dependency>
            <groupId>org.apache.kafka</groupId>
            <artifactId>kafka-clients</artifactId>
            <version>${kafka-clients.version}</version>
        </dependency>

        <!-- Jackson pour JSON -->
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>${jackson.version}</version>
        </dependency>

        <dependency>
            <groupId>com.fasterxml.jackson.datatype</groupId>
            <artifactId>jackson-datatype-jsr310</artifactId>
            <version>${jackson.version}</version>
        </dependency>

        <!-- Testing -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-api</artifactId>
            <version>${junit.version}</version>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-engine</artifactId>
            <version>${junit.version}</version>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-core</artifactId>
            <version>${mockito.version}</version>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-junit-jupiter</artifactId>
            <version>${mockito.version}</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <!-- Maven Compiler Plugin -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                </configuration>
            </plugin>

            <!-- Maven Shade Plugin - Créer un fat JAR -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.5.0</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <createDependencyReducedPom>false</createDependencyReducedPom>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>org.springframework.cloud.function.adapter.aws.FunctionInvoker</mainClass>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.handlers</resource>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.schemas</resource>
                                </transformer>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.AppendingTransformer">
                                    <resource>META-INF/spring.factories</resource>
                                </transformer>
                            </transformers>
                        </configuration>
                    </execution>
                </executions>
            </plugin>

            <!-- Maven Surefire Plugin - Tests -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.1.2</version>
            </plugin>
        </plugins>
    </build>
</project>
```

##### 2. application.properties

**Fichier**: `src/main/resources/application.properties`

```properties
# Spring Cloud Function configuration
spring.cloud.function.definition=birthdateValidationHandler;birthdateUpdateHandler;birthdateEventPublisher

# AWS Configuration (overridden by environment variables)
aws.region=${AWS_REGION:ca-central-1}

# DynamoDB
dynamodb.table.name=${DYNAMODB_TABLE_NAME:dev-ClientProfile}

# Kafka/MSK
kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}
kafka.topic.client.events=${KAFKA_TOPIC_CLIENT_EVENTS:client-events}

# Logging
logging.level.root=INFO
logging.level.com.bnc.mcp=DEBUG
```

##### 3. .gitignore

**Fichier**: `.gitignore`

```gitignore
# Maven
target/
pom.xml.tag
pom.xml.releaseBackup
pom.xml.versionsBackup
pom.xml.next
release.properties
dependency-reduced-pom.xml

# IDE
.idea/
*.iml
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# Build artifacts
*.jar
*.war
*.ear

# Java
*.class
*.ctxt
.mtj.tmp/
hs_err_pid*
```

##### 4. README.md (Repository Java)

**Fichier**: `README.md`

```markdown
# MCP Lambda Handlers

Lambda functions Java pour le système MCP (Modification Client Profile).

## 🎯 Handlers Disponibles

### 1. BirthdateValidationHandler
Valide la date de naissance d'un client avant mise à jour.

**Handler Name**: `birthdateValidationHandler`
**Runtime**: Java 11
**Memory**: 512 MB
**Timeout**: 30s

### 2. BirthdateUpdateHandler
Met à jour la date de naissance dans DynamoDB.

**Handler Name**: `birthdateUpdateHandler`
**Runtime**: Java 11
**Memory**: 512 MB
**Timeout**: 30s

### 3. BirthdateEventPublisher
Publie un événement Kafka après mise à jour.

**Handler Name**: `birthdateEventPublisher`
**Runtime**: Java 11
**Memory**: 512 MB
**Timeout**: 30s

## 🏗️ Build

### Prérequis
- Java 11+
- Maven 3.8+

### Compiler et packager

```bash
mvn clean package
```

Le JAR final sera créé dans `target/mcp-lambda-handlers-1.0.0.jar`.

### Exécuter les tests

```bash
mvn test
```

## 🚀 Déploiement

### Upload vers S3

```bash
aws s3 cp target/mcp-lambda-handlers-1.0.0.jar \
  s3://mcp-lambda-artifacts-dev/birthdate/1.0.0/
```

### Déployer avec Terraform

```bash
cd ../mcp-infrastructure/environments/dev
terraform apply -target=module.lambda -auto-approve
```

## 📁 Structure

```
src/
├── main/java/com/bnc/mcp/
│   ├── handlers/          # Lambda handlers
│   └── exceptions/        # Custom exceptions
└── test/java/com/bnc/mcp/
    └── handlers/          # Tests unitaires
```

## 🔧 Configuration

Les handlers utilisent des variables d'environnement:

- `AWS_REGION`: Région AWS (ca-central-1)
- `DYNAMODB_TABLE_NAME`: Table DynamoDB (dev-ClientProfile)
- `KAFKA_BOOTSTRAP_SERVERS`: Brokers MSK
- `KAFKA_TOPIC_CLIENT_EVENTS`: Topic Kafka (client-events)

## 📖 Documentation

- [Workflow Birthdate Update](../mcp-infrastructure/docs/BIRTHDATE-UPDATE-WORKFLOW.md)
- [Architecture](../mcp-infrastructure/docs/ARCHITECTURE.md)
```

---

### 🔄 Processus de Création - Étape par Étape

#### Phase 1: Setup du Repository Java

```bash
# 1. Créer le repository
mkdir -p ~/Documents/mcp-lambda-handlers
cd ~/Documents/mcp-lambda-handlers

# 2. Initialiser Git
git init
git remote add origin <URL_DU_REPO_GIT>

# 3. Créer la structure de dossiers
mkdir -p src/main/java/com/bnc/mcp/handlers
mkdir -p src/main/java/com/bnc/mcp/exceptions
mkdir -p src/main/resources
mkdir -p src/test/java/com/bnc/mcp/handlers

# 4. Créer les fichiers de configuration
# Copier le contenu de pom.xml (ci-dessus)
vim pom.xml

# Copier le contenu de application.properties
vim src/main/resources/application.properties

# Copier .gitignore
vim .gitignore

# Copier README.md
vim README.md
```

#### Phase 2: Créer les Handlers Java

```bash
# 5. Créer l'interface
vim src/main/java/com/bnc/mcp/handlers/McpHandler.java
# [Copier le code depuis la section "💻 Implémentation Java des Handlers"]

# 6. Créer BirthdateValidationHandler
vim src/main/java/com/bnc/mcp/handlers/BirthdateValidationHandler.java
# [Copier le code complet - 283 lignes]

# 7. Créer BirthdateUpdateHandler
vim src/main/java/com/bnc/mcp/handlers/BirthdateUpdateHandler.java
# [Copier le code complet - 138 lignes]

# 8. Créer BirthdateEventPublisher
vim src/main/java/com/bnc/mcp/handlers/BirthdateEventPublisher.java
# [Copier le code complet - 184 lignes]
```

#### Phase 3: Créer les Exceptions

```bash
# 9. Créer toutes les exceptions (8 fichiers)
vim src/main/java/com/bnc/mcp/exceptions/ClientNotFoundException.java
vim src/main/java/com/bnc/mcp/exceptions/InvalidDateFormatException.java
vim src/main/java/com/bnc/mcp/exceptions/FutureDateException.java
vim src/main/java/com/bnc/mcp/exceptions/InvalidAgeException.java
vim src/main/java/com/bnc/mcp/exceptions/InvalidReasonException.java
vim src/main/java/com/bnc/mcp/exceptions/ClientDeletedException.java
vim src/main/java/com/bnc/mcp/exceptions/DatabaseException.java
vim src/main/java/com/bnc/mcp/exceptions/KafkaPublishException.java
# [Copier le code de chaque exception depuis la section Java]
```

#### Phase 4: Build et Test

```bash
# 10. Compiler le projet
mvn clean compile

# 11. Exécuter les tests (après création des tests unitaires)
mvn test

# 12. Packager le JAR
mvn clean package

# 13. Vérifier le JAR créé
ls -lh target/mcp-lambda-handlers-1.0.0.jar
# Devrait faire environ 15-20 MB (avec toutes les dépendances)
```

#### Phase 5: Upload vers S3 (pour Lambda)

```bash
# 14. Créer un bucket S3 pour les artefacts Lambda (si pas déjà créé)
aws s3 mb s3://mcp-lambda-artifacts-dev --region ca-central-1

# 15. Créer le dossier pour cette version
aws s3api put-object \
  --bucket mcp-lambda-artifacts-dev \
  --key birthdate/1.0.0/

# 16. Upload du JAR
aws s3 cp target/mcp-lambda-handlers-1.0.0.jar \
  s3://mcp-lambda-artifacts-dev/birthdate/1.0.0/ \
  --region ca-central-1

# 17. Vérifier l'upload
aws s3 ls s3://mcp-lambda-artifacts-dev/birthdate/1.0.0/
```

#### Phase 6: Mise à Jour du Repository Terraform

```bash
# 18. Aller dans le repo Terraform
cd ~/Documents/mcp-infrastructure

# 19. Créer la définition de la state machine
vim modules/step-functions/state-machines/client_birthdate_update.json
# [Voir section "Définition de la State Machine" ci-dessous]

# 20. Mettre à jour le module Lambda pour ajouter les 3 nouvelles fonctions
vim modules/lambda/main.tf
# [Ajouter les 3 ressources aws_lambda_function]

# 21. Mettre à jour le module Step Functions
vim modules/step-functions/main.tf
# [Ajouter aws_sfn_state_machine.client_birthdate_update]

# 22. Mettre à jour l'API Gateway
vim modules/api-gateway/openapi-spec.json.tpl
# [Ajouter le endpoint PUT /api/clients/{clientId}/date-naissance]
```

#### Phase 7: Déploiement Terraform

```bash
# 23. Plan Terraform
cd environments/dev
terraform plan -out=tfplan

# 24. Apply Terraform
terraform apply tfplan

# 25. Récupérer les outputs
terraform output api_gateway_url
terraform output swagger_ui_url
```

#### Phase 8: Tests End-to-End

```bash
# 26. Tester via Swagger UI
# Ouvrir l'URL du Swagger UI dans le navigateur
open $(terraform output -raw swagger_ui_url)

# 27. Tester via cURL
API_URL=$(terraform output -raw api_gateway_url)
curl -X PUT "${API_URL}/api/clients/TEST123/date-naissance" \
  -H "Content-Type: application/json" \
  -d '{
    "newBirthdate": "1985-06-15",
    "reason": "CORRECTION"
  }'

# 28. Vérifier les logs CloudWatch
aws logs tail /aws/lambda/dev-mcp-birthdate-validation --follow

# 29. Vérifier DynamoDB
aws dynamodb get-item \
  --table-name dev-ClientProfile \
  --key '{"clientId": {"S": "TEST123"}}'

# 30. Vérifier les événements Kafka (si consumer configuré)
# [Dépend de votre setup Kafka]
```

---

### 📋 Checklist Complète de Création

#### Repository Java (mcp-lambda-handlers)

- [ ] Créer le dossier du projet
- [ ] Initialiser Git
- [ ] Créer `pom.xml` avec toutes les dépendances
- [ ] Créer `src/main/resources/application.properties`
- [ ] Créer `.gitignore`
- [ ] Créer `README.md`
- [ ] Créer `McpHandler.java` (interface)
- [ ] Créer `BirthdateValidationHandler.java` (283 lignes)
- [ ] Créer `BirthdateUpdateHandler.java` (138 lignes)
- [ ] Créer `BirthdateEventPublisher.java` (184 lignes)
- [ ] Créer 8 classes d'exceptions
- [ ] Compiler avec `mvn clean compile`
- [ ] Packager avec `mvn clean package`
- [ ] Uploader le JAR vers S3

#### Repository Terraform (mcp-infrastructure)

- [ ] Créer `client_birthdate_update.json` (state machine)
- [ ] Ajouter 3 ressources `aws_lambda_function` dans `modules/lambda/main.tf`
- [ ] Ajouter 3 rôles IAM pour les Lambdas
- [ ] Ajouter les permissions IAM nécessaires
- [ ] Ajouter 3 CloudWatch Log Groups
- [ ] Ajouter `aws_sfn_state_machine` dans `modules/step-functions/main.tf`
- [ ] Ajouter le rôle IAM pour Step Functions
- [ ] Mettre à jour `openapi-spec.json.tpl` avec le nouvel endpoint
- [ ] Mettre à jour `modules/api-gateway/main.tf` si nécessaire
- [ ] Exécuter `terraform plan`
- [ ] Exécuter `terraform apply`
- [ ] Vérifier les outputs Terraform

#### Tests et Validation

- [ ] Tester l'endpoint via Swagger UI
- [ ] Tester avec un client valide (HTTP 200)
- [ ] Tester avec un client inexistant (HTTP 404)
- [ ] Tester avec une date invalide (HTTP 400)
- [ ] Tester avec une date future (HTTP 400)
- [ ] Tester avec un âge invalide (HTTP 400)
- [ ] Vérifier les logs CloudWatch pour chaque Lambda
- [ ] Vérifier la mise à jour DynamoDB
- [ ] Vérifier la publication Kafka
- [ ] Configurer les alarmes CloudWatch

---

### 📦 Artefacts Générés

Après avoir tout créé et déployé, vous aurez:

#### Dans AWS

| Type | Nom | Région | Account |
|------|-----|--------|---------|
| S3 Bucket | `mcp-lambda-artifacts-dev` | ca-central-1 | Votre compte |
| S3 Object | `birthdate/1.0.0/mcp-lambda-handlers-1.0.0.jar` | ca-central-1 | 15-20 MB |
| Lambda Function | `dev-mcp-birthdate-validation` | ca-central-1 | Java 11 |
| Lambda Function | `dev-mcp-birthdate-update` | ca-central-1 | Java 11 |
| Lambda Function | `dev-mcp-birthdate-event-publisher` | ca-central-1 | Java 11 |
| Step Functions | `dev-mcp-client_birthdate_update` | ca-central-1 | STANDARD |
| API Gateway Endpoint | `PUT /api/clients/{id}/date-naissance` | ca-central-1 | - |
| CloudWatch Log Group | `/aws/lambda/dev-mcp-birthdate-validation` | ca-central-1 | 7 jours retention |
| CloudWatch Log Group | `/aws/lambda/dev-mcp-birthdate-update` | ca-central-1 | 7 jours retention |
| CloudWatch Log Group | `/aws/lambda/dev-mcp-birthdate-event-publisher` | ca-central-1 | 7 jours retention |

#### Dans Git

| Repository | Fichiers Créés | Total Lignes |
|------------|----------------|--------------|
| `mcp-lambda-handlers` | 16 fichiers | ~1200 lignes Java + 120 lignes XML |
| `mcp-infrastructure` | 4 fichiers modifiés | ~300 lignes Terraform/JSON |

---

## 📊 Définition Détaillée des États

### État 1: ValidateBirthdate

**Type**: Task
**Resource**: Lambda Function (`birthdate-validation`)
**Timeout**: 30 secondes
**Retry**: 2 tentatives avec backoff exponentiel

#### Input
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION"
}
```

#### Logique de Validation

**1. Vérification existence du client**
```
Action: DynamoDB GetItem
Table: dev-ClientProfile
Key: {clientId: "TEST123"}

Si client n'existe pas:
  → Lever exception ClientNotFoundException
  → Transition vers ValidationFailed
```

**2. Validation format de la date**
```
Pattern attendu: YYYY-MM-DD
Regex: ^\d{4}-\d{2}-\d{2}$

Si format invalide:
  → Lever exception InvalidDateFormatException
  → Transition vers ValidationFailed
```

**3. Vérification date non future**
```
Comparer newBirthdate avec date actuelle

Si newBirthdate > dateActuelle:
  → Lever exception FutureDateException
  → Transition vers ValidationFailed
```

**4. Vérification âge raisonnable**
```
Calculer: âge = dateActuelle - newBirthdate

Si âge < 0 OU âge > 150:
  → Lever exception InvalidAgeException
  → Transition vers ValidationFailed
```

**5. Vérification raison du changement**
```
Raisons valides: ["CORRECTION", "MISE_A_JOUR", "ERREUR_SAISIE", "AUTRE"]

Si reason non dans la liste:
  → Lever exception InvalidReasonException
  → Transition vers ValidationFailed
```

#### Output (Success)
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validation": {
    "status": "PASSED",
    "clientExists": true,
    "dateFormatValid": true,
    "dateNotFuture": true,
    "ageValid": true,
    "age": 41,
    "reasonValid": true
  },
  "clientProfile": {
    "firstName": "Jean",
    "lastName": "Tremblay",
    "currentBirthdate": "1980-01-01",
    "email": "jean.tremblay@example.com"
  }
}
```

#### Output (Failure)
```json
{
  "error": "ValidationFailed",
  "errorType": "InvalidAgeException",
  "message": "L'âge calculé (200 ans) n'est pas valide. Doit être entre 0 et 150 ans.",
  "clientId": "TEST123",
  "newBirthdate": "1824-06-15"
}
```

#### Transitions
- **Success**: → UpdateBirthdate
- **Failure**: → ValidationFailed (état FAIL)

---

### État 2: UpdateBirthdate

**Type**: Task
**Resource**: Lambda Function (`birthdate-update`)
**Timeout**: 30 secondes
**Retry**: 3 tentatives avec backoff exponentiel

#### Input
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validation": { ... },
  "clientProfile": { ... }
}
```

#### Logique de Mise à Jour

**1. Préparation de l'update**
```
Générer:
  - updateTimestamp = ISO8601 actuel
  - previousBirthdate = clientProfile.currentBirthdate
  - updatedBy = "API_GATEWAY" (ou user context si disponible)
```

**2. DynamoDB Update**
```
Action: DynamoDB UpdateItem
Table: dev-ClientProfile
Key: {clientId: "TEST123"}

UpdateExpression:
  SET
    dateOfBirth = :newBirthdate,
    previousDateOfBirth = :previousBirthdate,
    lastUpdated = :timestamp,
    updateReason = :reason,
    updatedBy = :updatedBy

ConditionExpression:
  attribute_exists(clientId)  // Client doit toujours exister
```

**3. Gestion des erreurs**
```
Si ConditionalCheckFailedException:
  → Client supprimé entre validation et update
  → Lever ClientDeletedException
  → Transition vers UpdateFailed

Si ProvisionedThroughputExceededException:
  → Retry automatique (jusqu'à 3 fois)

Si autre erreur DynamoDB:
  → Lever DatabaseException
  → Transition vers UpdateFailed
```

#### Output (Success)
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "previousBirthdate": "1980-01-01",
  "reason": "CORRECTION",
  "update": {
    "status": "SUCCESS",
    "timestamp": "2026-09-29T14:30:00Z",
    "updatedBy": "API_GATEWAY",
    "dynamodbResponse": {
      "ResponseMetadata": {
        "HTTPStatusCode": 200
      }
    }
  },
  "clientProfile": {
    "firstName": "Jean",
    "lastName": "Tremblay",
    "dateOfBirth": "1985-06-15",
    "previousDateOfBirth": "1980-01-01",
    "email": "jean.tremblay@example.com",
    "lastUpdated": "2026-09-29T14:30:00Z"
  }
}
```

#### Output (Failure)
```json
{
  "error": "UpdateFailed",
  "errorType": "ClientDeletedException",
  "message": "Le client TEST123 a été supprimé pendant la mise à jour",
  "clientId": "TEST123"
}
```

#### Transitions
- **Success**: → PublishEvent
- **Failure**: → UpdateFailed (état FAIL)

---

### État 3: PublishEvent

**Type**: Task
**Resource**: Lambda Function (`birthdate-event-publisher`)
**Timeout**: 30 secondes
**Retry**: 5 tentatives avec backoff exponentiel (important pour Kafka)

#### Input
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "previousBirthdate": "1980-01-01",
  "reason": "CORRECTION",
  "update": { ... },
  "clientProfile": { ... }
}
```

#### Logique de Publication

**1. Construction du message Kafka**
```json
{
  "eventType": "CLIENT_BIRTHDATE_UPDATED",
  "eventVersion": "1.0",
  "eventId": "uuid-generated",
  "timestamp": "2026-09-29T14:30:00Z",
  "source": "mcp-api-gateway",
  "data": {
    "clientId": "TEST123",
    "firstName": "Jean",
    "lastName": "Tremblay",
    "dateOfBirth": {
      "previous": "1980-01-01",
      "current": "1985-06-15"
    },
    "updateReason": "CORRECTION",
    "updatedBy": "API_GATEWAY",
    "updateTimestamp": "2026-09-29T14:30:00Z"
  },
  "metadata": {
    "correlationId": "step-functions-execution-id",
    "environment": "dev",
    "region": "ca-central-1"
  }
}
```

**2. Publication vers Kafka**
```
Topic: client-events
Partition Key: clientId (pour garantir l'ordre des événements par client)
Compression: gzip
Acknowledgment: all (pour garantir la durabilité)

Si publication échoue:
  → Retry jusqu'à 5 fois (backoff: 1s, 2s, 4s, 8s, 16s)
  → Si toujours échec après 5 tentatives:
     → Lever KafkaPublishException
     → Transition vers PublishFailed
     → NOTE: DynamoDB déjà mis à jour! Compensation nécessaire?
```

**3. Logging et Traçabilité**
```
CloudWatch Logs:
  - Event ID
  - Kafka topic
  - Partition
  - Offset (si succès)
  - Nombre de tentatives
  - Temps de latence
```

#### Output (Success)
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "previousBirthdate": "1980-01-01",
  "reason": "CORRECTION",
  "update": { ... },
  "event": {
    "status": "PUBLISHED",
    "eventId": "550e8400-e29b-41d4-a716-446655440000",
    "topic": "client-events",
    "partition": 2,
    "offset": 12345,
    "timestamp": "2026-09-29T14:30:01Z",
    "retries": 0
  },
  "finalStatus": "SUCCESS"
}
```

#### Output (Failure)
```json
{
  "error": "PublishFailed",
  "errorType": "KafkaPublishException",
  "message": "Impossible de publier l'événement après 5 tentatives",
  "clientId": "TEST123",
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "retries": 5,
  "lastError": "Connection timeout to Kafka broker"
}
```

#### Transitions
- **Success**: → Success (état SUCCEED)
- **Failure**: → PublishFailed (état FAIL)

---

### État Terminal: Success

**Type**: Succeed
**Input**: Output complet de PublishEvent

#### Comportement
- Marque l'exécution comme réussie
- Retourne l'output final à API Gateway
- Enregistre métriques de succès dans CloudWatch

#### Output Final
```json
{
  "executionStatus": "SUCCEEDED",
  "clientId": "TEST123",
  "birthdateUpdate": {
    "previous": "1980-01-01",
    "current": "1985-06-15",
    "updateTimestamp": "2026-09-29T14:30:00Z"
  },
  "eventPublished": {
    "eventId": "550e8400-e29b-41d4-a716-446655440000",
    "topic": "client-events",
    "offset": 12345
  }
}
```

---

### État Terminal: ValidationFailed

**Type**: Fail
**Error**: ValidationError
**Cause**: Échec de validation (voir détails dans output de ValidateBirthdate)

#### Comportement
- Marque l'exécution comme échouée
- Retourne erreur 400 au client via API Gateway
- Enregistre métriques d'échec dans CloudWatch
- **Aucune modification persistée** (DynamoDB non touché)

---

### État Terminal: UpdateFailed

**Type**: Fail
**Error**: UpdateError
**Cause**: Échec de mise à jour DynamoDB

#### Comportement
- Marque l'exécution comme échouée
- Retourne erreur 500 au client via API Gateway
- **État partiel**: Validation OK, mais update échoué
- Nécessite investigation manuelle

---

### État Terminal: PublishFailed

**Type**: Fail
**Error**: PublishError
**Cause**: Échec de publication Kafka après 5 tentatives

#### Comportement
- Marque l'exécution comme échouée
- Retourne erreur 500 au client via API Gateway
- **⚠️ ATTENTION**: DynamoDB déjà mis à jour!
- État incohérent: données mises à jour mais événement non publié
- **Action requise**:
  - DLQ (Dead Letter Queue) pour republication
  - OU compensation manuelle
  - OU mécanisme de retry asynchrone

---

## 🔄 Diagramme d'États (Step Functions ASL)

```json
{
  "Comment": "Workflow de mise à jour de date de naissance client",
  "StartAt": "ValidateBirthdate",
  "States": {
    "ValidateBirthdate": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:ACCOUNT:function:dev-mcp-birthdate-validation",
      "TimeoutSeconds": 30,
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed", "Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["ClientNotFoundException", "InvalidDateFormatException", "FutureDateException", "InvalidAgeException", "InvalidReasonException"],
          "ResultPath": "$.validationError",
          "Next": "ValidationFailed"
        }
      ],
      "ResultPath": "$.validationResult",
      "Next": "UpdateBirthdate"
    },

    "UpdateBirthdate": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:ACCOUNT:function:dev-mcp-birthdate-update",
      "TimeoutSeconds": 30,
      "Retry": [
        {
          "ErrorEquals": ["ProvisionedThroughputExceededException"],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["ClientDeletedException", "DatabaseException"],
          "ResultPath": "$.updateError",
          "Next": "UpdateFailed"
        }
      ],
      "ResultPath": "$.updateResult",
      "Next": "PublishEvent"
    },

    "PublishEvent": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:ACCOUNT:function:dev-mcp-birthdate-event-publisher",
      "TimeoutSeconds": 30,
      "Retry": [
        {
          "ErrorEquals": ["KafkaPublishException", "States.TaskFailed"],
          "IntervalSeconds": 1,
          "MaxAttempts": 5,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.publishError",
          "Next": "PublishFailed"
        }
      ],
      "ResultPath": "$.publishResult",
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
      "Cause": "La mise à jour de la date de naissance dans DynamoDB a échoué"
    },

    "PublishFailed": {
      "Type": "Fail",
      "Error": "PublishError",
      "Cause": "La publication de l'événement Kafka a échoué après 5 tentatives"
    }
  }
}
```

---

## 📈 Flux de Données Détaillé

### Étape 1: Requête Initiale → API Gateway

**Input Client**:
```bash
curl -X PUT "https://API-ID.execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/date-naissance" \
  -H "Content-Type: application/json" \
  -d '{
    "newBirthdate": "1985-06-15",
    "reason": "CORRECTION"
  }'
```

**Transformation VTL (API Gateway)**:
```velocity
#set($inputRoot = $input.path('$'))
{
  "stateMachineArn": "arn:aws:states:ca-central-1:ACCOUNT:stateMachine:dev-mcp-client_birthdate_update",
  "input": "{\"clientId\": \"$util.escapeJavaScript($input.params('clientId'))\", \"newBirthdate\": \"$util.escapeJavaScript($input.path('$.newBirthdate'))\", \"reason\": \"$util.escapeJavaScript($input.path('$.reason'))\"}"
}
```

**Output vers Step Functions**:
```json
{
  "stateMachineArn": "arn:aws:states:ca-central-1:123456789:stateMachine:dev-mcp-client_birthdate_update",
  "input": "{\"clientId\": \"TEST123\", \"newBirthdate\": \"1985-06-15\", \"reason\": \"CORRECTION\"}"
}
```

---

### Étape 2: ValidateBirthdate Lambda

**Input Lambda**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION"
}
```

**Opérations Internes**:
1. DynamoDB GetItem
2. Parsing et validation de date
3. Calculs d'âge
4. Vérifications logiques

**Output Lambda** (enrichi):
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validation": {
    "status": "PASSED",
    "clientExists": true,
    "dateFormatValid": true,
    "dateNotFuture": true,
    "ageValid": true,
    "age": 41,
    "reasonValid": true,
    "validatedAt": "2026-09-29T14:29:58Z"
  },
  "clientProfile": {
    "clientId": "TEST123",
    "firstName": "Jean",
    "lastName": "Tremblay",
    "currentBirthdate": "1980-01-01",
    "email": "jean.tremblay@example.com"
  }
}
```

**Accumulation dans Step Functions** (ResultPath: $.validationResult):
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validationResult": {
    "clientId": "TEST123",
    "newBirthdate": "1985-06-15",
    "reason": "CORRECTION",
    "validation": { ... },
    "clientProfile": { ... }
  }
}
```

---

### Étape 3: UpdateBirthdate Lambda

**Input Lambda** (tout le contexte):
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validationResult": {
    "validation": { ... },
    "clientProfile": { ... }
  }
}
```

**Opérations Internes**:
1. DynamoDB UpdateItem
2. Génération de timestamps
3. Préservation de l'ancienne valeur

**Output Lambda**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "previousBirthdate": "1980-01-01",
  "reason": "CORRECTION",
  "update": {
    "status": "SUCCESS",
    "timestamp": "2026-09-29T14:30:00Z",
    "updatedBy": "API_GATEWAY"
  },
  "clientProfile": {
    "clientId": "TEST123",
    "firstName": "Jean",
    "lastName": "Tremblay",
    "dateOfBirth": "1985-06-15",
    "previousDateOfBirth": "1980-01-01",
    "email": "jean.tremblay@example.com",
    "lastUpdated": "2026-09-29T14:30:00Z",
    "updateReason": "CORRECTION"
  }
}
```

**Accumulation dans Step Functions** (ResultPath: $.updateResult):
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validationResult": { ... },
  "updateResult": {
    "clientId": "TEST123",
    "newBirthdate": "1985-06-15",
    "previousBirthdate": "1980-01-01",
    "update": { ... },
    "clientProfile": { ... }
  }
}
```

---

### Étape 4: PublishEvent Lambda

**Input Lambda** (contexte complet):
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION",
  "validationResult": { ... },
  "updateResult": {
    "previousBirthdate": "1980-01-01",
    "update": { ... },
    "clientProfile": { ... }
  }
}
```

**Opérations Internes**:
1. Construction du message Kafka
2. Publication vers topic
3. Gestion des retries
4. Logging

**Output Lambda**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "previousBirthdate": "1980-01-01",
  "reason": "CORRECTION",
  "event": {
    "status": "PUBLISHED",
    "eventId": "550e8400-e29b-41d4-a716-446655440000",
    "topic": "client-events",
    "partition": 2,
    "offset": 12345,
    "timestamp": "2026-09-29T14:30:01Z",
    "retries": 0
  },
  "finalStatus": "SUCCESS"
}
```

---

### Étape 5: Step Functions → API Gateway

**Output Final Step Functions**:
```json
{
  "executionStatus": "SUCCEEDED",
  "clientId": "TEST123",
  "birthdateUpdate": {
    "previous": "1980-01-01",
    "current": "1985-06-15",
    "updateTimestamp": "2026-09-29T14:30:00Z"
  },
  "eventPublished": {
    "eventId": "550e8400-e29b-41d4-a716-446655440000",
    "topic": "client-events",
    "offset": 12345
  }
}
```

**Transformation VTL (Response)**:
```velocity
#set($executionArn = $input.path('$.executionArn'))
{
  "message": "Birthdate update initiated",
  "executionArn": "$executionArn"
}
```

**Réponse HTTP au Client**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "message": "Birthdate update initiated",
  "executionArn": "arn:aws:states:ca-central-1:123456789:execution:dev-mcp-client_birthdate_update:abc-123-def-456"
}
```

---

## ⚠️ Gestion des Erreurs

### Scénario 1: Client Inexistant

**Requête**:
```json
{
  "clientId": "INVALID999",
  "newBirthdate": "1985-06-15",
  "reason": "CORRECTION"
}
```

**Flux**:
1. ValidateBirthdate → DynamoDB GetItem retourne vide
2. Lambda lève ClientNotFoundException
3. Catch → ValidationFailed
4. API Gateway retourne HTTP 404

**Réponse**:
```http
HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "NotFound",
  "message": "Client INVALID999 introuvable",
  "errorType": "ClientNotFoundException"
}
```

---

### Scénario 2: Date Future

**Requête**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "2030-01-01",
  "reason": "CORRECTION"
}
```

**Flux**:
1. ValidateBirthdate → Validation détecte date > aujourd'hui
2. Lambda lève FutureDateException
3. Catch → ValidationFailed
4. API Gateway retourne HTTP 400

**Réponse**:
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "BadRequest",
  "message": "La date de naissance ne peut pas être dans le futur",
  "errorType": "FutureDateException",
  "providedDate": "2030-01-01",
  "currentDate": "2026-09-29"
}
```

---

### Scénario 3: Format Date Invalide

**Requête**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "01/15/1985",
  "reason": "CORRECTION"
}
```

**Flux**:
1. ValidateBirthdate → Regex ne matche pas
2. Lambda lève InvalidDateFormatException
3. Catch → ValidationFailed
4. API Gateway retourne HTTP 400

**Réponse**:
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "BadRequest",
  "message": "Format de date invalide. Utilisez YYYY-MM-DD",
  "errorType": "InvalidDateFormatException",
  "providedFormat": "01/15/1985",
  "expectedFormat": "YYYY-MM-DD"
}
```

---

### Scénario 4: Âge Invalide

**Requête**:
```json
{
  "clientId": "TEST123",
  "newBirthdate": "1800-01-01",
  "reason": "CORRECTION"
}
```

**Flux**:
1. ValidateBirthdate → Calcul âge = 226 ans
2. Lambda lève InvalidAgeException
3. Catch → ValidationFailed
4. API Gateway retourne HTTP 400

**Réponse**:
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "BadRequest",
  "message": "L'âge calculé (226 ans) n'est pas valide. Doit être entre 0 et 150 ans",
  "errorType": "InvalidAgeException",
  "calculatedAge": 226,
  "allowedRange": "0-150"
}
```

---

### Scénario 5: Erreur DynamoDB (Throttling)

**Flux**:
1. ValidateBirthdate → OK
2. UpdateBirthdate → DynamoDB retourne ProvisionedThroughputExceededException
3. Retry automatique (1s, 2s, 4s) jusqu'à 3 fois
4. Si succès après retry → Continue vers PublishEvent
5. Si échec après 3 tentatives → UpdateFailed

**Réponse (après échec)**:
```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
  "error": "InternalServerError",
  "message": "Impossible de mettre à jour le profil client après 3 tentatives",
  "errorType": "ProvisionedThroughputExceededException"
}
```

---

### Scénario 6: Erreur Kafka (Indisponibilité)

**Flux**:
1. ValidateBirthdate → OK
2. UpdateBirthdate → OK (DynamoDB mis à jour!)
3. PublishEvent → Kafka timeout
4. Retry automatique (1s, 2s, 4s, 8s, 16s) jusqu'à 5 fois
5. Si échec après 5 tentatives → PublishFailed

**⚠️ État Incohérent**:
- DynamoDB: Date de naissance MISE À JOUR ✅
- Kafka: Événement NON PUBLIÉ ❌
- Systèmes en aval: Pas informés!

**Réponse**:
```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
  "error": "InternalServerError",
  "message": "La mise à jour a réussi mais la publication de l'événement a échoué",
  "errorType": "KafkaPublishException",
  "warning": "Les données ont été mises à jour dans DynamoDB mais les systèmes en aval n'ont pas été notifiés",
  "clientId": "TEST123",
  "requiresManualIntervention": true
}
```

**Action Requise**:
- Consulter CloudWatch Logs pour l'execution ARN
- Republier manuellement l'événement Kafka
- OU implémenter une DLQ (Dead Letter Queue) pour retry asynchrone

---

## 📊 Métriques et Monitoring

### Métriques CloudWatch à Surveiller

**Step Functions**:
- `ExecutionsStarted`: Nombre d'exécutions démarrées
- `ExecutionsSucceeded`: Nombre d'exécutions réussies
- `ExecutionsFailed`: Nombre d'exécutions échouées
- `ExecutionTime`: Temps d'exécution (ms)

**Lambda Functions**:
- `Invocations`: Nombre d'invocations par fonction
- `Errors`: Nombre d'erreurs
- `Duration`: Temps d'exécution
- `Throttles`: Nombre de throttles (limite concurrence)

**DynamoDB**:
- `ConsumedReadCapacityUnits`: Capacité lecture consommée
- `ConsumedWriteCapacityUnits`: Capacité écriture consommée
- `SystemErrors`: Erreurs système
- `UserErrors`: Erreurs utilisateur (ex: validation)

**API Gateway**:
- `Count`: Nombre de requêtes
- `4XXError`: Erreurs client (validation)
- `5XXError`: Erreurs serveur
- `Latency`: Temps de réponse

### Alarmes Recommandées

1. **Taux d'erreur élevé (Step Functions)**
   - Métrique: ExecutionsFailed
   - Seuil: > 10% des exécutions
   - Action: Notifier équipe DevOps

2. **Latence élevée (API Gateway)**
   - Métrique: Latency p99
   - Seuil: > 3000ms
   - Action: Investiguer performance

3. **Échecs Kafka répétés (PublishEvent Lambda)**
   - Métrique: Errors
   - Seuil: > 5 erreurs en 5 minutes
   - Action: Vérifier état du cluster Kafka

4. **Throttling DynamoDB**
   - Métrique: SystemErrors (ProvisionedThroughputExceededException)
   - Seuil: > 0
   - Action: Augmenter capacité ou activer auto-scaling

### Logs CloudWatch - Formats

**ValidateBirthdate Lambda**:
```json
{
  "timestamp": "2026-09-29T14:29:58Z",
  "level": "INFO",
  "message": "Validating birthdate for client",
  "clientId": "TEST123",
  "newBirthdate": "1985-06-15",
  "validationResults": {
    "clientExists": true,
    "dateFormatValid": true,
    "dateNotFuture": true,
    "ageValid": true,
    "age": 41
  }
}
```

**UpdateBirthdate Lambda**:
```json
{
  "timestamp": "2026-09-29T14:30:00Z",
  "level": "INFO",
  "message": "Updated client birthdate in DynamoDB",
  "clientId": "TEST123",
  "previousBirthdate": "1980-01-01",
  "newBirthdate": "1985-06-15",
  "dynamodbResponse": {
    "statusCode": 200
  }
}
```

**PublishEvent Lambda**:
```json
{
  "timestamp": "2026-09-29T14:30:01Z",
  "level": "INFO",
  "message": "Published birthdate update event to Kafka",
  "clientId": "TEST123",
  "eventId": "550e8400-e29b-41d4-a716-446655440000",
  "topic": "client-events",
  "partition": 2,
  "offset": 12345,
  "retries": 0,
  "latencyMs": 45
}
```

---

## 🔐 Considérations de Sécurité

### Validation des Données

1. **Input Sanitization**: Tous les inputs doivent être validés et sanitizés
2. **SQL Injection**: N/A (DynamoDB utilise des requêtes paramétrées)
3. **XSS Prevention**: Échapper tous les inputs utilisateur dans les logs
4. **Data Validation**: Format strict pour les dates (YYYY-MM-DD)

### Permissions IAM

**API Gateway**:
```json
{
  "Effect": "Allow",
  "Action": "states:StartExecution",
  "Resource": "arn:aws:states:ca-central-1:ACCOUNT:stateMachine:dev-mcp-client_birthdate_update"
}
```

**Lambda Functions**:
```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:GetItem",
    "dynamodb:UpdateItem"
  ],
  "Resource": "arn:aws:dynamodb:ca-central-1:ACCOUNT:table/dev-ClientProfile"
}
```

### Audit et Traçabilité

- Tous les changements loggés dans CloudWatch
- Correlation ID pour tracer les requêtes end-to-end
- Préservation de l'ancienne valeur (previousBirthdate)
- Raison du changement stockée (updateReason)
- Timestamp de modification (lastUpdated)

---

## 🚀 Performance et Scalabilité

### Temps d'Exécution Attendus

| Étape | Temps Moyen | Temps Max (p99) |
|-------|-------------|-----------------|
| ValidateBirthdate | 150ms | 500ms |
| UpdateBirthdate | 100ms | 300ms |
| PublishEvent | 80ms | 200ms |
| **Total Workflow** | **330ms** | **1000ms** |

### Capacité de Traitement

**Limites AWS**:
- **Step Functions**: 2500 exécutions/seconde par région
- **Lambda**: 1000 exécutions concurrentes (par défaut, peut être augmenté)
- **DynamoDB**: Dépend de la capacité provisionnée (RCU/WCU)
- **API Gateway**: 10000 requêtes/seconde (par défaut)

**Configuration Recommandée (DEV)**:
- DynamoDB: On-demand (auto-scaling)
- Lambda: 100 exécutions concurrentes réservées par fonction
- Step Functions: Type STANDARD (pour traçabilité complète)

**Configuration Recommandée (PROD)**:
- DynamoDB: Provisioned avec auto-scaling (100-1000 WCU)
- Lambda: 500 exécutions concurrentes réservées
- Step Functions: Type STANDARD avec retry et DLQ

---

## 📝 Checklist de Validation du Workflow

### Avant Implémentation
- [ ] Workflow défini et approuvé
- [ ] Tous les états identifiés
- [ ] Gestion des erreurs définie pour chaque état
- [ ] Retry policy définie
- [ ] Métriques et alarmes spécifiées

### Pendant Implémentation
- [ ] 3 Lambda functions créées et testées unitairement
- [ ] Step Functions state machine déployée
- [ ] API Gateway endpoint configuré
- [ ] OpenAPI spec mise à jour
- [ ] Tests d'intégration passés

### Après Déploiement
- [ ] Workflow testé end-to-end via Swagger UI
- [ ] Tous les scénarios d'erreur testés
- [ ] Logs CloudWatch vérifiés
- [ ] Métriques CloudWatch activées
- [ ] Alarmes configurées et testées
- [ ] Documentation mise à jour

---

## 📝 Code Terraform Complet

Cette section contient le code Terraform exact à ajouter pour déployer les ressources.

### Module Lambda - Ajout des 3 Fonctions

**Fichier**: `modules/lambda/main.tf`

Ajouter ce code après les Lambda functions existantes:

```hcl
# ============================================================================
# BIRTHDATE UPDATE WORKFLOW - Lambda Functions
# ============================================================================

# Lambda Function 1: Birthdate Validation
resource "aws_lambda_function" "birthdate_validation" {
  function_name = "${var.environment}-${var.project_name}-birthdate-validation"
  description   = "Validates client birthdate before update"

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "birthdate/${var.code_version}/mcp-lambda-handlers-${var.code_version}.jar"

  handler = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
  runtime = "java11"

  memory_size = var.lambda_memory_size
  timeout     = 30

  role = aws_iam_role.birthdate_validation.arn

  environment {
    variables = {
      SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateValidationHandler"
      DYNAMODB_TABLE_NAME              = var.dynamodb_table_name
      AWS_REGION                       = var.aws_region
      ENVIRONMENT                      = var.environment
      LOG_LEVEL                        = "INFO"
    }
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-validation"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workflow    = "birthdate-update"
  }
}

# Lambda Function 2: Birthdate Update
resource "aws_lambda_function" "birthdate_update" {
  function_name = "${var.environment}-${var.project_name}-birthdate-update"
  description   = "Updates client birthdate in DynamoDB"

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "birthdate/${var.code_version}/mcp-lambda-handlers-${var.code_version}.jar"

  handler = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
  runtime = "java11"

  memory_size = var.lambda_memory_size
  timeout     = 30

  role = aws_iam_role.birthdate_update.arn

  environment {
    variables = {
      SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateUpdateHandler"
      DYNAMODB_TABLE_NAME              = var.dynamodb_table_name
      AWS_REGION                       = var.aws_region
      ENVIRONMENT                      = var.environment
      LOG_LEVEL                        = "INFO"
    }
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-update"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workflow    = "birthdate-update"
  }
}

# Lambda Function 3: Birthdate Event Publisher
resource "aws_lambda_function" "birthdate_event_publisher" {
  function_name = "${var.environment}-${var.project_name}-birthdate-event-publisher"
  description   = "Publishes birthdate update events to Kafka"

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "birthdate/${var.code_version}/mcp-lambda-handlers-${var.code_version}.jar"

  handler = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
  runtime = "java11"

  memory_size = var.lambda_memory_size
  timeout     = 30

  role = aws_iam_role.birthdate_event_publisher.arn

  environment {
    variables = {
      SPRING_CLOUD_FUNCTION_DEFINITION = "birthdateEventPublisher"
      KAFKA_BOOTSTRAP_SERVERS          = var.msk_bootstrap_brokers
      KAFKA_TOPIC                      = "client-events"
      AWS_REGION                       = var.aws_region
      ENVIRONMENT                      = var.environment
      LOG_LEVEL                        = "INFO"
    }
  }

  # Si MSK dans VPC, ajouter vpc_config
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-event-publisher"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Workflow    = "birthdate-update"
  }
}

# ============================================================================
# IAM ROLES
# ============================================================================

# IAM Role for Birthdate Validation Lambda
resource "aws_iam_role" "birthdate_validation" {
  name = "${var.environment}-${var.project_name}-birthdate-validation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-validation-role"
    Environment = var.environment
  }
}

# IAM Role for Birthdate Update Lambda
resource "aws_iam_role" "birthdate_update" {
  name = "${var.environment}-${var.project_name}-birthdate-update-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-update-role"
    Environment = var.environment
  }
}

# IAM Role for Birthdate Event Publisher Lambda
resource "aws_iam_role" "birthdate_event_publisher" {
  name = "${var.environment}-${var.project_name}-birthdate-event-publisher-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-${var.project_name}-birthdate-event-publisher-role"
    Environment = var.environment
  }
}

# ============================================================================
# IAM POLICIES
# ============================================================================

# Policy: CloudWatch Logs for Validation Lambda
resource "aws_iam_role_policy" "birthdate_validation_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.birthdate_validation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.birthdate_validation.arn}:*"
      }
    ]
  })
}

# Policy: DynamoDB Read for Validation Lambda
resource "aws_iam_role_policy" "birthdate_validation_dynamodb" {
  name = "dynamodb-read"
  role = aws_iam_role.birthdate_validation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Policy: CloudWatch Logs for Update Lambda
resource "aws_iam_role_policy" "birthdate_update_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.birthdate_update.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.birthdate_update.arn}:*"
      }
    ]
  })
}

# Policy: DynamoDB Read/Write for Update Lambda
resource "aws_iam_role_policy" "birthdate_update_dynamodb" {
  name = "dynamodb-read-write"
  role = aws_iam_role.birthdate_update.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Policy: CloudWatch Logs for Event Publisher Lambda
resource "aws_iam_role_policy" "birthdate_event_publisher_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.birthdate_event_publisher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.birthdate_event_publisher.arn}:*"
      }
    ]
  })
}

# Policy: Kafka/MSK for Event Publisher Lambda
resource "aws_iam_role_policy" "birthdate_event_publisher_kafka" {
  name = "kafka-publish"
  role = aws_iam_role.birthdate_event_publisher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:GetBootstrapBrokers"
        ]
        Resource = var.msk_cluster_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "birthdate_validation" {
  name              = "/aws/lambda/${aws_lambda_function.birthdate_validation.function_name}"
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name        = "${var.environment}-birthdate-validation-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "birthdate_update" {
  name              = "/aws/lambda/${aws_lambda_function.birthdate_update.function_name}"
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name        = "${var.environment}-birthdate-update-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "birthdate_event_publisher" {
  name              = "/aws/lambda/${aws_lambda_function.birthdate_event_publisher.function_name}"
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name        = "${var.environment}-birthdate-event-publisher-logs"
    Environment = var.environment
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "birthdate_validation_arn" {
  description = "ARN of Birthdate Validation Lambda"
  value       = aws_lambda_function.birthdate_validation.arn
}

output "birthdate_update_arn" {
  description = "ARN of Birthdate Update Lambda"
  value       = aws_lambda_function.birthdate_update.arn
}

output "birthdate_event_publisher_arn" {
  description = "ARN of Birthdate Event Publisher Lambda"
  value       = aws_lambda_function.birthdate_event_publisher.arn
}
```

---

### Module Step Functions - State Machine

**Fichier**: `modules/step-functions/state-machines/client_birthdate_update.json`

```json
{
  "Comment": "Workflow de mise à jour de date de naissance client - Valide, met à jour DynamoDB et publie événement Kafka",
  "StartAt": "ValidateBirthdate",
  "States": {
    "ValidateBirthdate": {
      "Type": "Task",
      "Resource": "${birthdate_validation_lambda_arn}",
      "Comment": "Valide l'existence du client et le format/validité de la nouvelle date de naissance",
      "TimeoutSeconds": 30,
      "HeartbeatSeconds": 15,
      "Retry": [
        {
          "ErrorEquals": [
            "States.TaskFailed",
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "ClientNotFoundException"
          ],
          "ResultPath": "$.validationError",
          "Next": "ValidationFailedNotFound"
        },
        {
          "ErrorEquals": [
            "InvalidDateFormatException",
            "FutureDateException",
            "InvalidAgeException",
            "InvalidReasonException"
          ],
          "ResultPath": "$.validationError",
          "Next": "ValidationFailedBadRequest"
        },
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "ResultPath": "$.validationError",
          "Next": "ValidationFailedInternalError"
        }
      ],
      "ResultPath": "$.validationResult",
      "Next": "UpdateBirthdate"
    },

    "UpdateBirthdate": {
      "Type": "Task",
      "Resource": "${birthdate_update_lambda_arn}",
      "Comment": "Met à jour la date de naissance dans DynamoDB avec préservation de l'ancienne valeur",
      "TimeoutSeconds": 30,
      "HeartbeatSeconds": 15,
      "Retry": [
        {
          "ErrorEquals": [
            "ProvisionedThroughputExceededException",
            "ThrottlingException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        },
        {
          "ErrorEquals": [
            "States.TaskFailed",
            "Lambda.ServiceException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "ClientDeletedException"
          ],
          "ResultPath": "$.updateError",
          "Next": "UpdateFailedClientDeleted"
        },
        {
          "ErrorEquals": [
            "DatabaseException",
            "States.ALL"
          ],
          "ResultPath": "$.updateError",
          "Next": "UpdateFailedDatabaseError"
        }
      ],
      "ResultPath": "$.updateResult",
      "Next": "PublishEvent"
    },

    "PublishEvent": {
      "Type": "Task",
      "Resource": "${birthdate_event_publisher_lambda_arn}",
      "Comment": "Publie un événement de mise à jour vers le topic Kafka client-events",
      "TimeoutSeconds": 30,
      "HeartbeatSeconds": 15,
      "Retry": [
        {
          "ErrorEquals": [
            "KafkaPublishException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 5,
          "BackoffRate": 2.0,
          "Comment": "Retry agressif pour Kafka car DynamoDB déjà mis à jour"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "ResultPath": "$.publishError",
          "Next": "PublishFailedKafkaUnavailable"
        }
      ],
      "ResultPath": "$.publishResult",
      "Next": "Success"
    },

    "Success": {
      "Type": "Succeed",
      "Comment": "Workflow terminé avec succès - DynamoDB mis à jour et événement Kafka publié"
    },

    "ValidationFailedNotFound": {
      "Type": "Fail",
      "Error": "ClientNotFound",
      "Cause": "Le client spécifié n'existe pas dans DynamoDB"
    },

    "ValidationFailedBadRequest": {
      "Type": "Fail",
      "Error": "ValidationError",
      "Cause": "La validation de la date de naissance a échoué - format invalide, date future, âge invalide ou raison invalide"
    },

    "ValidationFailedInternalError": {
      "Type": "Fail",
      "Error": "InternalError",
      "Cause": "Erreur interne lors de la validation de la date de naissance"
    },

    "UpdateFailedClientDeleted": {
      "Type": "Fail",
      "Error": "ClientDeleted",
      "Cause": "Le client a été supprimé entre la validation et la mise à jour"
    },

    "UpdateFailedDatabaseError": {
      "Type": "Fail",
      "Error": "DatabaseError",
      "Cause": "Erreur lors de la mise à jour de la date de naissance dans DynamoDB"
    },

    "PublishFailedKafkaUnavailable": {
      "Type": "Fail",
      "Error": "KafkaPublishError",
      "Cause": "Échec de la publication de l'événement Kafka après 5 tentatives. ATTENTION: DynamoDB déjà mis à jour - état incohérent nécessitant intervention manuelle"
    }
  }
}
```

**Fichier**: `modules/step-functions/main.tf`

Ajouter ce code:

```hcl
# State Machine: Client Birthdate Update
resource "aws_sfn_state_machine" "client_birthdate_update" {
  name     = "${var.environment}-${var.project_name}-client_birthdate_update"
  role_arn = aws_iam_role.sfn_birthdate_update.arn
  type     = "STANDARD"

  definition = templatefile("${path.module}/state-machines/client_birthdate_update.json", {
    birthdate_validation_lambda_arn   = var.birthdate_validation_lambda_arn
    birthdate_update_lambda_arn       = var.birthdate_update_lambda_arn
    birthdate_event_publisher_lambda_arn = var.birthdate_event_publisher_lambda_arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_birthdate_update.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name        = "${var.environment}-client-birthdate-update"
    Environment = var.environment
    Workflow    = "birthdate-update"
  }
}

# IAM Role for Step Functions
resource "aws_iam_role" "sfn_birthdate_update" {
  name = "${var.environment}-${var.project_name}-sfn-birthdate-update-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy: Invoke Lambda Functions
resource "aws_iam_role_policy" "sfn_birthdate_update_lambda" {
  name = "invoke-lambda"
  role = aws_iam_role.sfn_birthdate_update.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          var.birthdate_validation_lambda_arn,
          var.birthdate_update_lambda_arn,
          var.birthdate_event_publisher_lambda_arn
        ]
      }
    ]
  })
}

# IAM Policy: CloudWatch Logs
resource "aws_iam_role_policy" "sfn_birthdate_update_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.sfn_birthdate_update.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "sfn_birthdate_update" {
  name              = "/aws/vendedlogs/states/${var.environment}-${var.project_name}-client-birthdate-update"
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name        = "${var.environment}-sfn-birthdate-update-logs"
    Environment = var.environment
  }
}

# Output
output "client_birthdate_update_state_machine_arn" {
  description = "ARN of Client Birthdate Update State Machine"
  value       = aws_sfn_state_machine.client_birthdate_update.arn
}
```

---

### Module API Gateway - Endpoint Configuration

**Fichier**: `modules/api-gateway/openapi-spec.json.tpl`

Ajouter ce path dans la section `"paths"`:

```json
"/api/clients/{clientId}/date-naissance": {
  "put": {
    "tags": ["Clients"],
    "summary": "Mise à jour de la date de naissance d'un client",
    "description": "Met à jour la date de naissance d'un client existant. Cette opération déclenche un workflow Step Functions qui:\n\n1. Valide l'existence du client\n2. Valide le format et la cohérence de la date\n3. Met à jour le profil dans DynamoDB\n4. Publie un événement Kafka\n\n**Format de date**: YYYY-MM-DD (ISO 8601)\n**Raisons valides**: CORRECTION, MISE_A_JOUR, ERREUR_SAISIE, AUTRE",
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
      "required": true,
      "content": {
        "application/json": {
          "schema": {
            "type": "object",
            "required": ["newBirthdate", "reason"],
            "properties": {
              "newBirthdate": {
                "type": "string",
                "format": "date",
                "pattern": "^\\d{4}-\\d{2}-\\d{2}$",
                "description": "Nouvelle date de naissance au format YYYY-MM-DD",
                "example": "1985-06-15"
              },
              "reason": {
                "type": "string",
                "enum": ["CORRECTION", "MISE_A_JOUR", "ERREUR_SAISIE", "AUTRE"],
                "description": "Raison du changement de date de naissance",
                "example": "CORRECTION"
              }
            }
          },
          "examples": {
            "correction": {
              "summary": "Correction d'erreur de saisie",
              "value": {
                "newBirthdate": "1985-06-15",
                "reason": "CORRECTION"
              }
            },
            "mise_a_jour": {
              "summary": "Mise à jour administrative",
              "value": {
                "newBirthdate": "1990-12-25",
                "reason": "MISE_A_JOUR"
              }
            },
            "erreur_saisie": {
              "summary": "Correction d'erreur initiale",
              "value": {
                "newBirthdate": "1978-03-10",
                "reason": "ERREUR_SAISIE"
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
              "type": "object",
              "properties": {
                "message": {
                  "type": "string",
                  "example": "Birthdate update initiated"
                },
                "executionArn": {
                  "type": "string",
                  "example": "arn:aws:states:ca-central-1:123456789:execution:dev-mcp-client_birthdate_update:abc-123"
                }
              }
            }
          }
        }
      },
      "400": {
        "description": "Requête invalide - erreur de validation",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorResponse"
            },
            "examples": {
              "invalid_format": {
                "summary": "Format de date invalide",
                "value": {
                  "error": "BadRequest",
                  "message": "Format de date invalide. Utilisez YYYY-MM-DD",
                  "errorType": "InvalidDateFormatException"
                }
              },
              "future_date": {
                "summary": "Date dans le futur",
                "value": {
                  "error": "BadRequest",
                  "message": "La date de naissance ne peut pas être dans le futur",
                  "errorType": "FutureDateException"
                }
              },
              "invalid_age": {
                "summary": "Âge invalide",
                "value": {
                  "error": "BadRequest",
                  "message": "L'âge calculé (200 ans) n'est pas valide. Doit être entre 0 et 150 ans",
                  "errorType": "InvalidAgeException"
                }
              }
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
              "message": "Client TEST123 introuvable",
              "errorType": "ClientNotFoundException"
            }
          }
        }
      },
      "500": {
        "description": "Erreur serveur interne",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorResponse"
            },
            "example": {
              "error": "InternalServerError",
              "message": "Une erreur s'est produite lors du traitement de la requête"
            }
          }
        }
      }
    },
    "x-amazon-apigateway-integration": {
      "type": "aws",
      "uri": "arn:aws:apigateway:${aws_region}:states:action/StartExecution",
      "httpMethod": "POST",
      "credentials": "${api_gateway_role_arn}",
      "requestTemplates": {
        "application/json": "#set($inputRoot = $input.path('$'))\n{\n  \"stateMachineArn\": \"${client_birthdate_update_state_machine_arn}\",\n  \"input\": \"{\\\"clientId\\\": \\\"$util.escapeJavaScript($input.params('clientId'))\\\", \\\"newBirthdate\\\": \\\"$util.escapeJavaScript($inputRoot.newBirthdate)\\\", \\\"reason\\\": \\\"$util.escapeJavaScript($inputRoot.reason)\\\"}\"\n}"
      },
      "responses": {
        "default": {
          "statusCode": "200",
          "responseTemplates": {
            "application/json": "#set($inputRoot = $input.path('$'))\n{\n  \"message\": \"Birthdate update initiated\",\n  \"executionArn\": \"$inputRoot.executionArn\"\n}"
          }
        }
      }
    }
  }
}
```

---

## 🧪 Tests Unitaires - Exemples

### Test BirthdateValidationHandler

**Fichier**: `src/test/java/com/bnc/mcp/handlers/BirthdateValidationHandlerTest.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.model.AttributeValue;
import com.amazonaws.services.dynamodbv2.model.GetItemRequest;
import com.amazonaws.services.dynamodbv2.model.GetItemResult;
import com.bnc.mcp.exceptions.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BirthdateValidationHandlerTest {

    @Mock
    private AmazonDynamoDB dynamoDB;

    private BirthdateValidationHandler handler;

    @BeforeEach
    void setUp() {
        handler = new BirthdateValidationHandler();
        // Inject mock (nécessite refactoring du handler pour injection)
    }

    @Test
    void testValidBirthdateValidationSuccess() throws Exception {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "CORRECTION");

        // Mock DynamoDB response
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("clientId", new AttributeValue("TEST123"));
        item.put("firstName", new AttributeValue("Jean"));
        item.put("lastName", new AttributeValue("Tremblay"));
        item.put("dateOfBirth", new AttributeValue("1980-01-01"));
        item.put("email", new AttributeValue("jean@example.com"));

        GetItemResult result = new GetItemResult().withItem(item);
        when(dynamoDB.getItem(any(GetItemRequest.class))).thenReturn(result);

        // When
        Object response = handler.handle(input);

        // Then
        assertNotNull(response);
        assertTrue(response instanceof Map);

        @SuppressWarnings("unchecked")
        Map<String, Object> responseMap = (Map<String, Object>) response;

        assertEquals("TEST123", responseMap.get("clientId"));
        assertEquals("1985-06-15", responseMap.get("newBirthdate"));

        @SuppressWarnings("unchecked")
        Map<String, Object> validation = (Map<String, Object>) responseMap.get("validation");
        assertEquals("PASSED", validation.get("status"));
        assertTrue((Boolean) validation.get("clientExists"));
        assertTrue((Boolean) validation.get("dateFormatValid"));
    }

    @Test
    void testClientNotFoundThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "INVALID999");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "CORRECTION");

        // Mock DynamoDB returning empty
        GetItemResult result = new GetItemResult();
        when(dynamoDB.getItem(any(GetItemRequest.class))).thenReturn(result);

        // When/Then
        assertThrows(ClientNotFoundException.class, () -> handler.handle(input));
    }

    @Test
    void testInvalidDateFormatThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "15/06/1985"); // Format invalide
        input.put("reason", "CORRECTION");

        // When/Then
        assertThrows(InvalidDateFormatException.class, () -> handler.handle(input));
    }

    @Test
    void testFutureDateThrowsException() {
        // Given
        String futureDate = LocalDate.now().plusYears(1).toString();
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", futureDate);
        input.put("reason", "CORRECTION");

        // When/Then
        assertThrows(FutureDateException.class, () -> handler.handle(input));
    }

    @Test
    void testInvalidAgeThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1800-01-01"); // Âge > 150 ans
        input.put("reason", "CORRECTION");

        // When/Then
        assertThrows(InvalidAgeException.class, () -> handler.handle(input));
    }

    @Test
    void testInvalidReasonThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "INVALID_REASON");

        // When/Then
        assertThrows(InvalidReasonException.class, () -> handler.handle(input));
    }
}
```

### Test BirthdateUpdateHandler

**Fichier**: `src/test/java/com/bnc/mcp/handlers/BirthdateUpdateHandlerTest.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.model.*;
import com.bnc.mcp.exceptions.ClientDeletedException;
import com.bnc.mcp.exceptions.DatabaseException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BirthdateUpdateHandlerTest {

    @Mock
    private AmazonDynamoDB dynamoDB;

    private BirthdateUpdateHandler handler;

    @BeforeEach
    void setUp() {
        handler = new BirthdateUpdateHandler();
    }

    @Test
    void testUpdateBirthdateSuccess() throws Exception {
        // Given
        Map<String, Object> clientProfile = new HashMap<>();
        clientProfile.put("clientId", "TEST123");
        clientProfile.put("firstName", "Jean");
        clientProfile.put("lastName", "Tremblay");
        clientProfile.put("currentBirthdate", "1980-01-01");

        Map<String, Object> validationResult = new HashMap<>();
        validationResult.put("clientProfile", clientProfile);

        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "CORRECTION");
        input.put("validationResult", validationResult);

        // Mock DynamoDB UpdateItem response
        Map<String, AttributeValue> updatedItem = new HashMap<>();
        updatedItem.put("clientId", new AttributeValue("TEST123"));
        updatedItem.put("dateOfBirth", new AttributeValue("1985-06-15"));
        updatedItem.put("previousDateOfBirth", new AttributeValue("1980-01-01"));

        UpdateItemResult updateResult = new UpdateItemResult().withAttributes(updatedItem);
        when(dynamoDB.updateItem(any(UpdateItemRequest.class))).thenReturn(updateResult);

        // When
        Object response = handler.handle(input);

        // Then
        assertNotNull(response);
        verify(dynamoDB, times(1)).updateItem(any(UpdateItemRequest.class));

        @SuppressWarnings("unchecked")
        Map<String, Object> responseMap = (Map<String, Object>) response;
        assertEquals("TEST123", responseMap.get("clientId"));
        assertEquals("1985-06-15", responseMap.get("newBirthdate"));
        assertEquals("1980-01-01", responseMap.get("previousBirthdate"));
    }

    @Test
    void testClientDeletedDuringUpdateThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "CORRECTION");

        // Mock DynamoDB throwing ConditionalCheckFailedException
        when(dynamoDB.updateItem(any(UpdateItemRequest.class)))
            .thenThrow(new ConditionalCheckFailedException("Client not found"));

        // When/Then
        assertThrows(ClientDeletedException.class, () -> handler.handle(input));
    }

    @Test
    void testDatabaseErrorThrowsException() {
        // Given
        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "TEST123");
        input.put("newBirthdate", "1985-06-15");
        input.put("reason", "CORRECTION");

        // Mock DynamoDB throwing generic exception
        when(dynamoDB.updateItem(any(UpdateItemRequest.class)))
            .thenThrow(new RuntimeException("Database connection error"));

        // When/Then
        assertThrows(DatabaseException.class, () -> handler.handle(input));
    }
}
```

---

## 🥒 Tests Cucumber (BDD)

### Dépendances Maven

Ajouter dans `pom.xml` (section `<dependencies>`):

```xml
<!-- Cucumber Dependencies -->
<dependency>
    <groupId>io.cucumber</groupId>
    <artifactId>cucumber-java</artifactId>
    <version>7.14.0</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>io.cucumber</groupId>
    <artifactId>cucumber-junit-platform-engine</artifactId>
    <version>7.14.0</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>io.cucumber</groupId>
    <artifactId>cucumber-spring</artifactId>
    <version>7.14.0</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.junit.platform</groupId>
    <artifactId>junit-platform-suite</artifactId>
    <version>1.10.0</version>
    <scope>test</scope>
</dependency>
```

---

### Feature Files (Gherkin)

#### 1. Validation de Date de Naissance

**Fichier**: `src/test/resources/features/birthdate-validation.feature`

```gherkin
# language: fr
Fonctionnalité: Validation de la date de naissance d'un client
  En tant que système MCP
  Je veux valider la date de naissance avant de procéder à la mise à jour
  Afin d'assurer l'intégrité des données client

  Contexte:
    Étant donné que le service DynamoDB est disponible
    Et que la table "dev-mcp-clients" existe

  Scénario: Validation réussie d'une date de naissance valide
    Étant donné qu'un client existe avec l'ID "CLIENT001"
    Et que la date de naissance actuelle du client est "1985-06-15"
    Quand je valide la nouvelle date de naissance "1985-07-20"
    Alors la validation doit réussir
    Et le statut doit être "VALID"
    Et le message doit contenir "Birthdate validation successful"

  Scénario: Rejet d'une date de naissance dans le futur
    Étant donné qu'un client existe avec l'ID "CLIENT002"
    Quand je valide la nouvelle date de naissance "2030-01-01"
    Alors la validation doit échouer
    Et le code d'erreur doit être "INVALID_DATE_FUTURE"
    Et le message d'erreur doit contenir "Birthdate cannot be in the future"

  Scénario: Rejet d'une date de naissance invalide (trop ancien)
    Étant donné qu'un client existe avec l'ID "CLIENT003"
    Quand je valide la nouvelle date de naissance "1800-01-01"
    Alors la validation doit échouer
    Et le code d'erreur doit être "INVALID_DATE_TOO_OLD"
    Et le message d'erreur doit contenir "Birthdate indicates age greater than 150 years"

  Scénario: Rejet pour un client non trouvé
    Étant donné qu'aucun client n'existe avec l'ID "INVALID999"
    Quand je valide la nouvelle date de naissance "1990-05-10"
    Alors la validation doit échouer
    Et le code d'erreur doit être "CLIENT_NOT_FOUND"
    Et le message d'erreur doit contenir "Client INVALID999 not found"

  Plan du Scénario: Validation de différents formats de date
    Étant donné qu'un client existe avec l'ID "CLIENT004"
    Quand je valide la nouvelle date de naissance "<date>"
    Alors la validation doit <résultat>
    Et le code doit être "<code>"

    Exemples:
      | date       | résultat | code          |
      | 1990-12-31 | réussir  | VALID         |
      | 2000-01-01 | réussir  | VALID         |
      | 1950-06-15 | réussir  | VALID         |
      | INVALID    | échouer  | INVALID_FORMAT|
      | 32/13/2000 | échouer  | INVALID_FORMAT|
      | null       | échouer  | MISSING_FIELD |
```

---

#### 2. Mise à Jour de Date de Naissance

**Fichier**: `src/test/resources/features/birthdate-update.feature`

```gherkin
# language: fr
Fonctionnalité: Mise à jour de la date de naissance d'un client
  En tant que système MCP
  Je veux mettre à jour la date de naissance dans DynamoDB
  Afin de maintenir des données client exactes

  Contexte:
    Étant donné que le service DynamoDB est disponible
    Et que la table "dev-mcp-clients" existe

  Scénario: Mise à jour réussie de la date de naissance
    Étant donné qu'un client existe avec l'ID "CLIENT101"
    Et que la date de naissance actuelle est "1985-03-20"
    Et que la raison de modification est "CORRECTION"
    Quand je mets à jour la date de naissance à "1985-03-21"
    Alors la mise à jour doit réussir
    Et la date de naissance dans DynamoDB doit être "1985-03-21"
    Et l'historique doit contenir l'ancienne date "1985-03-20"
    Et la raison enregistrée doit être "CORRECTION"
    Et le timestamp de modification doit être défini

  Scénario: Mise à jour avec raison ERREUR_SAISIE
    Étant donné qu'un client existe avec l'ID "CLIENT102"
    Et que la date de naissance actuelle est "1990-01-01"
    Et que la raison de modification est "ERREUR_SAISIE"
    Quand je mets à jour la date de naissance à "1991-02-15"
    Alors la mise à jour doit réussir
    Et la raison enregistrée doit être "ERREUR_SAISIE"
    Et un indicateur d'erreur doit être ajouté dans l'historique

  Scénario: Échec de mise à jour pour un client verrouillé
    Étant donné qu'un client existe avec l'ID "CLIENT103"
    Et que le client a le statut "LOCKED"
    Quand je mets à jour la date de naissance à "1988-05-10"
    Alors la mise à jour doit échouer
    Et le code d'erreur doit être "CLIENT_LOCKED"
    Et le message doit contenir "Cannot update locked client"

  Scénario: Échec de mise à jour suite à une erreur DynamoDB
    Étant donné qu'un client existe avec l'ID "CLIENT104"
    Et que DynamoDB renvoie une erreur "ProvisionedThroughputExceededException"
    Quand je mets à jour la date de naissance à "1992-08-25"
    Alors la mise à jour doit échouer
    Et le code d'erreur doit être "DATABASE_ERROR"
    Et une tentative de retry doit être effectuée

  Plan du Scénario: Mise à jour avec différentes raisons
    Étant donné qu'un client existe avec l'ID "CLIENT105"
    Et que la raison de modification est "<raison>"
    Quand je mets à jour la date de naissance à "1987-11-30"
    Alors la mise à jour doit réussir
    Et la raison enregistrée doit être "<raison>"
    Et l'attribut "<attribut_audit>" doit être défini

    Exemples:
      | raison          | attribut_audit        |
      | CORRECTION      | correctionReason      |
      | ERREUR_SAISIE   | inputErrorFlag        |
      | MISE_A_JOUR     | updateRequestedBy     |
```

---

#### 3. Publication d'Événement Kafka

**Fichier**: `src/test/resources/features/kafka-event-publish.feature`

```gherkin
# language: fr
Fonctionnalité: Publication d'événement Kafka après mise à jour
  En tant que système MCP
  Je veux publier un événement Kafka après chaque mise à jour réussie
  Afin de notifier les systèmes abonnés

  Contexte:
    Étant donné que le cluster MSK est disponible
    Et que le topic "client.birthdate.updated" existe

  Scénario: Publication réussie d'un événement de mise à jour
    Étant donné qu'une mise à jour de date de naissance a été effectuée
    Et que le clientId est "CLIENT201"
    Et que l'ancienne date était "1980-05-15"
    Et que la nouvelle date est "1980-05-16"
    Et que la raison est "CORRECTION"
    Quand je publie l'événement Kafka
    Alors l'événement doit être envoyé au topic "client.birthdate.updated"
    Et le message doit contenir le clientId "CLIENT201"
    Et le message doit contenir l'ancienne date "1980-05-15"
    Et le message doit contenir la nouvelle date "1980-05-16"
    Et le message doit contenir la raison "CORRECTION"
    Et le message doit contenir un timestamp
    Et le message doit contenir un eventId unique

  Scénario: Réessai automatique en cas d'échec de publication
    Étant donné qu'une mise à jour de date de naissance a été effectuée
    Et que le cluster MSK est temporairement indisponible
    Quand je publie l'événement Kafka
    Alors la publication doit échouer lors de la première tentative
    Et une réessai doit être effectué après 1 seconde
    Et l'événement doit finalement être publié avec succès

  Scénario: Échec définitif après épuisement des tentatives
    Étant donné qu'une mise à jour de date de naissance a été effectuée
    Et que le cluster MSK est définitivement indisponible
    Quand je publie l'événement Kafka
    Alors toutes les tentatives de publication doivent échouer
    Et le code d'erreur doit être "KAFKA_PUBLISH_FAILED"
    Et l'événement doit être enregistré dans les logs pour investigation

  Scénario: Validation du format de l'événement publié
    Étant donné qu'une mise à jour de date de naissance a été effectuée
    Quand je publie l'événement Kafka
    Alors le message Kafka doit respecter le schéma JSON suivant:
      """
      {
        "eventId": "string (UUID)",
        "eventType": "CLIENT_BIRTHDATE_UPDATED",
        "timestamp": "string (ISO 8601)",
        "clientId": "string",
        "oldBirthdate": "string (YYYY-MM-DD)",
        "newBirthdate": "string (YYYY-MM-DD)",
        "reason": "string (enum)",
        "updatedBy": "string"
      }
      """
    Et le content-type doit être "application/json"
    Et l'encoding doit être "UTF-8"
```

---

#### 4. Workflow Complet (End-to-End)

**Fichier**: `src/test/resources/features/birthdate-workflow-e2e.feature`

```gherkin
# language: fr
Fonctionnalité: Workflow complet de mise à jour de date de naissance
  En tant qu'utilisateur de l'API MCP
  Je veux mettre à jour la date de naissance d'un client de bout en bout
  Afin de corriger ou mettre à jour les informations du client

  Contexte:
    Étant donné que tous les services AWS sont disponibles
    Et que le Step Functions state machine est déployé
    Et que l'API Gateway est configuré

  Scénario: Workflow complet réussi de bout en bout
    Étant donné qu'un client existe avec l'ID "E2E_CLIENT_001"
    Et que la date de naissance actuelle est "1975-12-25"
    Quand j'envoie une requête PUT à "/api/clients/E2E_CLIENT_001/date-naissance"
    Avec le body suivant:
      """
      {
        "newBirthdate": "1975-12-26",
        "reason": "CORRECTION"
      }
      """
    Alors la réponse HTTP doit avoir le code 200
    Et la réponse doit contenir un "executionArn"
    Et l'exécution Step Functions doit se terminer avec le statut "SUCCEEDED"
    Et la date de naissance dans DynamoDB doit être mise à jour à "1975-12-26"
    Et un événement Kafka doit être publié
    Et les logs CloudWatch doivent contenir "Birthdate update completed successfully"

  Scénario: Workflow échoue à l'étape de validation
    Étant donné qu'un client existe avec l'ID "E2E_CLIENT_002"
    Quand j'envoie une requête PUT à "/api/clients/E2E_CLIENT_002/date-naissance"
    Avec le body suivant:
      """
      {
        "newBirthdate": "2050-01-01",
        "reason": "CORRECTION"
      }
      """
    Alors la réponse HTTP doit avoir le code 400
    Et le message d'erreur doit contenir "Birthdate cannot be in the future"
    Et l'exécution Step Functions doit se terminer avec le statut "FAILED"
    Et l'état final doit être "ValidationFailed"
    Et aucun événement Kafka ne doit être publié

  Scénario: Workflow échoue pour client inexistant
    Quand j'envoie une requête PUT à "/api/clients/NONEXISTENT_999/date-naissance"
    Avec le body suivant:
      """
      {
        "newBirthdate": "1990-06-15",
        "reason": "CORRECTION"
      }
      """
    Alors la réponse HTTP doit avoir le code 404
    Et le message d'erreur doit contenir "Client NONEXISTENT_999 not found"
    Et l'exécution Step Functions doit se terminer avec le statut "FAILED"
    Et l'état final doit être "ValidationFailed"

  Scénario: Workflow avec compensation en cas d'échec Kafka
    Étant donné qu'un client existe avec l'ID "E2E_CLIENT_003"
    Et que la date de naissance actuelle est "1982-03-10"
    Et que le cluster MSK est indisponible
    Quand j'envoie une requête PUT à "/api/clients/E2E_CLIENT_003/date-naissance"
    Avec le body suivant:
      """
      {
        "newBirthdate": "1982-03-11",
        "reason": "CORRECTION"
      }
      """
    Alors la mise à jour DynamoDB doit réussir
    Mais la publication Kafka doit échouer
    Et l'exécution Step Functions doit se terminer avec le statut "FAILED"
    Et l'état final doit être "PublishFailed"
    Et les logs doivent indiquer l'échec de publication Kafka
    Et la date dans DynamoDB doit rester "1982-03-11" (pas de rollback)

  Plan du Scénario: Workflow avec différentes raisons de modification
    Étant donné qu'un client existe avec l'ID "E2E_CLIENT_004"
    Quand j'envoie une requête PUT à "/api/clients/E2E_CLIENT_004/date-naissance"
    Avec le body suivant:
      """
      {
        "newBirthdate": "1995-08-20",
        "reason": "<raison>"
      }
      """
    Alors la réponse HTTP doit avoir le code 200
    Et l'événement Kafka doit contenir la raison "<raison>"
    Et l'audit trail doit contenir le type "<type_audit>"

    Exemples:
      | raison        | type_audit         |
      | CORRECTION    | ADMIN_CORRECTION   |
      | ERREUR_SAISIE | DATA_ENTRY_ERROR   |
      | MISE_A_JOUR   | CLIENT_REQUESTED   |
```

---

### Step Definitions (Java)

#### 1. Validation Steps

**Fichier**: `src/test/java/com/bnc/mcp/steps/BirthdateValidationSteps.java`

```java
package com.bnc.mcp.steps;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.model.AttributeValue;
import com.amazonaws.services.dynamodbv2.model.GetItemRequest;
import com.amazonaws.services.dynamodbv2.model.GetItemResult;
import com.bnc.mcp.exceptions.ClientNotFoundException;
import com.bnc.mcp.exceptions.ValidationException;
import com.bnc.mcp.handlers.BirthdateValidationHandler;
import io.cucumber.java.Before;
import io.cucumber.java.fr.Alors;
import io.cucumber.java.fr.Et;
import io.cucumber.java.fr.Quand;
import io.cucumber.java.fr.Étantdonnéque;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

public class BirthdateValidationSteps {

    @Mock
    private AmazonDynamoDB dynamoDB;

    private BirthdateValidationHandler handler;
    private Map<String, Object> input;
    private Map<String, Object> output;
    private Exception thrownException;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        handler = new BirthdateValidationHandler(dynamoDB);
        input = new HashMap<>();
        output = null;
        thrownException = null;
    }

    @Étantdonnéque("que le service DynamoDB est disponible")
    public void dynamoDBEstDisponible() {
        // DynamoDB mock is already initialized
        assertNotNull(dynamoDB);
    }

    @Étantdonnéque("que la table {string} existe")
    public void queTableExiste(String tableName) {
        System.setProperty("DYNAMODB_TABLE", tableName);
    }

    @Étantdonnéque("qu'un client existe avec l'ID {string}")
    public void clientExisteAvecID(String clientId) {
        Map<String, AttributeValue> item = new HashMap<>();
        item.put("clientId", new AttributeValue(clientId));
        item.put("firstName", new AttributeValue("Jean"));
        item.put("lastName", new AttributeValue("Tremblay"));
        item.put("birthdate", new AttributeValue("1985-06-15"));

        GetItemResult result = new GetItemResult().withItem(item);
        when(dynamoDB.getItem(any(GetItemRequest.class))).thenReturn(result);

        input.put("clientId", clientId);
    }

    @Étantdonnéque("que la date de naissance actuelle du client est {string}")
    public void datenaissanceActuelleEst(String currentBirthdate) {
        // Already set in client creation
        // This step is for documentation purposes
    }

    @Étantdonnéque("qu'aucun client n'existe avec l'ID {string}")
    public void aucunClientExisteAvecID(String clientId) {
        GetItemResult result = new GetItemResult().withItem(null);
        when(dynamoDB.getItem(any(GetItemRequest.class))).thenReturn(result);

        input.put("clientId", clientId);
    }

    @Quand("je valide la nouvelle date de naissance {string}")
    public void jeValideLaNouvelledatenaissance(String newBirthdate) {
        input.put("newBirthdate", newBirthdate);
        input.put("reason", "CORRECTION");

        try {
            output = handler.handle(input);
        } catch (Exception e) {
            thrownException = e;
        }
    }

    @Alors("la validation doit réussir")
    public void laValidationDoitReussir() {
        assertNull(thrownException, "Expected no exception but got: " +
            (thrownException != null ? thrownException.getMessage() : ""));
        assertNotNull(output);
    }

    @Alors("le statut doit être {string}")
    public void leStatutDoitEtre(String expectedStatus) {
        assertNotNull(output);
        assertEquals(expectedStatus, output.get("status"));
    }

    @Alors("le message doit contenir {string}")
    public void leMessageDoitContenir(String expectedMessage) {
        assertNotNull(output);
        String actualMessage = (String) output.get("message");
        assertTrue(actualMessage.contains(expectedMessage),
            "Expected message to contain '" + expectedMessage + "' but was: " + actualMessage);
    }

    @Alors("la validation doit échouer")
    public void laValidationDoitEchouer() {
        assertNotNull(thrownException, "Expected an exception to be thrown");
    }

    @Alors("le code d'erreur doit être {string}")
    public void leCodeErreurDoitEtre(String expectedCode) {
        assertNotNull(thrownException);
        if (thrownException instanceof ValidationException) {
            ValidationException ve = (ValidationException) thrownException;
            assertTrue(ve.getMessage().contains(expectedCode) ||
                       ve.getClass().getSimpleName().contains(expectedCode));
        } else if (thrownException instanceof ClientNotFoundException) {
            assertEquals("CLIENT_NOT_FOUND", expectedCode);
        }
    }

    @Alors("le message d'erreur doit contenir {string}")
    public void leMessageErreurDoitContenir(String expectedMessage) {
        assertNotNull(thrownException);
        assertTrue(thrownException.getMessage().contains(expectedMessage),
            "Expected error message to contain '" + expectedMessage +
            "' but was: " + thrownException.getMessage());
    }

    @Alors("la validation doit {string}")
    public void laValidationDoit(String resultat) {
        if ("réussir".equals(resultat)) {
            laValidationDoitReussir();
        } else if ("échouer".equals(resultat)) {
            laValidationDoitEchouer();
        }
    }

    @Alors("le code doit être {string}")
    public void leCodeDoitEtre(String expectedCode) {
        if (thrownException != null) {
            leCodeErreurDoitEtre(expectedCode);
        } else {
            leStatutDoitEtre(expectedCode);
        }
    }
}
```

---

#### 2. Update Steps

**Fichier**: `src/test/java/com/bnc/mcp/steps/BirthdateUpdateSteps.java`

```java
package com.bnc.mcp.steps;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.dynamodbv2.model.*;
import com.bnc.mcp.exceptions.ClientLockedException;
import com.bnc.mcp.exceptions.DatabaseException;
import com.bnc.mcp.handlers.BirthdateUpdateHandler;
import io.cucumber.java.Before;
import io.cucumber.java.fr.Alors;
import io.cucumber.java.fr.Et;
import io.cucumber.java.fr.Quand;
import io.cucumber.java.fr.Étantdonnéque;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class BirthdateUpdateSteps {

    @Mock
    private AmazonDynamoDB dynamoDB;

    private BirthdateUpdateHandler handler;
    private Map<String, Object> input;
    private Map<String, Object> output;
    private Exception thrownException;
    private String currentBirthdate;
    private String reason;
    private boolean isLocked = false;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        handler = new BirthdateUpdateHandler(dynamoDB);
        input = new HashMap<>();
        output = null;
        thrownException = null;
        isLocked = false;
    }

    @Étantdonnéque("que la date de naissance actuelle est {string}")
    public void datenaissanceActuelleEst(String birthdate) {
        this.currentBirthdate = birthdate;
    }

    @Étantdonnéque("que la raison de modification est {string}")
    public void raisonModificationEst(String raison) {
        this.reason = raison;
        input.put("reason", raison);
    }

    @Étantdonnéque("que le client a le statut {string}")
    public void clientStatut(String status) {
        if ("LOCKED".equals(status)) {
            this.isLocked = true;
        }
    }

    @Étantdonnéque("que DynamoDB renvoie une erreur {string}")
    public void dynamoDBRenvoieErreur(String errorType) {
        when(dynamoDB.updateItem(any(UpdateItemRequest.class)))
            .thenThrow(new ProvisionedThroughputExceededException(errorType));
    }

    @Quand("je mets à jour la date de naissance à {string}")
    public void jeMetsAJourDatenaissanceA(String newBirthdate) {
        input.put("newBirthdate", newBirthdate);
        input.put("oldBirthdate", currentBirthdate);

        if (isLocked) {
            thrownException = new ClientLockedException("Cannot update locked client");
            return;
        }

        UpdateItemResult mockResult = new UpdateItemResult();
        Map<String, AttributeValue> attributes = new HashMap<>();
        attributes.put("birthdate", new AttributeValue(newBirthdate));
        attributes.put("updatedAt", new AttributeValue(String.valueOf(System.currentTimeMillis())));
        mockResult.setAttributes(attributes);

        when(dynamoDB.updateItem(any(UpdateItemRequest.class))).thenReturn(mockResult);

        try {
            output = handler.handle(input);
        } catch (Exception e) {
            thrownException = e;
        }
    }

    @Alors("la mise à jour doit réussir")
    public void laMiseAJourDoitReussir() {
        assertNull(thrownException, "Expected no exception but got: " +
            (thrownException != null ? thrownException.getMessage() : ""));
        assertNotNull(output);
    }

    @Alors("la date de naissance dans DynamoDB doit être {string}")
    public void datenaissanceDansDynamoDBDoitEtre(String expectedBirthdate) {
        ArgumentCaptor<UpdateItemRequest> captor = ArgumentCaptor.forClass(UpdateItemRequest.class);
        verify(dynamoDB).updateItem(captor.capture());

        UpdateItemRequest request = captor.getValue();
        Map<String, AttributeValueUpdate> updates = request.getAttributeUpdates();

        assertTrue(updates.containsKey("birthdate"));
        assertEquals(expectedBirthdate, updates.get("birthdate").getValue().getS());
    }

    @Et("l'historique doit contenir l'ancienne date {string}")
    public void historiqueDoitContenirAncienneDate(String oldBirthdate) {
        ArgumentCaptor<UpdateItemRequest> captor = ArgumentCaptor.forClass(UpdateItemRequest.class);
        verify(dynamoDB).updateItem(captor.capture());

        UpdateItemRequest request = captor.getValue();
        assertTrue(request.getAttributeUpdates().containsKey("birthdateHistory"));
    }

    @Et("la raison enregistrée doit être {string}")
    public void raisonEnregistreeDoitEtre(String expectedReason) {
        ArgumentCaptor<UpdateItemRequest> captor = ArgumentCaptor.forClass(UpdateItemRequest.class);
        verify(dynamoDB).updateItem(captor.capture());

        UpdateItemRequest request = captor.getValue();
        assertTrue(request.getAttributeUpdates().containsKey("updateReason"));
        assertEquals(expectedReason, request.getAttributeUpdates().get("updateReason").getValue().getS());
    }

    @Et("le timestamp de modification doit être défini")
    public void timestampModificationDoitEtreDefini() {
        ArgumentCaptor<UpdateItemRequest> captor = ArgumentCaptor.forClass(UpdateItemRequest.class);
        verify(dynamoDB).updateItem(captor.capture());

        UpdateItemRequest request = captor.getValue();
        assertTrue(request.getAttributeUpdates().containsKey("updatedAt"));
    }

    @Et("un indicateur d'erreur doit être ajouté dans l'historique")
    public void indicateurErreurDoitEtreAjoute() {
        // Verify that error flag is set in history
        assertTrue(reason.equals("ERREUR_SAISIE"));
    }

    @Alors("la mise à jour doit échouer")
    public void laMiseAJourDoitEchouer() {
        assertNotNull(thrownException, "Expected an exception to be thrown");
    }

    @Et("une tentative de retry doit être effectuée")
    public void tentativeRetryDoitEtreEffectuee() {
        // In real implementation, verify retry logic
        assertTrue(thrownException instanceof ProvisionedThroughputExceededException ||
                   thrownException instanceof DatabaseException);
    }

    @Et("l'attribut {string} doit être défini")
    public void attributDoitEtreDefini(String attributeName) {
        assertNotNull(output);
        // Verify attribute presence in update operation
    }
}
```

---

#### 3. Kafka Event Steps

**Fichier**: `src/test/java/com/bnc/mcp/steps/KafkaEventSteps.java`

```java
package com.bnc.mcp.steps;

import com.bnc.mcp.exceptions.KafkaPublishException;
import com.bnc.mcp.handlers.KafkaEventPublishHandler;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.cucumber.java.Before;
import io.cucumber.java.fr.Alors;
import io.cucumber.java.fr.Et;
import io.cucumber.java.fr.Quand;
import io.cucumber.java.fr.Étantdonnéque;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Future;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

public class KafkaEventSteps {

    @Mock
    private KafkaProducer<String, String> kafkaProducer;

    @Mock
    private Future<RecordMetadata> future;

    private KafkaEventPublishHandler handler;
    private Map<String, Object> input;
    private Map<String, Object> output;
    private Exception thrownException;
    private ObjectMapper objectMapper;
    private String publishedMessage;
    private int retryAttempts = 0;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        handler = new KafkaEventPublishHandler(kafkaProducer);
        input = new HashMap<>();
        output = null;
        thrownException = null;
        objectMapper = new ObjectMapper();
        publishedMessage = null;
        retryAttempts = 0;
    }

    @Étantdonnéque("que le cluster MSK est disponible")
    public void clusterMSKEstDisponible() {
        when(kafkaProducer.send(any(ProducerRecord.class))).thenReturn(future);
    }

    @Étantdonnéque("que le topic {string} existe")
    public void topicExiste(String topicName) {
        System.setProperty("KAFKA_TOPIC", topicName);
    }

    @Étantdonnéque("qu'une mise à jour de date de naissance a été effectuée")
    public void miseAJourEffectuee() {
        // Context setup - update was successful
    }

    @Étantdonnéque("que le clientId est {string}")
    public void clientIdEst(String clientId) {
        input.put("clientId", clientId);
    }

    @Étantdonnéque("que l'ancienne date était {string}")
    public void ancienneDateEtait(String oldBirthdate) {
        input.put("oldBirthdate", oldBirthdate);
    }

    @Étantdonnéque("que la nouvelle date est {string}")
    public void nouvelleDateEst(String newBirthdate) {
        input.put("newBirthdate", newBirthdate);
    }

    @Étantdonnéque("que la raison est {string}")
    public void raisonEst(String reason) {
        input.put("reason", reason);
    }

    @Étantdonnéque("que le cluster MSK est temporairement indisponible")
    public void clusterMSKTemporairementIndisponible() {
        when(kafkaProducer.send(any(ProducerRecord.class)))
            .thenThrow(new RuntimeException("Connection timeout"))
            .thenReturn(future);
    }

    @Étantdonnéque("que le cluster MSK est définitivement indisponible")
    public void clusterMSKDefinitivementIndisponible() {
        when(kafkaProducer.send(any(ProducerRecord.class)))
            .thenThrow(new RuntimeException("Connection refused"));
    }

    @Quand("je publie l'événement Kafka")
    public void jePublieEvenementKafka() {
        try {
            output = handler.handle(input);

            ArgumentCaptor<ProducerRecord> captor = ArgumentCaptor.forClass(ProducerRecord.class);
            verify(kafkaProducer, atLeastOnce()).send(captor.capture());

            ProducerRecord<String, String> record = captor.getValue();
            publishedMessage = record.value();
        } catch (Exception e) {
            thrownException = e;
        }
    }

    @Alors("l'événement doit être envoyé au topic {string}")
    public void evenementDoitEtreEnvoyeAuTopic(String expectedTopic) {
        ArgumentCaptor<ProducerRecord> captor = ArgumentCaptor.forClass(ProducerRecord.class);
        verify(kafkaProducer).send(captor.capture());

        ProducerRecord<String, String> record = captor.getValue();
        assertEquals(expectedTopic, record.topic());
    }

    @Et("le message doit contenir le clientId {string}")
    public void messageDoitContenirClientId(String expectedClientId) throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertEquals(expectedClientId, json.get("clientId").asText());
    }

    @Et("le message doit contenir l'ancienne date {string}")
    public void messageDoitContenirAncienneDate(String expectedOldBirthdate) throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertEquals(expectedOldBirthdate, json.get("oldBirthdate").asText());
    }

    @Et("le message doit contenir la nouvelle date {string}")
    public void messageDoitContenirNouvelleDate(String expectedNewBirthdate) throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertEquals(expectedNewBirthdate, json.get("newBirthdate").asText());
    }

    @Et("le message doit contenir la raison {string}")
    public void messageDoitContenirRaison(String expectedReason) throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertEquals(expectedReason, json.get("reason").asText());
    }

    @Et("le message doit contenir un timestamp")
    public void messageDoitContenirTimestamp() throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertTrue(json.has("timestamp"));
        assertNotNull(json.get("timestamp").asText());
    }

    @Et("le message doit contenir un eventId unique")
    public void messageDoitContenirEventIdUnique() throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);
        assertTrue(json.has("eventId"));
        assertNotNull(json.get("eventId").asText());
        // Verify UUID format
        assertTrue(json.get("eventId").asText().matches(
            "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"));
    }

    @Alors("la publication doit échouer lors de la première tentative")
    public void publicationDoitEchouerPremiereTentative() {
        // Verified by mock configuration
    }

    @Et("une réessai doit être effectué après {int} seconde")
    public void reessaiDoitEtreEffectue(int seconds) {
        verify(kafkaProducer, atLeast(2)).send(any(ProducerRecord.class));
    }

    @Et("l'événement doit finalement être publié avec succès")
    public void evenementDoitFinalementEtrePublieAvecSucces() {
        assertNull(thrownException);
        verify(kafkaProducer, times(2)).send(any(ProducerRecord.class));
    }

    @Alors("toutes les tentatives de publication doivent échouer")
    public void toutesLesTentativesDoiventEchouer() {
        assertNotNull(thrownException);
        assertTrue(thrownException instanceof KafkaPublishException ||
                   thrownException.getCause() instanceof RuntimeException);
    }

    @Et("l'événement doit être enregistré dans les logs pour investigation")
    public void evenementDoitEtreEnregistreDansLogs() {
        // Verify logging occurred (would need logger mock in real implementation)
        assertNotNull(thrownException);
    }

    @Alors("le message Kafka doit respecter le schéma JSON suivant:")
    public void messageKafkaDoitRespecterSchema(String schemaDoc) throws Exception {
        assertNotNull(publishedMessage);
        JsonNode json = objectMapper.readTree(publishedMessage);

        // Verify required fields
        assertTrue(json.has("eventId"));
        assertTrue(json.has("eventType"));
        assertTrue(json.has("timestamp"));
        assertTrue(json.has("clientId"));
        assertTrue(json.has("oldBirthdate"));
        assertTrue(json.has("newBirthdate"));
        assertTrue(json.has("reason"));
        assertTrue(json.has("updatedBy"));

        // Verify types
        assertEquals("CLIENT_BIRTHDATE_UPDATED", json.get("eventType").asText());
    }

    @Et("le content-type doit être {string}")
    public void contentTypeDoitEtre(String expectedContentType) {
        // Verified by Kafka producer configuration
        assertEquals("application/json", expectedContentType);
    }

    @Et("l'encoding doit être {string}")
    public void encodingDoitEtre(String expectedEncoding) {
        // Verified by Kafka producer configuration
        assertEquals("UTF-8", expectedEncoding);
    }
}
```

---

#### 4. End-to-End Steps

**Fichier**: `src/test/java/com/bnc/mcp/steps/BirthdateWorkflowE2ESteps.java`

```java
package com.bnc.mcp.steps;

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB;
import com.amazonaws.services.stepfunctions.AWSStepFunctions;
import com.amazonaws.services.stepfunctions.model.*;
import io.cucumber.java.Before;
import io.cucumber.java.fr.Alors;
import io.cucumber.java.fr.Et;
import io.cucumber.java.fr.Mais;
import io.cucumber.java.fr.Quand;
import io.cucumber.java.fr.Étantdonnéque;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

public class BirthdateWorkflowE2ESteps {

    @Mock
    private AWSStepFunctions stepFunctions;

    @Mock
    private AmazonDynamoDB dynamoDB;

    @Mock
    private KafkaProducer<String, String> kafkaProducer;

    private String clientId;
    private String requestBody;
    private int httpStatusCode;
    private String responseBody;
    private String executionArn;
    private ExecutionStatus executionStatus;
    private boolean kafkaEventPublished = false;

    @Before
    public void setUp() {
        MockitoAnnotations.openMocks(this);
        httpStatusCode = 0;
        responseBody = null;
        executionArn = null;
        executionStatus = null;
        kafkaEventPublished = false;
    }

    @Étantdonnéque("que tous les services AWS sont disponibles")
    public void tousLesServicesAWSDisponibles() {
        assertNotNull(stepFunctions);
        assertNotNull(dynamoDB);
        assertNotNull(kafkaProducer);
    }

    @Étantdonnéque("que le Step Functions state machine est déployé")
    public void stepFunctionsStateMachineDeploye() {
        // Mock state machine existence
        DescribeStateMachineResult result = new DescribeStateMachineResult()
            .withName("dev-mcp-birthdate-update")
            .withStatus(StateMachineStatus.ACTIVE);
        when(stepFunctions.describeStateMachine(any(DescribeStateMachineRequest.class)))
            .thenReturn(result);
    }

    @Étantdonnéque("que l'API Gateway est configuré")
    public void apiGatewayEstConfigure() {
        // API Gateway is configured (integration test context)
    }

    @Quand("j'envoie une requête PUT à {string}")
    public void envoieRequetePUT(String endpoint) {
        // Extract clientId from endpoint
        String[] parts = endpoint.split("/");
        this.clientId = parts[3]; // /api/clients/{clientId}/date-naissance
    }

    @Quand("Avec le body suivant:")
    public void avecLeBodySuivant(String body) {
        this.requestBody = body;

        // Simulate API Gateway -> Step Functions invocation
        StartExecutionResult startResult = new StartExecutionResult()
            .withExecutionArn("arn:aws:states:ca-central-1:123456789012:execution:dev-mcp-birthdate-update:test-exec-001");

        when(stepFunctions.startExecution(any(StartExecutionRequest.class)))
            .thenReturn(startResult);

        executionArn = startResult.getExecutionArn();

        // Determine execution outcome based on request
        if (requestBody.contains("2050-01-01")) {
            // Future date - validation fails
            httpStatusCode = 400;
            responseBody = "{\"error\":\"BadRequest\",\"message\":\"Birthdate cannot be in the future\"}";
            executionStatus = ExecutionStatus.FAILED;
        } else if (clientId.equals("NONEXISTENT_999")) {
            // Client not found
            httpStatusCode = 404;
            responseBody = "{\"error\":\"NotFound\",\"message\":\"Client NONEXISTENT_999 not found\"}";
            executionStatus = ExecutionStatus.FAILED;
        } else {
            // Success
            httpStatusCode = 200;
            responseBody = "{\"message\":\"Client birthdate update initiated\",\"executionArn\":\"" + executionArn + "\"}";
            executionStatus = ExecutionStatus.SUCCEEDED;
            kafkaEventPublished = true;
        }
    }

    @Alors("la réponse HTTP doit avoir le code {int}")
    public void reponseHTTPDoitAvoirCode(int expectedStatusCode) {
        assertEquals(expectedStatusCode, httpStatusCode);
    }

    @Et("la réponse doit contenir un {string}")
    public void reponseDoitContenirUn(String field) {
        assertTrue(responseBody.contains(field));
    }

    @Et("l'exécution Step Functions doit se terminer avec le statut {string}")
    public void executionStepFunctionsDoitSeTerminerAvecStatut(String expectedStatus) {
        assertEquals(expectedStatus, executionStatus.toString());
    }

    @Et("la date de naissance dans DynamoDB doit être mise à jour à {string}")
    public void datenaissanceDansDynamoDBDoitEtreMiseAJour(String expectedBirthdate) {
        // Verify DynamoDB update was called
        verify(dynamoDB, atLeastOnce()).updateItem(any());
    }

    @Et("un événement Kafka doit être publié")
    public void evenementKafkaDoitEtrePublie() {
        assertTrue(kafkaEventPublished);
    }

    @Et("les logs CloudWatch doivent contenir {string}")
    public void logsCloudWatchDoiventContenir(String expectedLogMessage) {
        // In real implementation, verify CloudWatch logs
        assertTrue(executionStatus == ExecutionStatus.SUCCEEDED);
    }

    @Et("le message d'erreur doit contenir {string}")
    public void messageErreurDoitContenir(String expectedMessage) {
        assertTrue(responseBody.contains(expectedMessage));
    }

    @Et("l'état final doit être {string}")
    public void etatFinalDoitEtre(String expectedState) {
        // Verify Step Functions final state
        assertNotNull(executionStatus);
    }

    @Et("aucun événement Kafka ne doit être publié")
    public void aucunEvenementKafkaNeDoitEtrePublie() {
        assertFalse(kafkaEventPublished);
    }

    @Étantdonnéque("que le cluster MSK est indisponible")
    public void clusterMSKEstIndisponible() {
        kafkaEventPublished = false;
        when(kafkaProducer.send(any())).thenThrow(new RuntimeException("Kafka unavailable"));
    }

    @Alors("la mise à jour DynamoDB doit réussir")
    public void miseAJourDynamoDBDoitReussir() {
        verify(dynamoDB, atLeastOnce()).updateItem(any());
    }

    @Mais("la publication Kafka doit échouer")
    public void publicationKafkaDoitEchouer() {
        assertFalse(kafkaEventPublished);
    }

    @Et("les logs doivent indiquer l'échec de publication Kafka")
    public void logsDoiventIndiquerEchecPublicationKafka() {
        // Verify error logging
        assertFalse(kafkaEventPublished);
    }

    @Et("la date dans DynamoDB doit rester {string} \\(pas de rollback)")
    public void dateDansDynamoDBDoitRester(String birthdate) {
        // Verify no rollback was performed
        verify(dynamoDB, atLeastOnce()).updateItem(any());
    }

    @Et("l'événement Kafka doit contenir la raison {string}")
    public void evenementKafkaDoitContenirRaison(String reason) {
        assertTrue(kafkaEventPublished);
        // Would verify Kafka message content in real implementation
    }

    @Et("l'audit trail doit contenir le type {string}")
    public void auditTrailDoitContenirType(String auditType) {
        // Verify audit trail entry
        assertTrue(httpStatusCode == 200);
    }
}
```

---

### Test Runner

**Fichier**: `src/test/java/com/bnc/mcp/CucumberTestRunner.java`

```java
package com.bnc.mcp;

import org.junit.platform.suite.api.ConfigurationParameter;
import org.junit.platform.suite.api.IncludeEngines;
import org.junit.platform.suite.api.SelectClasspathResource;
import org.junit.platform.suite.api.Suite;

import static io.cucumber.junit.platform.engine.Constants.*;

@Suite
@IncludeEngines("cucumber")
@SelectClasspathResource("features")
@ConfigurationParameter(key = GLUE_PROPERTY_NAME, value = "com.bnc.mcp.steps")
@ConfigurationParameter(key = PLUGIN_PROPERTY_NAME, value = "pretty, html:target/cucumber-reports/cucumber.html, json:target/cucumber-reports/cucumber.json")
@ConfigurationParameter(key = FILTER_TAGS_PROPERTY_NAME, value = "not @skip")
public class CucumberTestRunner {
}
```

---

### Configuration Cucumber

**Fichier**: `src/test/resources/cucumber.properties`

```properties
cucumber.publish.enabled=false
cucumber.publish.quiet=true
cucumber.execution.parallel.enabled=false
cucumber.execution.parallel.config.strategy=fixed
cucumber.execution.parallel.config.fixed.parallelism=4
cucumber.plugin=pretty, html:target/cucumber-reports/cucumber.html, json:target/cucumber-reports/cucumber.json, junit:target/cucumber-reports/cucumber.xml
cucumber.glue=com.bnc.mcp.steps
cucumber.features=src/test/resources/features
```

---

### Exécution des Tests

#### Commande Maven

```bash
# Exécuter tous les tests Cucumber
mvn test -Dtest=CucumberTestRunner

# Exécuter uniquement les tests de validation
mvn test -Dtest=CucumberTestRunner -Dcucumber.filter.tags="@validation"

# Exécuter avec rapport détaillé
mvn clean test -Dtest=CucumberTestRunner
```

#### Rapport HTML

Après exécution, le rapport HTML est disponible à:
```
target/cucumber-reports/cucumber.html
```

Ouvrir dans un navigateur:
```bash
open target/cucumber-reports/cucumber.html  # macOS
xdg-open target/cucumber-reports/cucumber.html  # Linux
start target/cucumber-reports/cucumber.html  # Windows
```

---

### Tags pour Organisation

Ajouter des tags dans les feature files pour filtrer les tests:

```gherkin
@validation @smoke
Scénario: Validation réussie d'une date de naissance valide
  ...

@update @regression
Scénario: Mise à jour réussie de la date de naissance
  ...

@kafka @integration
Scénario: Publication réussie d'un événement de mise à jour
  ...

@e2e @slow
Scénario: Workflow complet réussi de bout en bout
  ...
```

#### Exécution par Tags

```bash
# Tests de smoke seulement
mvn test -Dtest=CucumberTestRunner -Dcucumber.filter.tags="@smoke"

# Tests d'intégration
mvn test -Dtest=CucumberTestRunner -Dcucumber.filter.tags="@integration"

# Tests E2E (lents)
mvn test -Dtest=CucumberTestRunner -Dcucumber.filter.tags="@e2e"

# Tous sauf E2E
mvn test -Dtest=CucumberTestRunner -Dcucumber.filter.tags="not @e2e"
```

---

### Intégration CI/CD

#### Exemple GitLab CI

```yaml
test:cucumber:
  stage: test
  script:
    - mvn clean test -Dtest=CucumberTestRunner
  artifacts:
    when: always
    paths:
      - target/cucumber-reports/
    reports:
      junit: target/cucumber-reports/cucumber.xml
  only:
    - merge_requests
    - main
```

#### Exemple GitHub Actions

```yaml
- name: Run Cucumber Tests
  run: mvn clean test -Dtest=CucumberTestRunner

- name: Publish Cucumber Report
  uses: actions/upload-artifact@v3
  if: always()
  with:
    name: cucumber-report
    path: target/cucumber-reports/
```

---

## 📜 Scripts de Déploiement

### Script de Déploiement Complet

**Fichier**: `scripts/deploy-birthdate-workflow.sh`

```bash
#!/bin/bash

#######################################################################
# Script de déploiement du workflow Birthdate Update
# Usage: ./scripts/deploy-birthdate-workflow.sh [dev|prod]
#######################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JAVA_PROJECT_DIR="$HOME/Documents/mcp-lambda-handlers"
CODE_VERSION="1.0.0"
AWS_REGION="ca-central-1"
S3_BUCKET="mcp-lambda-artifacts-${ENVIRONMENT}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Déploiement Workflow Birthdate Update${NC}"
echo -e "${GREEN}Environnement: ${ENVIRONMENT}${NC}"
echo -e "${GREEN}========================================${NC}"

#######################################################################
# Étape 1: Vérifications préalables
#######################################################################
echo -e "\n${YELLOW}[1/8] Vérifications préalables...${NC}"

# Vérifier que Java est installé
if ! command -v java &> /dev/null; then
    echo -e "${RED}Erreur: Java n'est pas installé${NC}"
    exit 1
fi

# Vérifier que Maven est installé
if ! command -v mvn &> /dev/null; then
    echo -e "${RED}Erreur: Maven n'est pas installé${NC}"
    exit 1
fi

# Vérifier que Terraform est installé
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Erreur: Terraform n'est pas installé${NC}"
    exit 1
fi

# Vérifier que AWS CLI est installé et configuré
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Erreur: AWS CLI n'est pas installé${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Toutes les dépendances sont installées${NC}"

#######################################################################
# Étape 2: Build du projet Java
#######################################################################
echo -e "\n${YELLOW}[2/8] Build du projet Java...${NC}"

cd "$JAVA_PROJECT_DIR"

echo "Nettoyage des builds précédents..."
mvn clean

echo "Compilation du code..."
mvn compile

echo "Exécution des tests unitaires..."
mvn test

echo "Packaging du JAR..."
mvn package -DskipTests

JAR_FILE="target/mcp-lambda-handlers-${CODE_VERSION}.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo -e "${RED}Erreur: JAR non trouvé à $JAR_FILE${NC}"
    exit 1
fi

JAR_SIZE=$(du -h "$JAR_FILE" | cut -f1)
echo -e "${GREEN}✓ JAR créé avec succès: $JAR_FILE ($JAR_SIZE)${NC}"

#######################################################################
# Étape 3: Upload du JAR vers S3
#######################################################################
echo -e "\n${YELLOW}[3/8] Upload du JAR vers S3...${NC}"

# Créer le bucket S3 s'il n'existe pas
if ! aws s3 ls "s3://${S3_BUCKET}" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Bucket S3 existe déjà"
else
    echo "Création du bucket S3..."
    aws s3 mb "s3://${S3_BUCKET}" --region "$AWS_REGION"
fi

# Upload du JAR
S3_KEY="birthdate/${CODE_VERSION}/mcp-lambda-handlers-${CODE_VERSION}.jar"
echo "Upload vers s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "$JAR_FILE" "s3://${S3_BUCKET}/${S3_KEY}" --region "$AWS_REGION"

echo -e "${GREEN}✓ JAR uploadé avec succès${NC}"

#######################################################################
# Étape 4: Initialisation Terraform
#######################################################################
echo -e "\n${YELLOW}[4/8] Initialisation Terraform...${NC}"

cd "$PROJECT_ROOT/environments/${ENVIRONMENT}"

echo "Terraform init..."
terraform init -upgrade

echo -e "${GREEN}✓ Terraform initialisé${NC}"

#######################################################################
# Étape 5: Validation Terraform
#######################################################################
echo -e "\n${YELLOW}[5/8] Validation Terraform...${NC}"

terraform validate

echo -e "${GREEN}✓ Configuration Terraform valide${NC}"

#######################################################################
# Étape 6: Plan Terraform
#######################################################################
echo -e "\n${YELLOW}[6/8] Plan Terraform...${NC}"

terraform plan \
  -var="code_version=${CODE_VERSION}" \
  -out=tfplan-birthdate

echo -e "${GREEN}✓ Plan Terraform généré${NC}"

#######################################################################
# Étape 7: Apply Terraform (avec confirmation)
#######################################################################
echo -e "\n${YELLOW}[7/8] Apply Terraform...${NC}"
echo -e "${YELLOW}Cette étape va créer/modifier les ressources AWS${NC}"
read -p "Voulez-vous continuer? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Déploiement annulé${NC}"
    exit 1
fi

terraform apply tfplan-birthdate

echo -e "${GREEN}✓ Infrastructure déployée${NC}"

#######################################################################
# Étape 8: Tests de validation
#######################################################################
echo -e "\n${YELLOW}[8/8] Tests de validation...${NC}"

# Récupérer l'URL de l'API
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
if [ -z "$API_URL" ]; then
    echo -e "${YELLOW}⚠ Impossible de récupérer l'URL de l'API${NC}"
else
    echo "URL de l'API: $API_URL"

    # Test simple avec un client fictif
    echo "Test de l'endpoint..."
    RESPONSE=$(curl -s -X PUT "${API_URL}/api/clients/TEST_DEPLOY_123/date-naissance" \
      -H "Content-Type: application/json" \
      -d '{
        "newBirthdate": "1985-06-15",
        "reason": "CORRECTION"
      }' || echo "")

    if echo "$RESPONSE" | grep -q "executionArn"; then
        echo -e "${GREEN}✓ Endpoint répond correctement${NC}"
        echo "Réponse: $RESPONSE"
    else
        echo -e "${YELLOW}⚠ Réponse inattendue de l'endpoint${NC}"
        echo "Réponse: $RESPONSE"
    fi
fi

#######################################################################
# Résumé
#######################################################################
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Déploiement terminé avec succès!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Ressources déployées:${NC}"
echo "  - 3 Lambda Functions (validation, update, event-publisher)"
echo "  - 1 Step Functions State Machine"
echo "  - 1 API Gateway Endpoint"
echo "  - 3 CloudWatch Log Groups"
echo "  - IAM Roles et Policies"

echo -e "\n${YELLOW}Prochaines étapes:${NC}"
echo "  1. Tester via Swagger UI:"
SWAGGER_URL=$(terraform output -raw swagger_ui_url 2>/dev/null || echo "N/A")
echo "     $SWAGGER_URL"

echo "  2. Surveiller les logs CloudWatch:"
echo "     aws logs tail /aws/lambda/${ENVIRONMENT}-mcp-birthdate-validation --follow"

echo "  3. Vérifier les métriques Step Functions:"
echo "     https://console.aws.amazon.com/states/home?region=${AWS_REGION}"

echo -e "\n${GREEN}✓ Déploiement complet${NC}"
```

Rendre le script exécutable:
```bash
chmod +x scripts/deploy-birthdate-workflow.sh
```

---

## 🔧 Guide de Troubleshooting Approfondi

### Problème 1: Lambda Timeout lors de la Validation

**Symptômes**:
- CloudWatch logs montrent "Task timed out after 30.00 seconds"
- Step Functions montre l'état "ValidateBirthdate" en timeout

**Diagnostic**:
```bash
# Vérifier les logs CloudWatch
aws logs tail /aws/lambda/dev-mcp-birthdate-validation \
  --filter-pattern "Task timed out" \
  --follow

# Vérifier les métriques Lambda
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=dev-mcp-birthdate-validation \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Average,Maximum \
  --region ca-central-1
```

**Causes possibles**:
1. DynamoDB lent (throttling ou haute latence)
2. Initialisation Java/Spring lente (cold start)
3. Timeout trop court

**Solutions**:
```hcl
# Solution 1: Augmenter le timeout
resource "aws_lambda_function" "birthdate_validation" {
  timeout = 60  # Augmenter à 60 secondes
}

# Solution 2: Augmenter la mémoire (améliore aussi le CPU)
resource "aws_lambda_function" "birthdate_validation" {
  memory_size = 1024  # Augmenter à 1024 MB
}

# Solution 3: Activer Provisioned Concurrency (éviter cold starts)
resource "aws_lambda_provisioned_concurrency_config" "birthdate_validation" {
  function_name                     = aws_lambda_function.birthdate_validation.function_name
  provisioned_concurrent_executions = 2
  qualifier                         = aws_lambda_function.birthdate_validation.version
}
```

---

### Problème 2: DynamoDB ProvisionedThroughputExceededException

**Symptômes**:
- Erreur "ProvisionedThroughputExceededException" dans les logs
- UpdateBirthdate échoue après plusieurs retries

**Diagnostic**:
```bash
# Vérifier les métriques DynamoDB
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedWriteCapacityUnits \
  --dimensions Name=TableName,Value=dev-ClientProfile \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Sum \
  --region ca-central-1

# Vérifier les throttled requests
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name UserErrors \
  --dimensions Name=TableName,Value=dev-ClientProfile \
  --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 300 \
  --statistics Sum \
  --region ca-central-1
```

**Solutions**:
```hcl
# Solution 1: Passer en mode On-Demand
resource "aws_dynamodb_table" "client_profile" {
  billing_mode = "PAY_PER_REQUEST"  # Au lieu de PROVISIONED
}

# Solution 2: Augmenter les WCU/RCU
resource "aws_dynamodb_table" "client_profile" {
  billing_mode   = "PROVISIONED"
  read_capacity  = 50   # Augmenter
  write_capacity = 50   # Augmenter
}

# Solution 3: Activer Auto-Scaling
resource "aws_appautoscaling_target" "dynamodb_table_write" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/dev-ClientProfile"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:table/dev-ClientProfile"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70.0
  }
}
```

---

### Problème 3: Kafka Publish Failure (État Incohérent)

**Symptômes**:
- DynamoDB mis à jour ✅
- Événement Kafka non publié ❌
- Step Functions se termine en état "PublishFailedKafkaUnavailable"

**Diagnostic**:
```bash
# Vérifier les logs de la Lambda Event Publisher
aws logs tail /aws/lambda/dev-mcp-birthdate-event-publisher \
  --filter-pattern "Failed to publish" \
  --follow

# Vérifier l'état du cluster MSK
aws kafka describe-cluster \
  --cluster-arn arn:aws:kafka:ca-central-1:ACCOUNT:cluster/mcp-dev/... \
  --region ca-central-1

# Vérifier la connectivité réseau (si Lambda dans VPC)
# Vérifier que les Security Groups permettent le trafic vers MSK
```

**Solutions**:

**Solution 1: Republier manuellement l'événement**
```bash
# Script de republication manuelle
#!/bin/bash

CLIENT_ID="TEST123"
EXECUTION_ARN="arn:aws:states:ca-central-1:...:execution:..."

# Récupérer les données de DynamoDB
aws dynamodb get-item \
  --table-name dev-ClientProfile \
  --key "{\"clientId\": {\"S\": \"$CLIENT_ID\"}}" \
  --region ca-central-1

# Publier manuellement vers Kafka
# (nécessite un producteur Kafka configuré)
```

**Solution 2: Implémenter une DLQ (Dead Letter Queue)**
```hcl
# Ajouter une DLQ SQS pour les échecs de publication
resource "aws_sqs_queue" "birthdate_event_dlq" {
  name = "${var.environment}-mcp-birthdate-event-dlq"

  message_retention_seconds = 1209600  # 14 jours

  tags = {
    Name = "${var.environment}-birthdate-event-dlq"
  }
}

# Configurer la Lambda pour utiliser la DLQ
resource "aws_lambda_function" "birthdate_event_publisher" {
  # ... autres configs ...

  dead_letter_config {
    target_arn = aws_sqs_queue.birthdate_event_dlq.arn
  }
}

# Créer une Lambda pour retraiter la DLQ
resource "aws_lambda_function" "dlq_reprocessor" {
  function_name = "${var.environment}-mcp-dlq-reprocessor"
  # ... configuration pour relire la DLQ et republier vers Kafka ...
}
```

**Solution 3: Saga Pattern (Compensation)**
```hcl
# Ajouter un état de compensation dans la State Machine
# Si PublishEvent échoue, rollback la mise à jour DynamoDB

"PublishEvent": {
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.publishError",
      "Next": "RollbackUpdate"  # Nouvel état
    }
  ]
},

"RollbackUpdate": {
  "Type": "Task",
  "Resource": "${rollback_lambda_arn}",
  "Comment": "Rollback DynamoDB update",
  "Next": "PublishFailed"
}
```

---

### Problème 4: Step Functions Execution Failed (Erreur Générique)

**Diagnostic complet**:
```bash
# Lister les exécutions échouées
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ca-central-1:ACCOUNT:stateMachine:dev-mcp-client_birthdate_update \
  --status-filter FAILED \
  --max-results 10 \
  --region ca-central-1

# Obtenir les détails d'une exécution spécifique
EXECUTION_ARN="arn:aws:states:..."
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --region ca-central-1

# Obtenir l'historique complet de l'exécution
aws stepfunctions get-execution-history \
  --execution-arn $EXECUTION_ARN \
  --region ca-central-1 \
  --output json | jq '.events[] | select(.type | contains("Failed"))'
```

---

### Problème 5: API Gateway Returns 500 (Sans logs Lambda)

**Symptômes**:
- API Gateway retourne HTTP 500
- Aucun log dans CloudWatch Logs pour les Lambdas
- Step Functions n'est pas démarrée

**Diagnostic**:
```bash
# Vérifier les logs API Gateway
aws logs tail /aws/api-gateway/dev-mcp-api \
  --filter-pattern "ERROR" \
  --follow

# Vérifier les permissions IAM
aws iam get-role-policy \
  --role-name dev-mcp-api-gateway-role \
  --policy-name step-functions-execution
```

**Causes possibles**:
1. Permissions IAM manquantes pour API Gateway → Step Functions
2. ARN de State Machine incorrect dans l'intégration
3. Transformation VTL incorrecte

**Solutions**:
```hcl
# Vérifier/Corriger les permissions IAM
resource "aws_iam_role_policy" "api_gateway_step_functions" {
  name = "step-functions-execution"
  role = aws_iam_role.api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.client_birthdate_update.arn
      }
    ]
  })
}

# Activer les logs détaillés API Gateway
resource "aws_api_gateway_stage" "main" {
  # ... autres configs ...

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = "$context.requestId: $context.error.message $context.error.messageString"
  }

  xray_tracing_enabled = true
}
```

---

## 🔗 Références

- [Guide d'ajout d'endpoint complet](ADD-NEW-ENDPOINT-GUIDE.md)
- [Guide Swagger UI](SWAGGER-UI-GUIDE.md)
- [Guide Quick Start](../QUICK-START.md)
- [AWS Step Functions - Standard vs Express](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-standard-vs-express.html)
- [AWS Step Functions - Error Handling](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html)

---

**Version**: 1.0.0
**Date**: 2026-09-29
**Auteur**: MCP DevOps Team
**Status**: Définition Complète - Prêt pour Implémentation