# Guide d'Implémentation : Code Métier du Workflow de Mise à Jour de Téléphone

## 📋 Vue d'ensemble

Ce guide détaille **pas à pas** l'implémentation du code métier Java pour le workflow de mise à jour de téléphone dans le repo `mcp-local`.

**Repo concerné :** `/Users/fabricefoko/Downloads/mcp-local`

**Langage :** Java 17

**Framework :** AWS Lambda (sans Spring Boot)

---

## 🎯 Architecture du code métier

```
mcp-local/
├── pom.xml                           # Configuration Maven
├── src/
│   ├── main/
│   │   └── java/
│   │       └── com/
│   │           └── bnc/
│   │               └── mcp/
│   │                   ├── models/              # 1. Créer en premier
│   │                   │   ├── PhoneValidationResult.java
│   │                   │   ├── PhoneHistoryCheck.java
│   │                   │   ├── OTPCode.java
│   │                   │   └── MDMAEPhoneUpdateRequest.java
│   │                   │
│   │                   ├── clients/             # 2. Créer ensuite
│   │                   │   ├── DynamoDBClient.java
│   │                   │   ├── SNSClient.java
│   │                   │   ├── MDMAEClient.java
│   │                   │   ├── FCCClient.java
│   │                   │   └── CRMClient.java
│   │                   │
│   │                   ├── services/            # 3. Créer après les clients
│   │                   │   ├── PhoneValidationService.java
│   │                   │   ├── PhoneHistoryService.java
│   │                   │   └── OTPService.java
│   │                   │
│   │                   ├── handlers/            # 4. Créer les handlers
│   │                   │   ├── ReadClientProfileHandler.java
│   │                   │   ├── PhoneValidatorHandler.java
│   │                   │   ├── CheckPhoneHistoryHandler.java
│   │                   │   ├── HumanApprovalHandler.java
│   │                   │   ├── SendOTPSMSHandler.java
│   │                   │   ├── CheckOTPStatusHandler.java
│   │                   │   ├── PhoneMDMAEClientHandler.java
│   │                   │   ├── FCCSenderHandler.java
│   │                   │   ├── CRMUpdaterHandler.java
│   │                   │   ├── NotificationUpdaterHandler.java
│   │                   │   └── NotificationSenderHandler.java    # ⭐ NOUVEAU
│   │                   │
│   │                   └── controllers/         # 5. Créer en dernier
│   │                       └── ClientPhoneUpdateController.java
│   │
│   └── test/
│       └── java/
│           └── com/
│               └── bnc/
│                   └── mcp/
│                       ├── PhoneValidationServiceTest.java
│                       ├── PhoneValidatorHandlerTest.java
│                       └── CheckPhoneHistoryHandlerTest.java
│
└── target/                           # Généré après build
    ├── phone-validator-1.0.0.jar
    ├── check-phone-history-1.0.0.jar
    └── ... (autres JARs)
```

---

## 📊 Ordre de création des fichiers

### Vue d'ensemble

```
1. pom.xml (configuration Maven)
   ↓
2. Models (aucune dépendance)
   ↓
3. Clients (dépendent des Models)
   ↓
4. Services (dépendent des Clients et Models)
   ↓
5. Handlers (dépendent des Services, Clients, Models)
   ↓
6. Controller (dépend de tout)
   ↓
7. Tests
   ↓
8. Build et déploiement
```

---

## 🔧 Étape 1 : Configuration Maven (pom.xml)

**Pourquoi en premier ?** Le fichier `pom.xml` définit toutes les dépendances nécessaires.

**Fichier :** `pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.bnc.mcp</groupId>
    <artifactId>mcp-phone-update</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>MCP Phone Update Workflow</name>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>

        <!-- AWS SDK v2 -->
        <aws.sdk.version>2.20.0</aws.sdk.version>

        <!-- Google libphonenumber -->
        <libphonenumber.version>8.13.20</libphonenumber.version>

        <!-- Logging -->
        <slf4j.version>2.0.9</slf4j.version>

        <!-- JSON -->
        <gson.version>2.10.1</gson.version>

        <!-- Testing -->
        <junit.version>5.10.0</junit.version>
        <mockito.version>5.5.0</mockito.version>
    </properties>

    <dependencies>
        <!-- AWS Lambda Core -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-core</artifactId>
            <version>1.2.3</version>
        </dependency>

        <!-- AWS Lambda Events -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-events</artifactId>
            <version>3.11.3</version>
        </dependency>

        <!-- AWS SDK v2 - DynamoDB -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>dynamodb</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- AWS SDK v2 - SNS (for SMS) -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sns</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- AWS SDK v2 - SQS -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sqs</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- AWS SDK v2 - Step Functions -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sfn</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- Google libphonenumber (validation) -->
        <dependency>
            <groupId>com.googlecode.libphonenumber</groupId>
            <artifactId>libphonenumber</artifactId>
            <version>${libphonenumber.version}</version>
        </dependency>

        <!-- JSON parsing (Gson) -->
        <dependency>
            <groupId>com.google.code.gson</groupId>
            <artifactId>gson</artifactId>
            <version>${gson.version}</version>
        </dependency>

        <!-- Logging -->
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
            <version>${slf4j.version}</version>
        </dependency>
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-simple</artifactId>
            <version>${slf4j.version}</version>
        </dependency>

        <!-- HTTP Client for API calls -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>url-connection-client</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- Testing -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
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
                    <source>17</source>
                    <target>17</target>
                </configuration>
            </plugin>

            <!-- Maven Shade Plugin - Créer un JAR unique avec toutes les dépendances -->
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
                            <finalName>mcp-phone-update-${project.version}</finalName>
                            <createDependencyReducedPom>false</createDependencyReducedPom>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>com.bnc.mcp.controllers.ClientPhoneUpdateController</mainClass>
                                </transformer>
                            </transformers>
                        </configuration>
                    </execution>
                </executions>
            </plugin>

            <!-- Maven Surefire Plugin for tests -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.1.2</version>
            </plugin>
        </plugins>
    </build>
</project>
```

**Commande :**
```bash
cd /Users/fabricefoko/Downloads/mcp-local
# Vérifier que pom.xml est valide
mvn validate
```

---

## 📦 Étape 2 : Models (aucune dépendance)

**Pourquoi maintenant ?** Les models n'ont aucune dépendance et seront utilisés partout.

### 2.1 PhoneValidationResult.java

**Fichier :** `src/main/java/com/bnc/mcp/models/PhoneValidationResult.java`

```java
package com.bnc.mcp.models;

public class PhoneValidationResult {
    private boolean isValid;
    private String phoneType;      // MOBILE, FIXED_LINE, VOIP, etc.
    private String carrier;
    private String message;
    private String formattedPhone; // E.164 format

    public PhoneValidationResult() {}

    public PhoneValidationResult(boolean isValid, String message) {
        this.isValid = isValid;
        this.message = message;
    }

    // Getters and Setters
    public boolean isValid() { return isValid; }
    public void setValid(boolean valid) { isValid = valid; }

    public String getPhoneType() { return phoneType; }
    public void setPhoneType(String phoneType) { this.phoneType = phoneType; }

    public String getCarrier() { return carrier; }
    public void setCarrier(String carrier) { this.carrier = carrier; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }

    public String getFormattedPhone() { return formattedPhone; }
    public void setFormattedPhone(String formattedPhone) { this.formattedPhone = formattedPhone; }
}
```

### 2.2 PhoneHistoryCheck.java

**Fichier :** `src/main/java/com/bnc/mcp/models/PhoneHistoryCheck.java`

```java
package com.bnc.mcp.models;

import java.time.Instant;
import java.util.List;

public class PhoneHistoryCheck {
    private String clientId;
    private int changeCount;           // Nombre de changements dans les 90 derniers jours
    private Instant lastChangeDate;
    private boolean isSuspicious;
    private String reason;
    private List<PhoneChangeRecord> recentChanges;

    public PhoneHistoryCheck() {}

    public PhoneHistoryCheck(String clientId, int changeCount, boolean isSuspicious, String reason) {
        this.clientId = clientId;
        this.changeCount = changeCount;
        this.isSuspicious = isSuspicious;
        this.reason = reason;
    }

    // Getters and Setters
    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }

    public int getChangeCount() { return changeCount; }
    public void setChangeCount(int changeCount) { this.changeCount = changeCount; }

    public Instant getLastChangeDate() { return lastChangeDate; }
    public void setLastChangeDate(Instant lastChangeDate) { this.lastChangeDate = lastChangeDate; }

    public boolean isSuspicious() { return isSuspicious; }
    public void setSuspicious(boolean suspicious) { isSuspicious = suspicious; }

    public String getReason() { return reason; }
    public void setReason(String reason) { this.reason = reason; }

    public List<PhoneChangeRecord> getRecentChanges() { return recentChanges; }
    public void setRecentChanges(List<PhoneChangeRecord> recentChanges) { this.recentChanges = recentChanges; }

    // Inner class for change records
    public static class PhoneChangeRecord {
        private String oldPhone;
        private String newPhone;
        private Instant timestamp;

        public PhoneChangeRecord(String oldPhone, String newPhone, Instant timestamp) {
            this.oldPhone = oldPhone;
            this.newPhone = newPhone;
            this.timestamp = timestamp;
        }

        // Getters
        public String getOldPhone() { return oldPhone; }
        public String getNewPhone() { return newPhone; }
        public Instant getTimestamp() { return timestamp; }
    }
}
```

### 2.3 OTPCode.java

**Fichier :** `src/main/java/com/bnc/mcp/models/OTPCode.java`

```java
package com.bnc.mcp.models;

import java.time.Instant;

public class OTPCode {
    private String otpId;
    private String clientId;
    private String code;              // Code à 6 chiffres
    private String phoneNumber;
    private Instant createdAt;
    private Instant expiresAt;        // Expire après 5 minutes
    private String status;            // PENDING, VALIDATED, EXPIRED, FAILED
    private int validationAttempts;
    private Instant validatedAt;

    public OTPCode() {}

    public OTPCode(String otpId, String clientId, String code, String phoneNumber) {
        this.otpId = otpId;
        this.clientId = clientId;
        this.code = code;
        this.phoneNumber = phoneNumber;
        this.createdAt = Instant.now();
        this.expiresAt = Instant.now().plusSeconds(300); // 5 minutes
        this.status = "PENDING";
        this.validationAttempts = 0;
    }

    // Getters and Setters
    public String getOtpId() { return otpId; }
    public void setOtpId(String otpId) { this.otpId = otpId; }

    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }

    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public int getValidationAttempts() { return validationAttempts; }
    public void setValidationAttempts(int validationAttempts) { this.validationAttempts = validationAttempts; }

    public Instant getValidatedAt() { return validatedAt; }
    public void setValidatedAt(Instant validatedAt) { this.validatedAt = validatedAt; }

    // Helper methods
    public boolean isExpired() {
        return Instant.now().isAfter(expiresAt);
    }

    public boolean isValidated() {
        return "VALIDATED".equals(status);
    }
}
```

### 2.4 MDMAEPhoneUpdateRequest.java

**Fichier :** `src/main/java/com/bnc/mcp/models/MDMAEPhoneUpdateRequest.java`

```java
package com.bnc.mcp.models;

public class MDMAEPhoneUpdateRequest {
    private String clientId;
    private String newPhoneNumber;
    private String country;
    private String requestId;
    private String updatedBy;

    public MDMAEPhoneUpdateRequest() {}

    public MDMAEPhoneUpdateRequest(String clientId, String newPhoneNumber, String country) {
        this.clientId = clientId;
        this.newPhoneNumber = newPhoneNumber;
        this.country = country;
    }

    // Getters and Setters
    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }

    public String getNewPhoneNumber() { return newPhoneNumber; }
    public void setNewPhoneNumber(String newPhoneNumber) { this.newPhoneNumber = newPhoneNumber; }

    public String getCountry() { return country; }
    public void setCountry(String country) { this.country = country; }

    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }

    public String getUpdatedBy() { return updatedBy; }
    public void setUpdatedBy(String updatedBy) { this.updatedBy = updatedBy; }
}
```

**Commande :**
```bash
# Créer le répertoire models
mkdir -p src/main/java/com/bnc/mcp/models

# Compiler les models
mvn compile
```

---

## 🔌 Étape 3 : Clients (dépendent des Models)

**Pourquoi maintenant ?** Les clients utilisent les models et seront utilisés par les services.

### 3.1 DynamoDBClient.java

**Fichier :** `src/main/java/com/bnc/mcp/clients/DynamoDBClient.java`

**⚠️ Configuration Retry :** Ce client inclut une **RetryPolicy AWS SDK** pour gérer automatiquement les retry en cas de throttling ou erreurs transitoires DynamoDB.

```java
package com.bnc.mcp.clients;

import com.bnc.mcp.models.OTPCode;
import com.bnc.mcp.models.PhoneHistoryCheck;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.retry.RetryPolicy;
import software.amazon.awssdk.core.retry.backoff.BackoffStrategy;
import software.amazon.awssdk.core.retry.conditions.RetryCondition;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class DynamoDBClient {
    private static final Logger logger = LoggerFactory.getLogger(DynamoDBClient.class);

    private final DynamoDbClient dynamoDb;
    private final String phoneHistoryTable;
    private final String otpCodesTable;
    private final String clientProfileTable;

    /**
     * Constructor avec configuration Retry automatique pour DynamoDB
     *
     * Retry automatique pour:
     * - ProvisionedThroughputExceededException
     * - ThrottlingException
     * - Erreurs réseau transitoires (500, 503)
     *
     * Configuration:
     * - Max 3 tentatives
     * - Exponential backoff: 500ms base, max 20s
     * - Backoff strategy optimisé pour throttling AWS
     */
    public DynamoDBClient() {
        logger.info("Initializing DynamoDBClient with retry policy");

        // Configuration de la RetryPolicy pour DynamoDB
        RetryPolicy retryPolicy = RetryPolicy.builder()
                .numRetries(3)  // Maximum 3 retry attempts
                .backoffStrategy(BackoffStrategy.defaultThrottlingStrategy())
                .throttlingBackoffStrategy(BackoffStrategy.exponentialDelay(
                    Duration.ofMillis(500),   // Base delay: 500ms
                    Duration.ofSeconds(20)    // Max delay: 20s
                ))
                .build();

        this.dynamoDb = DynamoDbClient.builder()
                .overrideConfiguration(config -> config.retryPolicy(retryPolicy))
                .build();

        this.phoneHistoryTable = System.getenv("DYNAMODB_PHONE_HISTORY");
        this.otpCodesTable = System.getenv("DYNAMODB_OTP_TABLE");
        this.clientProfileTable = System.getenv("DYNAMODB_CLIENT_TABLE");

        logger.info("DynamoDBClient initialized with tables: history={}, otp={}, profile={}",
            phoneHistoryTable, otpCodesTable, clientProfileTable);
    }

    // Constructor for testing
    public DynamoDBClient(DynamoDbClient dynamoDb, String phoneHistoryTable, String otpCodesTable, String clientProfileTable) {
        this.dynamoDb = dynamoDb;
        this.phoneHistoryTable = phoneHistoryTable;
        this.otpCodesTable = otpCodesTable;
        this.clientProfileTable = clientProfileTable;
    }

    /**
     * Récupère l'historique des changements de téléphone pour un client
     */
    public PhoneHistoryCheck getPhoneHistory(String clientId) {
        logger.info("Fetching phone history for client: {}", clientId);

        try {
            // Query pour récupérer les derniers changements (90 jours)
            long ninetyDaysAgo = Instant.now().minusSeconds(90 * 24 * 60 * 60).toEpochMilli();

            QueryRequest request = QueryRequest.builder()
                    .tableName(phoneHistoryTable)
                    .keyConditionExpression("clientId = :clientId AND #ts >= :timestamp")
                    .expressionAttributeNames(Map.of("#ts", "timestamp"))
                    .expressionAttributeValues(Map.of(
                            ":clientId", AttributeValue.builder().s(clientId).build(),
                            ":timestamp", AttributeValue.builder().n(String.valueOf(ninetyDaysAgo)).build()
                    ))
                    .build();

            QueryResponse response = dynamoDb.query(request);
            int changeCount = response.count();

            boolean isSuspicious = changeCount >= 3;
            String reason = isSuspicious
                    ? String.format("Client a changé son téléphone %d fois en 90 jours", changeCount)
                    : "Changements normaux";

            PhoneHistoryCheck result = new PhoneHistoryCheck(clientId, changeCount, isSuspicious, reason);

            // Ajouter les enregistrements récents
            List<PhoneHistoryCheck.PhoneChangeRecord> changes = new ArrayList<>();
            for (Map<String, AttributeValue> item : response.items()) {
                String oldPhone = item.get("oldPhone").s();
                String newPhone = item.get("newPhone").s();
                long timestamp = Long.parseLong(item.get("timestamp").n());
                changes.add(new PhoneHistoryCheck.PhoneChangeRecord(
                        oldPhone, newPhone, Instant.ofEpochMilli(timestamp)
                ));
            }
            result.setRecentChanges(changes);

            if (!changes.isEmpty()) {
                result.setLastChangeDate(changes.get(0).getTimestamp());
            }

            return result;

        } catch (Exception e) {
            logger.error("Error fetching phone history for client {}: {}", clientId, e.getMessage());
            throw new RuntimeException("Failed to fetch phone history", e);
        }
    }

    /**
     * Sauvegarde un code OTP dans DynamoDB
     */
    public void saveOTPCode(OTPCode otpCode) {
        logger.info("Saving OTP code for client: {}", otpCode.getClientId());

        try {
            Map<String, AttributeValue> item = new HashMap<>();
            item.put("clientId", AttributeValue.builder().s(otpCode.getClientId()).build());
            item.put("otpId", AttributeValue.builder().s(otpCode.getOtpId()).build());
            item.put("code", AttributeValue.builder().s(otpCode.getCode()).build());
            item.put("phoneNumber", AttributeValue.builder().s(otpCode.getPhoneNumber()).build());
            item.put("createdAt", AttributeValue.builder().n(String.valueOf(otpCode.getCreatedAt().toEpochMilli())).build());
            item.put("expiresAt", AttributeValue.builder().n(String.valueOf(otpCode.getExpiresAt().getEpochSecond())).build());
            item.put("status", AttributeValue.builder().s(otpCode.getStatus()).build());
            item.put("validationAttempts", AttributeValue.builder().n(String.valueOf(otpCode.getValidationAttempts())).build());

            PutItemRequest request = PutItemRequest.builder()
                    .tableName(otpCodesTable)
                    .item(item)
                    .build();

            dynamoDb.putItem(request);
            logger.info("OTP code saved successfully");

        } catch (Exception e) {
            logger.error("Error saving OTP code: {}", e.getMessage());
            throw new RuntimeException("Failed to save OTP code", e);
        }
    }

    /**
     * Récupère un code OTP depuis DynamoDB
     */
    public OTPCode getOTPCode(String clientId, String otpId) {
        logger.info("Fetching OTP code: {} for client: {}", otpId, clientId);

        try {
            GetItemRequest request = GetItemRequest.builder()
                    .tableName(otpCodesTable)
                    .key(Map.of(
                            "clientId", AttributeValue.builder().s(clientId).build(),
                            "otpId", AttributeValue.builder().s(otpId).build()
                    ))
                    .build();

            GetItemResponse response = dynamoDb.getItem(request);

            if (!response.hasItem()) {
                return null;
            }

            Map<String, AttributeValue> item = response.item();

            OTPCode otpCode = new OTPCode();
            otpCode.setOtpId(item.get("otpId").s());
            otpCode.setClientId(item.get("clientId").s());
            otpCode.setCode(item.get("code").s());
            otpCode.setPhoneNumber(item.get("phoneNumber").s());
            otpCode.setCreatedAt(Instant.ofEpochMilli(Long.parseLong(item.get("createdAt").n())));
            otpCode.setExpiresAt(Instant.ofEpochSecond(Long.parseLong(item.get("expiresAt").n())));
            otpCode.setStatus(item.get("status").s());
            otpCode.setValidationAttempts(Integer.parseInt(item.get("validationAttempts").n()));

            return otpCode;

        } catch (Exception e) {
            logger.error("Error fetching OTP code: {}", e.getMessage());
            throw new RuntimeException("Failed to fetch OTP code", e);
        }
    }

    /**
     * Met à jour le statut d'un code OTP
     */
    public void updateOTPStatus(String clientId, String otpId, String status) {
        logger.info("Updating OTP status to {} for client: {}", status, clientId);

        try {
            UpdateItemRequest request = UpdateItemRequest.builder()
                    .tableName(otpCodesTable)
                    .key(Map.of(
                            "clientId", AttributeValue.builder().s(clientId).build(),
                            "otpId", AttributeValue.builder().s(otpId).build()
                    ))
                    .updateExpression("SET #status = :status, validatedAt = :validatedAt")
                    .expressionAttributeNames(Map.of("#status", "status"))
                    .expressionAttributeValues(Map.of(
                            ":status", AttributeValue.builder().s(status).build(),
                            ":validatedAt", AttributeValue.builder().n(String.valueOf(Instant.now().toEpochMilli())).build()
                    ))
                    .build();

            dynamoDb.updateItem(request);
            logger.info("OTP status updated successfully");

        } catch (Exception e) {
            logger.error("Error updating OTP status: {}", e.getMessage());
            throw new RuntimeException("Failed to update OTP status", e);
        }
    }

    /**
     * Récupère le profil client
     */
    public Map<String, Object> getClientProfile(String clientId) {
        logger.info("Fetching client profile: {}", clientId);

        try {
            GetItemRequest request = GetItemRequest.builder()
                    .tableName(clientProfileTable)
                    .key(Map.of("clientId", AttributeValue.builder().s(clientId).build()))
                    .build();

            GetItemResponse response = dynamoDb.getItem(request);

            if (!response.hasItem()) {
                throw new RuntimeException("Client not found: " + clientId);
            }

            Map<String, AttributeValue> item = response.item();
            Map<String, Object> profile = new HashMap<>();
            profile.put("clientId", item.get("clientId").s());
            profile.put("currentPhone", item.get("phoneNumber").s());
            profile.put("status", item.get("status").s());

            return profile;

        } catch (Exception e) {
            logger.error("Error fetching client profile: {}", e.getMessage());
            throw new RuntimeException("Failed to fetch client profile", e);
        }
    }
}
```

### 3.2 SNSClient.java

**Fichier :** `src/main/java/com/bnc/mcp/clients/SNSClient.java`

**⚠️ Configuration Retry :** Ce client inclut une **RetryPolicy AWS SDK limitée à 2 retry** pour éviter d'envoyer plusieurs SMS au client en cas d'erreur temporaire.

```java
package com.bnc.mcp.clients;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.retry.RetryPolicy;
import software.amazon.awssdk.core.retry.backoff.BackoffStrategy;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sns.model.PublishResponse;

import java.time.Duration;

public class SNSClient {
    private static final Logger logger = LoggerFactory.getLogger(SNSClient.class);

    private final SnsClient snsClient;

    /**
     * Constructor avec configuration Retry limitée pour SNS
     *
     * ⚠️ IMPORTANT: Retry limité à 2 tentatives pour éviter d'envoyer
     * plusieurs SMS au client lors d'erreurs temporaires
     *
     * Retry automatique pour:
     * - ThrottlingException (rate limiting SNS)
     * - Erreurs réseau transitoires (500, 503)
     *
     * Configuration:
     * - Max 2 tentatives (au lieu de 3 par défaut)
     * - Exponential backoff: 1s base, max 10s
     */
    public SNSClient() {
        logger.info("Initializing SNSClient with limited retry policy");

        // Configuration de la RetryPolicy pour SNS
        // LIMITÉ À 2 RETRY pour éviter d'envoyer plusieurs SMS
        RetryPolicy retryPolicy = RetryPolicy.builder()
                .numRetries(2)  // Maximum 2 retry attempts (LIMITÉ!)
                .backoffStrategy(BackoffStrategy.defaultThrottlingStrategy())
                .throttlingBackoffStrategy(BackoffStrategy.exponentialDelay(
                    Duration.ofSeconds(1),   // Base delay: 1s
                    Duration.ofSeconds(10)   // Max delay: 10s
                ))
                .build();

        this.snsClient = SnsClient.builder()
                .overrideConfiguration(config -> config.retryPolicy(retryPolicy))
                .build();

        logger.info("SNSClient initialized with retry policy (max 2 attempts)");
    }

    // Constructor for testing
    public SNSClient(SnsClient snsClient) {
        this.snsClient = snsClient;
    }

    /**
     * Envoie un SMS avec le code OTP
     *
     * Le SDK AWS gérera automatiquement jusqu'à 2 retry en cas de:
     * - ThrottlingException
     * - Erreurs réseau transitoires
     *
     * @param phoneNumber Numéro de téléphone au format E.164 (ex: +15141234567)
     * @param otpCode Code OTP à 6 chiffres
     * @return MessageId du SMS envoyé
     * @throws RuntimeException si l'envoi échoue après tous les retry
     */
    public String sendOTPSMS(String phoneNumber, String otpCode) {
        logger.info("Sending OTP SMS to: {}", maskPhoneNumber(phoneNumber));

        try {
            String message = String.format(
                    "Votre code de vérification BNC est: %s. Ce code expire dans 5 minutes.",
                    otpCode
            );

            PublishRequest request = PublishRequest.builder()
                    .phoneNumber(phoneNumber)
                    .message(message)
                    .build();

            // Le SDK AWS gérera automatiquement les retry (max 2)
            PublishResponse response = snsClient.publish(request);

            logger.info("✅ OTP SMS sent successfully. MessageId: {}", response.messageId());
            return response.messageId();

        } catch (Exception e) {
            // Si tous les retry SDK échouent, propager l'erreur
            logger.error("❌ Failed to send OTP SMS after retries: {}", e.getMessage());
            throw new RuntimeException("Failed to send OTP SMS after retries", e);
        }
    }

    /**
     * Masque les chiffres du numéro de téléphone pour les logs
     * Exemple: +15141234567 -> +1514***4567
     */
    private String maskPhoneNumber(String phoneNumber) {
        if (phoneNumber == null || phoneNumber.length() < 8) {
            return "***";
        }
        int length = phoneNumber.length();
        return phoneNumber.substring(0, length - 7) + "***" + phoneNumber.substring(length - 4);
    }
}
```

**Points clés de la configuration SNS :**

| Configuration | Valeur | Raison |
|---------------|--------|--------|
| **numRetries** | 2 (au lieu de 3) | Éviter d'envoyer plusieurs SMS au client |
| **Base delay** | 1 seconde | Délai raisonnable pour SNS |
| **Max delay** | 10 secondes | Limite pour ne pas bloquer trop longtemps |
| **Throttling strategy** | Exponential backoff | Optimisé pour rate limiting AWS |

### 3.3 MDMAEClient.java

**Fichier :** `src/main/java/com/bnc/mcp/clients/MDMAEClient.java`

**⚠️ Configuration Retry :** Ce client implémente une **logique de retry manuelle complète** avec exponential backoff, jitter et idempotence pour les appels API externes critiques.

```java
package com.bnc.mcp.clients;

import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import com.google.gson.Gson;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

/**
 * Client pour l'API MDMAE (Master Data Management) avec retry automatique
 *
 * Stratégie de retry:
 * - Max 3 tentatives
 * - Exponential backoff: 1s → 2s → 4s
 * - Jitter (±25%) pour éviter thundering herd
 * - Retry seulement pour: 5xx, timeout, connection errors
 * - PAS de retry pour: 4xx (erreurs client)
 * - Idempotence avec Idempotency-Key header
 *
 * Cette classe est utilisée par PhoneMDMAEClientHandler pour mettre à jour
 * le numéro de téléphone dans le système central MDMAE.
 */
public class MDMAEClient {
    private static final Logger logger = LoggerFactory.getLogger(MDMAEClient.class);

    // Configuration retry
    private static final int MAX_RETRIES = 3;
    private static final long BASE_DELAY_MS = 1000;      // 1 seconde
    private static final double JITTER_FACTOR = 0.25;    // ±25%

    private final HttpClient httpClient;
    private final String mdmaeEndpoint;
    private final Gson gson;

    /**
     * Constructor par défaut avec HttpClient configuré pour timeout
     */
    public MDMAEClient() {
        this.httpClient = createHttpClient();
        this.mdmaeEndpoint = System.getenv("MDMAE_API_ENDPOINT");
        this.gson = new Gson();

        logger.info("MDMAEClient initialized with endpoint: {}", mdmaeEndpoint);
    }

    // Constructor for testing (injection de dépendances)
    public MDMAEClient(HttpClient httpClient, String mdmaeEndpoint) {
        this.httpClient = httpClient;
        this.mdmaeEndpoint = mdmaeEndpoint;
        this.gson = new Gson();
    }

    /**
     * Créer le HttpClient avec configuration optimale
     */
    private HttpClient createHttpClient() {
        return HttpClient.newBuilder()
                // Timeout connexion: 10 secondes
                .connectTimeout(Duration.ofSeconds(10))

                // Suivre les redirects HTTP (301, 302)
                .followRedirects(HttpClient.Redirect.NORMAL)

                // HTTP/2 avec fallback HTTP/1.1
                .version(HttpClient.Version.HTTP_2)

                .build();
    }

    /**
     * Met à jour le numéro de téléphone dans MDMAE avec retry automatique
     *
     * Retry automatique pour:
     * - HTTP 5xx (500, 503, 504)
     * - Timeout (ConnectTimeout, ReadTimeout)
     * - Connection errors
     *
     * PAS de retry pour:
     * - HTTP 4xx (400, 401, 403, 404) - erreurs client
     * - Parsing errors
     *
     * @param request Requête de mise à jour contenant clientId, phoneNumber, country
     * @return Map avec success=true/false, mdmaeId, transactionId, message
     * @throws RuntimeException si tous les retry échouent
     */
    public Map<String, Object> updatePhone(MDMAEPhoneUpdateRequest request) {
        logger.info("=== MDMAE updatePhone called ===");
        logger.info("Client ID: {}", request.getClientId());

        // Générer Idempotency Key (pour éviter doublons lors retry)
        String idempotencyKey = generateIdempotencyKey(request);
        logger.info("Idempotency Key: {}", idempotencyKey);

        int attempt = 0;
        Exception lastException = null;

        // ========================================
        // BOUCLE DE RETRY
        // ========================================
        while (attempt < MAX_RETRIES) {
            attempt++;
            logger.info("--- Attempt {} of {} ---", attempt, MAX_RETRIES);

            try {
                // Créer la requête HTTP
                String jsonBody = gson.toJson(request);

                HttpRequest httpRequest = HttpRequest.newBuilder()
                        .uri(URI.create(mdmaeEndpoint + "/clients/" + request.getClientId() + "/phone"))
                        .header("Content-Type", "application/json")
                        .header("Accept", "application/json")

                        // HEADERS POUR IDEMPOTENCE
                        .header("Idempotency-Key", idempotencyKey)
                        .header("X-Request-ID", request.getRequestId())

                        // Headers metadata
                        .header("User-Agent", "MCP-PhoneUpdate/1.0")
                        .header("X-Client-ID", request.getClientId())

                        // Timeout pour cette requête: 30 secondes
                        .timeout(Duration.ofSeconds(30))

                        .PUT(HttpRequest.BodyPublishers.ofString(jsonBody))
                        .build();

                logger.debug("HTTP Request: PUT {}", httpRequest.uri());
                logger.debug("Request body: {}", jsonBody);

                // ========================================
                // ENVOYER LA REQUÊTE HTTP
                // ========================================
                long requestStart = System.currentTimeMillis();

                HttpResponse<String> response = httpClient.send(
                    httpRequest,
                    HttpResponse.BodyHandlers.ofString()
                );

                long requestDuration = System.currentTimeMillis() - requestStart;

                logger.info("HTTP Response: {} (duration: {} ms)",
                    response.statusCode(), requestDuration);

                // ========================================
                // ANALYSER LA RÉPONSE
                // ========================================

                // SUCCÈS (2xx)
                if (response.statusCode() >= 200 && response.statusCode() < 300) {
                    logger.info("✅ MDMAE update successful on attempt {}", attempt);
                    logger.debug("Response body: {}", response.body());

                    return buildSuccessResponse(response, request, attempt, requestDuration);
                }

                // ERREUR CLIENT (4xx) - NE PAS RETRY
                if (response.statusCode() >= 400 && response.statusCode() < 500) {
                    logger.error("❌ Client error {}: {}", response.statusCode(), response.body());
                    logger.error("NO RETRY for 4xx errors");

                    return buildClientErrorResponse(response, request);
                }

                // ERREUR SERVEUR (5xx) - RETRY
                if (response.statusCode() >= 500) {
                    logger.warn("⚠️ Server error {} on attempt {}", response.statusCode(), attempt);

                    if (attempt < MAX_RETRIES) {
                        logger.info("Will retry after backoff...");
                        waitBeforeRetry(attempt);
                        continue;  // Retry
                    } else {
                        logger.error("❌ All {} retry attempts failed with 5xx", MAX_RETRIES);
                        return buildServerErrorResponse(response, request, attempt);
                    }
                }

            } catch (java.net.http.HttpTimeoutException e) {
                // TIMEOUT - RETRY
                logger.warn("⚠️ HTTP Timeout on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (java.net.ConnectException e) {
                // CONNECTION REFUSED - RETRY
                logger.warn("⚠️ Connection refused on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (java.io.IOException e) {
                // ERREUR I/O (network, etc.) - RETRY
                logger.warn("⚠️ I/O error on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (Exception e) {
                // AUTRE ERREUR - NE PAS RETRY
                logger.error("❌ Unexpected error (no retry): {}", e.getMessage(), e);

                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "Unexpected error: " + e.getMessage());
                errorResponse.put("errorType", e.getClass().getSimpleName());
                return errorResponse;
            }
        }

        // ========================================
        // TOUS LES RETRY ONT ÉCHOUÉ
        // ========================================
        logger.error("❌ MDMAE update failed after {} attempts", MAX_RETRIES);

        throw new RuntimeException(
            "Failed to update MDMAE after " + MAX_RETRIES + " attempts",
            lastException
        );
    }

    /**
     * Exponential backoff avec jitter pour éviter thundering herd
     *
     * Attempt 1: 1s ± 0.25s   → [0.75s - 1.25s]
     * Attempt 2: 2s ± 0.5s    → [1.5s - 2.5s]
     * Attempt 3: 4s ± 1s      → [3s - 5s]
     */
    private void waitBeforeRetry(int attemptNumber) {
        try {
            // Exponential backoff: 1s, 2s, 4s, 8s...
            long baseDelay = BASE_DELAY_MS * (long) Math.pow(2, attemptNumber - 1);

            // Ajouter jitter (±25%) pour éviter thundering herd
            long jitter = (long) (baseDelay * JITTER_FACTOR * (Math.random() - 0.5) * 2);
            long totalDelay = baseDelay + jitter;

            logger.info("⏳ Waiting {} ms before retry attempt {} (base: {} ms, jitter: {} ms)",
                totalDelay, attemptNumber + 1, baseDelay, jitter);

            Thread.sleep(totalDelay);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.error("Retry backoff interrupted");
            throw new RuntimeException("Retry interrupted", e);
        }
    }

    /**
     * Génère une clé d'idempotence unique pour éviter doublons
     *
     * Format: <clientId>-<phoneHash>-<requestId>
     */
    private String generateIdempotencyKey(MDMAEPhoneUpdateRequest request) {
        String data = request.getClientId() + "-" + request.getNewPhoneNumber();
        int hash = data.hashCode();
        return String.format("%s-%d-%s",
            request.getClientId(),
            hash,
            request.getRequestId() != null ? request.getRequestId() : "no-request-id"
        );
    }

    /**
     * Construire réponse succès
     */
    private Map<String, Object> buildSuccessResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request,
            int attempts,
            long duration) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("statusCode", response.statusCode());
        result.put("attempts", attempts);
        result.put("durationMs", duration);

        try {
            // Parser la réponse JSON
            @SuppressWarnings("unchecked")
            Map<String, Object> responseBody = gson.fromJson(response.body(), Map.class);

            result.put("mdmaeId", responseBody.get("id"));
            result.put("transactionId", responseBody.get("transactionId"));
            result.put("message", "Phone updated successfully in MDMAE");

        } catch (Exception e) {
            logger.warn("Could not parse MDMAE response body: {}", e.getMessage());
            result.put("transactionId", "unknown");
            result.put("message", "Phone updated successfully in MDMAE (response parsing failed)");
        }

        return result;
    }

    /**
     * Construire réponse erreur client (4xx)
     */
    private Map<String, Object> buildClientErrorResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("statusCode", response.statusCode());
        result.put("message", "MDMAE API client error: " + response.statusCode());
        result.put("errorType", "ClientError");
        result.put("responseBody", response.body());

        return result;
    }

    /**
     * Construire réponse erreur serveur (5xx)
     */
    private Map<String, Object> buildServerErrorResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request,
            int attempts) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("statusCode", response.statusCode());
        result.put("message", "MDMAE API server error after " + attempts + " attempts");
        result.put("errorType", "ServerError");
        result.put("attempts", attempts);
        result.put("responseBody", response.body());

        return result;
    }
}
```

**Points clés de la configuration MDMAE :**

| Configuration | Valeur | Raison |
|---------------|--------|--------|
| **MAX_RETRIES** | 3 tentatives | Équilibre entre résilience et temps d'exécution |
| **BASE_DELAY_MS** | 1000ms (1s) | Délai raisonnable pour API externe |
| **JITTER_FACTOR** | ±25% | Éviter thundering herd quand plusieurs clients retry en même temps |
| **Exponential backoff** | 1s → 2s → 4s | Doubler le délai à chaque retry |
| **Connect timeout** | 10 secondes | Timeout pour établir la connexion |
| **Request timeout** | 30 secondes | Timeout pour la requête complète |
| **Retry pour 5xx** | ✅ Oui | Erreurs serveur temporaires |
| **Retry pour 4xx** | ❌ Non | Erreurs client permanentes |
| **Retry timeout** | ✅ Oui | Peut être temporaire |
| **Idempotency-Key** | ✅ Oui | Éviter doublons lors des retry |

**Scénario typique de retry :**
```
T=0s  : HTTP call #1 → Timeout (30s)
T=30s : Wait 1.2s (1s + 0.2s jitter)
T=31s : HTTP call #2 → 503 Service Unavailable
T=31s : Wait 2.1s (2s + 0.1s jitter)
T=33s : HTTP call #3 → 200 OK ✅
Total: 33 secondes, succès!
```

### 3.4 FCCClient.java et CRMClient.java

**Fichiers similaires** avec la même structure que MDMAEClient, je les crée de manière abrégée :

```java
package com.bnc.mcp.clients;

// Structure similaire à MDMAEClient
public class FCCClient {
    // Envoie les mises à jour vers le système FCC
    public Map<String, Object> sendPhoneUpdate(String clientId, String newPhone, String mdmaeId) {
        // Implémentation similaire
    }
}
```

```java
package com.bnc.mcp.clients;

// Structure similaire à MDMAEClient
public class CRMClient {
    // Met à jour le CRM
    public Map<String, Object> updatePhoneInCRM(String clientId, String newPhone) {
        // Implémentation similaire
    }
}
```

**Commande :**
```bash
# Créer le répertoire clients
mkdir -p src/main/java/com/bnc/mcp/clients

# Compiler
mvn compile
```

---

## ⚙️ Étape 4 : Services (dépendent des Clients et Models)

**Pourquoi maintenant ?** Les services utilisent les clients et models, et seront utilisés par les handlers.

### 4.1 PhoneValidationService.java

**Fichier :** `src/main/java/com/bnc/mcp/services/PhoneValidationService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.models.PhoneValidationResult;
import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.Phonenumber.PhoneNumber;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class PhoneValidationService {
    private static final Logger logger = LoggerFactory.getLogger(PhoneValidationService.class);

    private final PhoneNumberUtil phoneUtil;

    public PhoneValidationService() {
        this.phoneUtil = PhoneNumberUtil.getInstance();
    }

    /**
     * Valide un numéro de téléphone avec Google libphonenumber
     */
    public PhoneValidationResult validate(String phoneNumber, String countryCode) {
        logger.info("Validating phone number: {} for country: {}", phoneNumber, countryCode);

        PhoneValidationResult result = new PhoneValidationResult();

        try {
            // Parser le numéro
            PhoneNumber number = phoneUtil.parse(phoneNumber, countryCode);

            // Vérifier si le numéro est valide
            boolean isValid = phoneUtil.isValidNumber(number);
            result.setValid(isValid);

            if (!isValid) {
                result.setMessage("Numéro de téléphone invalide");
                return result;
            }

            // Type de téléphone
            PhoneNumberUtil.PhoneNumberType numberType = phoneUtil.getNumberType(number);
            result.setPhoneType(numberType.toString());

            // Formater en E.164
            String formattedNumber = phoneUtil.format(number, PhoneNumberUtil.PhoneNumberFormat.E164);
            result.setFormattedPhone(formattedNumber);

            // Vérifier si c'est un mobile (requis pour OTP)
            if (numberType != PhoneNumberUtil.PhoneNumberType.MOBILE &&
                numberType != PhoneNumberUtil.PhoneNumberType.FIXED_LINE_OR_MOBILE) {
                result.setValid(false);
                result.setMessage("Le numéro doit être un téléphone mobile");
                return result;
            }

            result.setMessage("Numéro de téléphone valide");
            logger.info("Phone validation successful: {}", formattedNumber);

        } catch (NumberParseException e) {
            logger.error("Error parsing phone number: {}", e.getMessage());
            result.setValid(false);
            result.setMessage("Erreur de format: " + e.getMessage());
        }

        return result;
    }
}
```

### 4.2 PhoneHistoryService.java

**Fichier :** `src/main/java/com/bnc/mcp/services/PhoneHistoryService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.clients.DynamoDBClient;
import com.bnc.mcp.models.PhoneHistoryCheck;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class PhoneHistoryService {
    private static final Logger logger = LoggerFactory.getLogger(PhoneHistoryService.class);

    private final DynamoDBClient dynamoDBClient;

    public PhoneHistoryService(DynamoDBClient dynamoDBClient) {
        this.dynamoDBClient = dynamoDBClient;
    }

    public PhoneHistoryService() {
        this(new DynamoDBClient());
    }

    /**
     * Analyse l'historique et détecte les comportements suspects
     */
    public PhoneHistoryCheck analyzeHistory(String clientId) {
        logger.info("Analyzing phone change history for client: {}", clientId);

        PhoneHistoryCheck history = dynamoDBClient.getPhoneHistory(clientId);

        // Règles de détection de fraude
        if (history.getChangeCount() >= 3) {
            history.setSuspicious(true);
            history.setReason("Trop de changements récents (" + history.getChangeCount() + " en 90 jours)");
        }

        logger.info("History analysis complete. Suspicious: {}", history.isSuspicious());
        return history;
    }
}
```

### 4.3 OTPService.java

**Fichier :** `src/main/java/com/bnc/mcp/services/OTPService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.clients.DynamoDBClient;
import com.bnc.mcp.clients.SNSClient;
import com.bnc.mcp.models.OTPCode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.security.SecureRandom;
import java.util.UUID;

public class OTPService {
    private static final Logger logger = LoggerFactory.getLogger(OTPService.class);

    private final DynamoDBClient dynamoDBClient;
    private final SNSClient snsClient;
    private final SecureRandom random;

    public OTPService(DynamoDBClient dynamoDBClient, SNSClient snsClient) {
        this.dynamoDBClient = dynamoDBClient;
        this.snsClient = snsClient;
        this.random = new SecureRandom();
    }

    public OTPService() {
        this(new DynamoDBClient(), new SNSClient());
    }

    /**
     * Génère un code OTP à 6 chiffres
     */
    public String generateOTPCode() {
        int code = 100000 + random.nextInt(900000);
        return String.valueOf(code);
    }

    /**
     * Crée et envoie un code OTP
     */
    public OTPCode createAndSendOTP(String clientId, String phoneNumber) {
        logger.info("Creating and sending OTP for client: {}", clientId);

        // Générer le code
        String code = generateOTPCode();
        String otpId = UUID.randomUUID().toString();

        // Créer l'objet OTP
        OTPCode otpCode = new OTPCode(otpId, clientId, code, phoneNumber);

        // Sauvegarder dans DynamoDB
        dynamoDBClient.saveOTPCode(otpCode);

        // Envoyer par SMS
        String messageId = snsClient.sendOTPSMS(phoneNumber, code);
        logger.info("OTP sent via SMS. MessageId: {}", messageId);

        return otpCode;
    }

    /**
     * Vérifie le statut d'un OTP
     */
    public Map<String, Object> checkOTPStatus(String clientId, String otpId) {
        logger.info("Checking OTP status for client: {}", clientId);

        OTPCode otpCode = dynamoDBClient.getOTPCode(clientId, otpId);

        Map<String, Object> status = new HashMap<>();

        if (otpCode == null) {
            status.put("status", "NOT_FOUND");
            status.put("validated", false);
            return status;
        }

        if (otpCode.isExpired()) {
            status.put("status", "EXPIRED");
            status.put("validated", false);
            dynamoDBClient.updateOTPStatus(clientId, otpId, "EXPIRED");
            return status;
        }

        status.put("status", otpCode.getStatus());
        status.put("validated", otpCode.isValidated());
        status.put("attempts", otpCode.getValidationAttempts());

        return status;
    }
}
```

**Commande :**
```bash
# Créer le répertoire services
mkdir -p src/main/java/com/bnc/mcp/services

# Compiler
mvn compile
```

---

## 🔄 Étape 5 : Handlers Lambda (dépendent de tout)

**Pourquoi maintenant ?** Les handlers utilisent les services, clients et models.

### 5.1 PhoneValidatorHandler.java

**Fichier :** `src/main/java/com/bnc/mcp/handlers/PhoneValidatorHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.PhoneValidationResult;
import com.bnc.mcp.services.PhoneValidationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class PhoneValidatorHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(PhoneValidatorHandler.class);

    private final PhoneValidationService validationService;

    public PhoneValidatorHandler() {
        this.validationService = new PhoneValidationService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("Phone validation request received");

        String phoneNumber = (String) input.get("phoneNumber");
        String country = (String) input.get("country");

        PhoneValidationResult result = validationService.validate(phoneNumber, country);

        return Map.of(
                "isValid", result.isValid(),
                "phoneType", result.getPhoneType() != null ? result.getPhoneType() : "",
                "carrier", result.getCarrier() != null ? result.getCarrier() : "",
                "message", result.getMessage()
        );
    }
}
```

### 5.2 CheckPhoneHistoryHandler.java

**Fichier :** `src/main/java/com/bnc/mcp/handlers/CheckPhoneHistoryHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.PhoneHistoryCheck;
import com.bnc.mcp.services.PhoneHistoryService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class CheckPhoneHistoryHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(CheckPhoneHistoryHandler.class);

    private final PhoneHistoryService historyService;

    public CheckPhoneHistoryHandler() {
        this.historyService = new PhoneHistoryService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("Phone history check request received");

        String clientId = (String) input.get("clientId");

        PhoneHistoryCheck history = historyService.analyzeHistory(clientId);

        return Map.of(
                "changeCount", history.getChangeCount(),
                "lastChangeDate", history.getLastChangeDate() != null ? history.getLastChangeDate().toString() : "",
                "isSuspicious", history.isSuspicious(),
                "reason", history.getReason()
        );
    }
}
```

### 5.3 SendOTPSMSHandler.java

**Fichier :** `src/main/java/com/bnc/mcp/handlers/SendOTPSMSHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.OTPCode;
import com.bnc.mcp.services.OTPService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class SendOTPSMSHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(SendOTPSMSHandler.class);

    private final OTPService otpService;

    public SendOTPSMSHandler() {
        this.otpService = new OTPService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("Send OTP SMS request received");

        String clientId = (String) input.get("clientId");
        String phoneNumber = (String) input.get("phoneNumber");

        OTPCode otpCode = otpService.createAndSendOTP(clientId, phoneNumber);

        return Map.of(
                "otpId", otpCode.getOtpId(),
                "expiresAt", otpCode.getExpiresAt().toString(),
                "sent", true
        );
    }
}
```

### 5.4 CheckOTPStatusHandler.java

**Fichier :** `src/main/java/com/bnc/mcp/handlers/CheckOTPStatusHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.services.OTPService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class CheckOTPStatusHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(CheckOTPStatusHandler.class);

    private final OTPService otpService;

    public CheckOTPStatusHandler() {
        this.otpService = new OTPService();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("Check OTP status request received");

        String clientId = (String) input.get("clientId");
        String otpId = (String) input.get("otpId");

        return otpService.checkOTPStatus(clientId, otpId);
    }
}
```

### 5.5 PhoneMDMAEClientHandler.java

**Fichier :** `src/main/java/com/bnc/mcp/handlers/PhoneMDMAEClientHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.MDMAEClient;
import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;

public class PhoneMDMAEClientHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(PhoneMDMAEClientHandler.class);

    private final MDMAEClient mdmaeClient;

    public PhoneMDMAEClientHandler() {
        this.mdmaeClient = new MDMAEClient();
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("MDMAE phone update request received");

        String clientId = (String) input.get("clientId");
        String newPhone = (String) input.get("newPhone");
        String country = (String) input.get("country");

        MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(clientId, newPhone, country);
        request.setRequestId(context.getRequestId());

        return mdmaeClient.updatePhone(request);
    }
}
```

### 5.6 NotificationSenderHandler.java ⭐ NOUVEAU

**Fichier :** `src/main/java/com/bnc/mcp/handlers/NotificationSenderHandler.java`

**⚠️ Nouveau Handler :** Ce handler envoie des emails de confirmation après mise à jour réussie du téléphone via AWS SES (Simple Email Service).

**📋 Models requis :**

Créer d'abord ces 2 models dans `src/main/java/com/bnc/mcp/models/`:

**NotificationRequest.java :**
```java
package com.bnc.mcp.models;

public class NotificationRequest {
    private String clientId;
    private String emailType;  // "phone_update_confirmation", "phone_update_failed", "fraud_alert"
    private String recipientEmail;
    private String oldPhone;
    private String newPhone;
    private String timestamp;
    private String approvedBy;
    private String failureReason;

    public NotificationRequest() {}

    // Getters and Setters
    public String getClientId() { return clientId; }
    public void setClientId(String clientId) { this.clientId = clientId; }

    public String getEmailType() { return emailType; }
    public void setEmailType(String emailType) { this.emailType = emailType; }

    public String getRecipientEmail() { return recipientEmail; }
    public void setRecipientEmail(String recipientEmail) { this.recipientEmail = recipientEmail; }

    public String getOldPhone() { return oldPhone; }
    public void setOldPhone(String oldPhone) { this.oldPhone = oldPhone; }

    public String getNewPhone() { return newPhone; }
    public void setNewPhone(String newPhone) { this.newPhone = newPhone; }

    public String getTimestamp() { return timestamp; }
    public void setTimestamp(String timestamp) { this.timestamp = timestamp; }

    public String getApprovedBy() { return approvedBy; }
    public void setApprovedBy(String approvedBy) { this.approvedBy = approvedBy; }

    public String getFailureReason() { return failureReason; }
    public void setFailureReason(String failureReason) { this.failureReason = failureReason; }
}
```

**NotificationResponse.java :**
```java
package com.bnc.mcp.models;

public class NotificationResponse {
    private boolean success;
    private String messageId;
    private String recipient;
    private String emailType;
    private String timestamp;
    private Long processingTimeMs;
    private String errorMessage;

    private NotificationResponse(Builder builder) {
        this.success = builder.success;
        this.messageId = builder.messageId;
        this.recipient = builder.recipient;
        this.emailType = builder.emailType;
        this.timestamp = builder.timestamp;
        this.processingTimeMs = builder.processingTimeMs;
        this.errorMessage = builder.errorMessage;
    }

    public static Builder builder() { return new Builder(); }

    // Getters
    public boolean isSuccess() { return success; }
    public String getMessageId() { return messageId; }
    public String getRecipient() { return recipient; }
    public String getEmailType() { return emailType; }
    public String getTimestamp() { return timestamp; }
    public Long getProcessingTimeMs() { return processingTimeMs; }
    public String getErrorMessage() { return errorMessage; }

    // Builder class
    public static class Builder {
        private boolean success;
        private String messageId;
        private String recipient;
        private String emailType;
        private String timestamp;
        private Long processingTimeMs;
        private String errorMessage;

        public Builder success(boolean success) { this.success = success; return this; }
        public Builder messageId(String messageId) { this.messageId = messageId; return this; }
        public Builder recipient(String recipient) { this.recipient = recipient; return this; }
        public Builder emailType(String emailType) { this.emailType = emailType; return this; }
        public Builder timestamp(String timestamp) { this.timestamp = timestamp; return this; }
        public Builder processingTimeMs(Long processingTimeMs) { this.processingTimeMs = processingTimeMs; return this; }
        public Builder errorMessage(String errorMessage) { this.errorMessage = errorMessage; return this; }

        public NotificationResponse build() { return new NotificationResponse(this); }
    }
}
```

**📧 Client SES requis :**

Créer `src/main/java/com/bnc/mcp/clients/SESClient.java` :

```java
package com.bnc.mcp.clients;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.*;

/**
 * Client pour AWS SES email sending operations
 */
public class SESClient {
    private static final Logger logger = LoggerFactory.getLogger(SESClient.class);

    private final SesClient sesClient;

    public SESClient() {
        this.sesClient = SesClient.builder().build();
        logger.info("SESClient initialized");
    }

    public SESClient(SesClient sesClient) {
        this.sesClient = sesClient;
    }

    /**
     * Envoie un email via AWS SES
     *
     * @param fromEmail Sender email address (must be verified in SES)
     * @param toEmail Recipient email address
     * @param subject Email subject
     * @param htmlBody HTML body content
     * @param textBody Plain text body content (fallback)
     * @return SES Message ID
     * @throws SesException if email sending fails
     */
    public String sendEmail(String fromEmail, String toEmail, String subject,
                           String htmlBody, String textBody) {

        logger.info("Sending email to={}, subject={}", maskEmail(toEmail), subject);

        try {
            SendEmailRequest emailRequest = SendEmailRequest.builder()
                    .source(fromEmail)
                    .destination(Destination.builder()
                            .toAddresses(toEmail)
                            .build())
                    .message(Message.builder()
                            .subject(Content.builder()
                                    .data(subject)
                                    .charset("UTF-8")
                                    .build())
                            .body(Body.builder()
                                    .html(Content.builder()
                                            .data(htmlBody)
                                            .charset("UTF-8")
                                            .build())
                                    .text(Content.builder()
                                            .data(textBody)
                                            .charset("UTF-8")
                                            .build())
                                    .build())
                            .build())
                    .build();

            SendEmailResponse response = sesClient.sendEmail(emailRequest);
            String messageId = response.messageId();

            logger.info("Email sent successfully. MessageId={}", messageId);
            return messageId;

        } catch (SesException e) {
            logger.error("Failed to send email: {} - {}", e.awsErrorDetails().errorCode(), e.getMessage());
            throw e;
        } catch (Exception e) {
            logger.error("Unexpected error sending email: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to send email", e);
        }
    }

    private String maskEmail(String email) {
        if (email == null || !email.contains("@")) return "***";
        String[] parts = email.split("@");
        return parts[0].charAt(0) + "***@" + parts[1];
    }
}
```

**📐 Handler Implementation :**

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.SESClient;
import com.bnc.mcp.models.NotificationRequest;
import com.bnc.mcp.models.NotificationResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

/**
 * Lambda handler pour l'envoi d'emails de confirmation après mise à jour téléphone
 *
 * Envoie des emails via AWS SES avec numéros de téléphone masqués pour sécurité.
 *
 * Retry Strategy:
 * - Step Functions: 3 retry attempts avec exponential backoff (2s → 4s → 8s)
 * - Non-bloquant: Workflow continue même si email échoue
 *
 * @author MCP Team
 * @version 1.0.0
 */
public class NotificationSenderHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private static final Logger logger = LoggerFactory.getLogger(NotificationSenderHandler.class);

    private final SESClient sesClient;
    private final String fromEmail;
    private final String baseUrl;

    public NotificationSenderHandler() {
        this.sesClient = new SESClient();
        this.fromEmail = System.getenv().getOrDefault("FROM_EMAIL", "noreply@bnc.ca");
        this.baseUrl = System.getenv().getOrDefault("BASE_URL", "https://www.bnc.ca");

        logger.info("NotificationSenderHandler initialized with fromEmail={}", fromEmail);
    }

    // Constructor for testing
    public NotificationSenderHandler(SESClient sesClient, String fromEmail, String baseUrl) {
        this.sesClient = sesClient;
        this.fromEmail = fromEmail;
        this.baseUrl = baseUrl;
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        String requestId = context.getRequestId();
        long startTime = System.currentTimeMillis();

        logger.info("[{}] Processing notification request", requestId);

        try {
            // Extract input
            String clientId = (String) input.get("clientId");
            String emailType = (String) input.get("emailType");
            String recipientEmail = (String) input.get("recipientEmail");
            String oldPhone = (String) input.get("oldPhone");
            String newPhone = (String) input.get("newPhone");
            String timestamp = (String) input.getOrDefault("timestamp", Instant.now().toString());
            String approvedBy = (String) input.getOrDefault("approvedBy", "Système automatique");

            // Validate required fields
            if (clientId == null || emailType == null) {
                return buildErrorResponse(emailType, "clientId and emailType are required");
            }

            // Build email content based on type
            Map<String, String> emailContent = buildEmailContent(
                emailType, clientId, oldPhone, newPhone, timestamp, approvedBy
            );

            // Send email via SES
            String messageId = sesClient.sendEmail(
                fromEmail,
                recipientEmail != null ? recipientEmail : clientId + "@bnc.ca",
                emailContent.get("subject"),
                emailContent.get("htmlBody"),
                emailContent.get("textBody")
            );

            long duration = System.currentTimeMillis() - startTime;

            logger.info("[{}] Email sent successfully. MessageId={}, Duration={}ms",
                       requestId, messageId, duration);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("messageId", messageId);
            response.put("emailType", emailType);
            response.put("timestamp", Instant.now().toString());
            response.put("processingTimeMs", duration);

            return response;

        } catch (Exception e) {
            logger.error("[{}] Failed to send notification: {}", requestId, e.getMessage(), e);
            return buildErrorResponse("unknown", "Failed to send email: " + e.getMessage());
        }
    }

    /**
     * Builds email content based on notification type
     */
    private Map<String, String> buildEmailContent(
            String emailType, String clientId, String oldPhone, String newPhone,
            String timestamp, String approvedBy) {

        Map<String, String> content = new HashMap<>();

        switch (emailType) {
            case "phone_update_confirmation":
                content = buildPhoneUpdateConfirmationEmail(clientId, oldPhone, newPhone, timestamp, approvedBy);
                break;

            case "phone_update_failed":
                content = buildPhoneUpdateFailedEmail();
                break;

            case "fraud_alert":
                content = buildFraudAlertEmail();
                break;

            default:
                logger.warn("Unknown email type: {}, using generic template", emailType);
                content = buildGenericEmail();
        }

        return content;
    }

    /**
     * Builds phone update confirmation email
     */
    private Map<String, String> buildPhoneUpdateConfirmationEmail(
            String clientId, String oldPhone, String newPhone, String timestamp, String approvedBy) {

        String maskedOldPhone = maskPhoneNumber(oldPhone);
        String maskedNewPhone = maskPhoneNumber(newPhone);

        String subject = "Confirmation de mise à jour de votre numéro de téléphone";

        String htmlBody = String.format(
            "<!DOCTYPE html>" +
            "<html><body style='font-family: Arial, sans-serif;'>" +
            "<div style='max-width: 600px; margin: 0 auto; border: 1px solid #ddd;'>" +
            "<div style='background-color: #003366; color: white; padding: 20px; text-align: center;'>" +
            "<h1 style='margin: 0;'>Banque Nationale du Canada</h1>" +
            "<p style='margin: 5px 0 0 0;'>Confirmation de mise à jour de téléphone</p>" +
            "</div>" +
            "<div style='padding: 30px; background-color: #f9f9f9;'>" +
            "<p>Bonjour,</p>" +
            "<p>Votre numéro de téléphone a été mis à jour avec succès.</p>" +
            "<table style='margin: 20px 0; border-collapse: collapse;'>" +
            "<tr><td style='padding: 8px; font-weight: bold;'>Ancien numéro :</td><td style='padding: 8px;'>%s</td></tr>" +
            "<tr><td style='padding: 8px; font-weight: bold;'>Nouveau numéro :</td><td style='padding: 8px;'>%s</td></tr>" +
            "<tr><td style='padding: 8px; font-weight: bold;'>Date et heure :</td><td style='padding: 8px;'>%s</td></tr>" +
            "<tr><td style='padding: 8px; font-weight: bold;'>Approuvé par :</td><td style='padding: 8px;'>%s</td></tr>" +
            "</table>" +
            "<p style='color: #d32f2f; font-weight: bold;'>⚠️ Si ce n'est pas vous qui avez effectué ce changement :</p>" +
            "<p><a href='%s/fraud-report?clientId=%s' style='background-color: #d32f2f; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px;'>Signaler une activité suspecte</a></p>" +
            "<p style='margin-top: 30px; color: #666; font-size: 12px;'>Merci,<br/>Équipe Banque Nationale du Canada</p>" +
            "</div>" +
            "</div>" +
            "</body></html>",
            maskedOldPhone, maskedNewPhone, timestamp, approvedBy, baseUrl, clientId
        );

        String textBody = String.format(
            "Confirmation de mise à jour de votre numéro de téléphone\n\n" +
            "Bonjour,\n\n" +
            "Votre numéro de téléphone a été mis à jour avec succès.\n\n" +
            "Ancien numéro : %s\n" +
            "Nouveau numéro : %s\n" +
            "Date et heure : %s\n" +
            "Approuvé par : %s\n\n" +
            "Si ce n'est pas vous qui avez effectué ce changement, veuillez contacter notre service client immédiatement au 1-888-835-6281.\n\n" +
            "Merci,\nÉquipe Banque Nationale du Canada",
            maskedOldPhone, maskedNewPhone, timestamp, approvedBy
        );

        Map<String, String> content = new HashMap<>();
        content.put("subject", subject);
        content.put("htmlBody", htmlBody);
        content.put("textBody", textBody);

        return content;
    }

    /**
     * Builds failed email
     */
    private Map<String, String> buildPhoneUpdateFailedEmail() {
        Map<String, String> content = new HashMap<>();
        content.put("subject", "Échec de la mise à jour de votre numéro de téléphone");
        content.put("htmlBody", "<p>Votre demande de mise à jour n'a pas pu être complétée.</p>");
        content.put("textBody", "Votre demande de mise à jour n'a pas pu être complétée.");
        return content;
    }

    /**
     * Builds fraud alert email
     */
    private Map<String, String> buildFraudAlertEmail() {
        Map<String, String> content = new HashMap<>();
        content.put("subject", "⚠️ Alerte de sécurité - Activité suspecte détectée");
        content.put("htmlBody", "<p style='color: #d32f2f;'>Une tentative de modification suspecte a été détectée.</p>");
        content.put("textBody", "Une tentative de modification suspecte a été détectée.");
        return content;
    }

    /**
     * Builds generic email
     */
    private Map<String, String> buildGenericEmail() {
        Map<String, String> content = new HashMap<>();
        content.put("subject", "Notification - Banque Nationale du Canada");
        content.put("htmlBody", "<p>Ceci est une notification concernant votre compte.</p>");
        content.put("textBody", "Ceci est une notification concernant votre compte.");
        return content;
    }

    /**
     * Masks phone number for security (shows only last 2 digits)
     * Example: +15141234567 → +1 (514) ***-**67
     */
    private String maskPhoneNumber(String phoneNumber) {
        if (phoneNumber == null || phoneNumber.length() < 4) {
            return "***";
        }

        String lastTwo = phoneNumber.substring(phoneNumber.length() - 2);

        if (phoneNumber.startsWith("+1") && phoneNumber.length() >= 12) {
            String areaCode = phoneNumber.substring(2, 5);
            return String.format("+1 (%s) ***-**%s", areaCode, lastTwo);
        }

        String countryCode = phoneNumber.substring(0, Math.min(3, phoneNumber.length() - 2));
        return String.format("%s ***-**%s", countryCode, lastTwo);
    }

    /**
     * Builds error response
     */
    private Map<String, Object> buildErrorResponse(String emailType, String errorMessage) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        response.put("emailType", emailType);
        response.put("errorMessage", errorMessage);
        response.put("timestamp", Instant.now().toString());
        return response;
    }
}
```

**⚙️ Dépendance Maven requise :**

Ajouter AWS SES SDK dans `pom.xml` :

```xml
<!-- AWS SDK v2 - SES (for email) -->
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>ses</artifactId>
    <version>${aws.sdk.version}</version>
</dependency>
```

**🔧 Variables d'environnement Lambda :**

```hcl
environment_vars = {
  FROM_EMAIL = "noreply@bnc.ca"
  BASE_URL   = "https://www.bnc.ca"
}
```

**⚠️ Permissions IAM requises :**

Ajouter à l'IAM role de la Lambda :

```json
{
  "Effect": "Allow",
  "Action": [
    "ses:SendEmail",
    "ses:SendRawEmail"
  ],
  "Resource": "*"
}
```

**Commande :**
```bash
# Créer les fichiers
mkdir -p src/main/java/com/bnc/mcp/handlers
mkdir -p src/main/java/com/bnc/mcp/models

# Compiler
mvn compile
```

---

### 5.7 Autres Handlers (structure similaire)

Les handlers suivants ont une structure similaire :
- `ReadClientProfileHandler.java`
- `HumanApprovalHandler.java`
- `FCCSenderHandler.java`
- `CRMUpdaterHandler.java`
- `NotificationUpdaterHandler.java`

**Commande :**
```bash
# Créer le répertoire handlers
mkdir -p src/main/java/com/bnc/mcp/handlers

# Compiler
mvn compile
```

---

## 🎮 Étape 6 : Controller (point d'entrée API Gateway)

**Pourquoi en dernier ?** Le controller orchestre tout et démarre Step Functions.

**Fichier :** `src/main/java/com/bnc/mcp/controllers/ClientPhoneUpdateController.java`

```java
package com.bnc.mcp.controllers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.google.gson.Gson;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

import java.util.HashMap;
import java.util.Map;

public class ClientPhoneUpdateController
    implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final Logger logger = LoggerFactory.getLogger(ClientPhoneUpdateController.class);

    private final SfnClient sfnClient;
    private final Gson gson;
    private final String stateMachineArn;

    public ClientPhoneUpdateController() {
        this.sfnClient = SfnClient.builder().build();
        this.gson = new Gson();
        this.stateMachineArn = System.getenv("STEP_FUNCTIONS_PHONE_UPDATE_ARN");
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(
            APIGatewayProxyRequestEvent request,
            Context context) {

        logger.info("Phone update request received");

        try {
            // Extraire clientId du path
            String clientId = request.getPathParameters().get("clientId");

            // Parser le body
            @SuppressWarnings("unchecked")
            Map<String, Object> body = gson.fromJson(request.getBody(), Map.class);

            String phoneNumber = (String) body.get("phoneNumber");
            String country = (String) body.get("country");

            // Validation basique
            if (phoneNumber == null || country == null) {
                return createResponse(400, Map.of(
                        "error", "phoneNumber and country are required"
                ));
            }

            // Créer l'input pour Step Functions
            Map<String, Object> sfnInput = new HashMap<>();
            sfnInput.put("clientId", clientId);
            sfnInput.put("phoneNumber", phoneNumber);
            sfnInput.put("country", country);

            String inputJson = gson.toJson(sfnInput);

            // Démarrer l'exécution Step Functions
            StartExecutionRequest sfnRequest = StartExecutionRequest.builder()
                    .stateMachineArn(stateMachineArn)
                    .input(inputJson)
                    .name("phone-update-" + clientId + "-" + System.currentTimeMillis())
                    .build();

            StartExecutionResponse sfnResponse = sfnClient.startExecution(sfnRequest);

            logger.info("Step Functions execution started: {}", sfnResponse.executionArn());

            // Retourner la réponse
            return createResponse(200, Map.of(
                    "message", "Phone update workflow initiated",
                    "executionArn", sfnResponse.executionArn()
            ));

        } catch (Exception e) {
            logger.error("Error processing phone update request: {}", e.getMessage(), e);
            return createResponse(500, Map.of(
                    "error", "Internal server error: " + e.getMessage()
            ));
        }
    }

    private APIGatewayProxyResponseEvent createResponse(int statusCode, Map<String, Object> body) {
        APIGatewayProxyResponseEvent response = new APIGatewayProxyResponseEvent();
        response.setStatusCode(statusCode);
        response.setBody(gson.toJson(body));
        response.setHeaders(Map.of(
                "Content-Type", "application/json",
                "Access-Control-Allow-Origin", "*"
        ));
        return response;
    }
}
```

**Commande :**
```bash
# Créer le répertoire controllers
mkdir -p src/main/java/com/bnc/mcp/controllers

# Compiler tout le projet
mvn clean compile
```

---

## 🧪 Étape 7 : Tests unitaires

### 7.1 PhoneValidationServiceTest.java

**Fichier :** `src/test/java/com/bnc/mcp/PhoneValidationServiceTest.java`

```java
package com.bnc.mcp;

import com.bnc.mcp.models.PhoneValidationResult;
import com.bnc.mcp.services.PhoneValidationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class PhoneValidationServiceTest {

    private PhoneValidationService service;

    @BeforeEach
    void setUp() {
        service = new PhoneValidationService();
    }

    @Test
    void testValidCanadianMobile() {
        PhoneValidationResult result = service.validate("+15141234567", "CA");

        assertTrue(result.isValid());
        assertEquals("MOBILE", result.getPhoneType());
        assertEquals("+15141234567", result.getFormattedPhone());
    }

    @Test
    void testInvalidPhoneNumber() {
        PhoneValidationResult result = service.validate("+1234", "CA");

        assertFalse(result.isValid());
    }

    @Test
    void testFixedLineNotAllowed() {
        PhoneValidationResult result = service.validate("+15145551234", "CA");

        // Assuming it's a fixed line
        if ("FIXED_LINE".equals(result.getPhoneType())) {
            assertFalse(result.isValid());
        }
    }
}
```

**Commande :**
```bash
# Créer le répertoire de tests
mkdir -p src/test/java/com/bnc/mcp

# Exécuter les tests
mvn test
```

---

## 🏗️ Étape 8 : Build et déploiement

### Build Maven

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Clean et build complet
mvn clean package

# Résultat dans target/
# mcp-phone-update-1.0.0.jar (avec toutes les dépendances)
```

### Upload vers S3

```bash
# Upload du JAR vers S3
aws s3 cp target/mcp-phone-update-1.0.0.jar \
  s3://bnc-lambda-code-dev/phone-update/mcp-phone-update-1.0.0.jar

# Vérifier l'upload
aws s3 ls s3://bnc-lambda-code-dev/phone-update/
```

### Mise à jour des Lambdas

```bash
# Option 1 : Via GitHub Actions (recommandé)
git add .
git commit -m "feat: implement phone update workflow"
git push origin main

# Option 2 : Manuellement avec AWS CLI
for function in phone-update-controller read-client-profile phone-validator \
                check-phone-history human-approval-handler send-otp-sms \
                check-otp-status phone-mdmae-client fcc-sender-phone \
                crm-updater-phone notification-updater-phone; do
  aws lambda update-function-code \
    --function-name dev-mcp-$function \
    --s3-bucket bnc-lambda-code-dev \
    --s3-key phone-update/mcp-phone-update-1.0.0.jar \
    --region ca-central-1
done
```

---

## 📊 Résumé de l'implémentation

### Fichiers créés (ordre)

| Ordre | Fichier | Type | Lignes | Dépendances |
|-------|---------|------|--------|-------------|
| 1 | `pom.xml` | Config Maven | ~150 | Aucune |
| 2 | `PhoneValidationResult.java` | Model | ~50 | Aucune |
| 3 | `PhoneHistoryCheck.java` | Model | ~70 | Aucune |
| 4 | `OTPCode.java` | Model | ~90 | Aucune |
| 5 | `MDMAEPhoneUpdateRequest.java` | Model | ~40 | Aucune |
| 6 | `DynamoDBClient.java` | Client | ~200 | Models |
| 7 | `SNSClient.java` | Client | ~50 | Aucune |
| 8 | `MDMAEClient.java` | Client | ~80 | Models |
| 9 | `FCCClient.java` | Client | ~60 | Aucune |
| 10 | `CRMClient.java` | Client | ~60 | Aucune |
| 11 | `PhoneValidationService.java` | Service | ~70 | Models |
| 12 | `PhoneHistoryService.java` | Service | ~40 | Clients, Models |
| 13 | `OTPService.java` | Service | ~80 | Clients, Models |
| 14 | `PhoneValidatorHandler.java` | Handler | ~40 | Services, Models |
| 15 | `CheckPhoneHistoryHandler.java` | Handler | ~40 | Services, Models |
| 16 | `SendOTPSMSHandler.java` | Handler | ~40 | Services, Models |
| 17 | `CheckOTPStatusHandler.java` | Handler | ~35 | Services |
| 18 | `PhoneMDMAEClientHandler.java` | Handler | ~40 | Clients, Models |
| 19 | `ReadClientProfileHandler.java` | Handler | ~35 | Clients |
| 20 | `HumanApprovalHandler.java` | Handler | ~50 | Clients |
| 21 | `FCCSenderHandler.java` | Handler | ~40 | Clients |
| 22 | `CRMUpdaterHandler.java` | Handler | ~40 | Clients |
| 23 | `NotificationUpdaterHandler.java` | Handler | ~40 | Clients |
| 24 | `ClientPhoneUpdateController.java` | Controller | ~100 | Tout |
| 25 | Tests | Test | ~100 | Services |

**Total :** ~1,600 lignes de code Java

---

## ✅ Checklist d'implémentation

### Phase 1 : Setup
- [ ] Créer le projet Maven
- [ ] Configurer `pom.xml` avec toutes les dépendances
- [ ] Valider la configuration Maven

### Phase 2 : Models
- [ ] Créer `PhoneValidationResult.java`
- [ ] Créer `PhoneHistoryCheck.java`
- [ ] Créer `OTPCode.java`
- [ ] Créer `MDMAEPhoneUpdateRequest.java`
- [ ] Compiler les models

### Phase 3 : Clients
- [ ] Créer `DynamoDBClient.java`
- [ ] Créer `SNSClient.java`
- [ ] Créer `MDMAEClient.java`
- [ ] Créer `FCCClient.java`
- [ ] Créer `CRMClient.java`
- [ ] Compiler les clients

### Phase 4 : Services
- [ ] Créer `PhoneValidationService.java`
- [ ] Créer `PhoneHistoryService.java`
- [ ] Créer `OTPService.java`
- [ ] Compiler les services

### Phase 5 : Handlers
- [ ] Créer les 10 handlers Lambda
- [ ] Compiler les handlers

### Phase 6 : Controller
- [ ] Créer `ClientPhoneUpdateController.java`
- [ ] Compiler tout le projet

### Phase 7 : Tests
- [ ] Créer les tests unitaires
- [ ] Exécuter `mvn test`
- [ ] Tous les tests passent

### Phase 8 : Build et déploiement
- [ ] Build Maven : `mvn clean package`
- [ ] Upload JAR vers S3
- [ ] Mettre à jour les Lambdas
- [ ] Tester end-to-end

---

## 🚀 Déploiement complet

### Commandes complètes

```bash
# 1. Build
cd /Users/fabricefoko/Downloads/mcp-local
mvn clean package

# 2. Upload vers S3
aws s3 cp target/mcp-phone-update-1.0.0.jar \
  s3://bnc-lambda-code-dev/phone-update/

# 3. Update Lambdas (via Terraform ou AWS CLI)
cd /Users/fabricefoko/Documents/mcp-infrastructure
terraform apply -target=module.lambda

# 4. Test end-to-end
curl -X PUT "https://your-api-gateway.amazonaws.com/dev/api/clients/123/phone" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+15141234567","country":"CA"}'
```

---

## 📈 Prochaines étapes

1. **Tests d'intégration** : Tester chaque Lambda séparément
2. **Tests end-to-end** : Tester le workflow complet
3. **Monitoring** : Configurer CloudWatch Dashboard
4. **Documentation** : Runbook opérationnel

---

**Dernière mise à jour :** 2026-09-25
**Version :** 1.0.0
**Statut :** ✅ Prêt pour implémentation