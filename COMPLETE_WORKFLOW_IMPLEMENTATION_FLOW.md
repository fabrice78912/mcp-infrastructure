# Flow complet d'implémentation d'un workflow BNC MCP

## 📌 Table des matières

1. [Vue d'ensemble du processus](#vue-densemble-du-processus)
2. [Phase 1 : Infrastructure (mcp-infrastructure)](#phase-1--infrastructure-mcp-infrastructure)
3. [Phase 2 : Service Métier (mcp-local)](#phase-2--service-métier-mcp-local)
4. [Checklist complète d'implémentation](#checklist-complète-dimplémentation)
5. [Exemple concret : Workflow "Client Address Update"](#exemple-concret--workflow-client-address-update)
6. [Ordre de déploiement](#ordre-de-déploiement)

---

## Vue d'ensemble du processus

### Séparation des responsabilités

```
┌─────────────────────────────────────────────────────────────────┐
│                    WORKFLOW COMPLET                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
        ┌───────────────────┴────────────────────┐
        │                                        │
┌───────────────────┐                  ┌────────────────────┐
│ mcp-infrastructure│                  │    mcp-local       │
│   (Terraform)     │                  │     (Java)         │
├───────────────────┤                  ├────────────────────┤
│ ORCHESTRATION     │                  │ LOGIQUE MÉTIER     │
│                   │                  │                    │
│ • Step Functions  │                  │ • Lambda Handlers  │
│ • DynamoDB        │                  │ • Validators       │
│ • API Gateway     │                  │ • Services         │
│ • IAM Roles       │                  │ • Models (DTOs)    │
│ • CloudWatch      │                  │ • Clients (APIs)   │
│                   │                  │ • Utils            │
│ Définit QUOI      │                  │ Définit COMMENT    │
│ et QUAND          │                  │                    │
└───────────────────┘                  └────────────────────┘
        │                                        │
        └────────────┬───────────────────────────┘
                     ↓
            Workflow fonctionnel
```

### Principe clé

```
mcp-infrastructure → Crée les ressources AWS (Step Functions, Lambda placeholders)
        ↓
mcp-local → Implémente le code métier (JARs Java)
        ↓
GitHub Actions → Déploie les JARs et met à jour les Lambdas
```

---

## Phase 1 : Infrastructure (mcp-infrastructure)

### Résumé de ce qui a été fait

À ce stade, **l'infrastructure a déjà été créée** via Terraform :

✅ **Step Functions State Machine définie** (workflow JSON)
✅ **Lambdas déclarées** (avec code placeholder vide)
✅ **DynamoDB tables créées**
✅ **API Gateway endpoints configurés**
✅ **IAM roles créés**
✅ **CloudWatch Logs configurés**

### Fichiers créés/modifiés dans mcp-infrastructure

| Fichier | Action | Description |
|---------|--------|-------------|
| `modules/step_functions/state_machines/client-address-update.json` | ✅ **CRÉÉ** | Définition du workflow Step Functions |
| `modules/lambda/variables.tf` | ✅ **MODIFIÉ** | Déclaration des nouvelles Lambdas |
| `modules/dynamodb/main.tf` | ✅ **MODIFIÉ** | Nouvelle table `address-history` (si besoin) |
| `modules/api_gateway/main.tf` | ✅ **MODIFIÉ** | Route `PUT /clients/{id}/address` |
| `modules/iam/main.tf` | ✅ **MODIFIÉ** | Permissions pour les nouvelles Lambdas |
| `environments/dev/main.tf` | ✅ **MODIFIÉ** | Ajout du state machine + Lambdas |

### Outputs Terraform disponibles

Après `terraform apply`, vous avez :

```
Outputs:

state_machine_arn = "arn:aws:states:ca-central-1:123:stateMachine:dev-client-address-update"
api_gateway_url = "https://xyz.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/address"

lambda_arns = {
  "client-address-update-controller" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-client-address-update-controller"
  "address-validator" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-address-validator"
  "address-mdmae-client" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-address-mdmae-client"
}
```

**À ce stade :** Les Lambdas existent dans AWS mais **n'ont pas encore de code fonctionnel** (placeholder vide).

---

## Phase 2 : Service Métier (mcp-local)

### 🎯 Objectif

Implémenter le **code métier** (logique de validation, transformation, appels API) dans des Lambdas Java.

---

### Structure de répertoire à créer/modifier

```
mcp-local/
├── src/
│   ├── main/
│   │   └── java/
│   │       └── com/
│   │           └── bnc/
│   │               └── mcp/
│   │                   ├── controllers/               ← DOSSIER À CRÉER (si pas existant)
│   │                   │   └── ClientAddressUpdateController.java  ← CRÉER
│   │                   │
│   │                   ├── handlers/                  ← DOSSIER existant
│   │                   │   ├── AddressValidatorHandler.java         ← CRÉER
│   │                   │   ├── CheckAddressHistoryHandler.java      ← CRÉER
│   │                   │   └── AddressMdmaeClientHandler.java       ← CRÉER
│   │                   │
│   │                   ├── models/                    ← DOSSIER existant
│   │                   │   ├── Address.java                         ← CRÉER
│   │                   │   ├── AddressValidationResult.java         ← CRÉER
│   │                   │   └── AddressHistoryCheck.java             ← CRÉER
│   │                   │
│   │                   ├── validators/                ← DOSSIER À CRÉER
│   │                   │   ├── ClientIdValidator.java               ← CRÉER
│   │                   │   └── AddressValidator.java                ← CRÉER
│   │                   │
│   │                   ├── services/                  ← DOSSIER existant
│   │                   │   ├── AddressValidationService.java        ← CRÉER
│   │                   │   └── AddressHistoryService.java           ← CRÉER
│   │                   │
│   │                   ├── clients/                   ← DOSSIER existant
│   │                   │   ├── DynamoDBClient.java                  ← RÉUTILISER
│   │                   │   ├── MdmaeClient.java                     ← RÉUTILISER/MODIFIER
│   │                   │   └── SecretsManagerClient.java            ← RÉUTILISER
│   │                   │
│   │                   └── utils/                     ← DOSSIER À CRÉER
│   │                       ├── LoggingUtils.java                    ← CRÉER
│   │                       ├── MetricsUtils.java                    ← CRÉER
│   │                       └── AddressUtils.java                    ← CRÉER
│   │
│   └── test/
│       └── java/
│           └── com/
│               └── bnc/
│                   └── mcp/
│                       ├── controllers/
│                       │   └── ClientAddressUpdateControllerTest.java  ← CRÉER
│                       ├── handlers/
│                       │   ├── AddressValidatorHandlerTest.java        ← CRÉER
│                       │   └── CheckAddressHistoryHandlerTest.java     ← CRÉER
│                       ├── validators/
│                       │   └── AddressValidatorTest.java               ← CRÉER
│                       └── services/
│                           └── AddressValidationServiceTest.java       ← CRÉER
│
├── pom.xml                                             ← MODIFIER (si nouvelles dépendances)
└── .github/
    └── workflows/
        └── deploy-lambdas.yml                          ← DÉJÀ CRÉÉ (Phase précédente)
```

---

### Détails des fichiers à créer

#### 1. **Controllers** (Couche API)

##### `controllers/ClientAddressUpdateController.java`

**Rôle :** Recevoir la requête API Gateway, valider, enrichir, démarrer Step Functions

**Points clés :**
- ✅ Validation HTTP (clientId, body)
- ✅ Enrichissement métadonnées (requestId, userId, timestamp)
- ✅ Logging structuré (Datadog/Splunk)
- ✅ Démarrage Step Functions avec `sfnClient.startExecution()`
- ✅ Retour HTTP 202 Accepted

**Dépendances :**
```java
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import software.amazon.awssdk.services.sfn.SfnClient;
```

**Template de base :**
```java
@Slf4j
public class ClientAddressUpdateController implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final String stateMachineArn;
    private final ClientIdValidator clientIdValidator;
    private final AddressValidator addressValidator;

    public ClientAddressUpdateController() {
        this.sfnClient = SfnClient.builder().build();
        this.stateMachineArn = System.getenv("STATE_MACHINE_ARN");
        this.clientIdValidator = new ClientIdValidator();
        this.addressValidator = new AddressValidator();
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent request, Context context) {
        // 1. Logging
        // 2. Extraction clientId
        // 3. Validation clientId
        // 4. Parsing body
        // 5. Validation address
        // 6. Enrichissement
        // 7. Démarrer Step Functions
        // 8. Retour HTTP 202
    }
}
```

**📘 Voir :** `LAMBDA_CONTROLLER_PATTERN.md` pour le code complet

---

#### 2. **Handlers** (Couche métier - Step Functions)

##### `handlers/AddressValidatorHandler.java`

**Rôle :** Valider le format de l'adresse (code postal, province, pays)

**Input Step Functions :**
```json
{
  "clientId": "123456789",
  "address": {
    "street": "1500 rue Peel",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A1S9",
    "country": "CA"
  }
}
```

**Output Step Functions :**
```json
{
  "isValid": true,
  "errors": [],
  "normalizedAddress": {
    "street": "1500 RUE PEEL",
    "city": "MONTREAL",
    "province": "QC",
    "postalCode": "H3A 1S9",
    "country": "CA"
  }
}
```

**Template de base :**
```java
public class AddressValidatorHandler implements RequestHandler<Map<String, Object>, AddressValidationResult> {

    private final AddressValidationService validationService;

    @Override
    public AddressValidationResult handleRequest(Map<String, Object> input, Context context) {
        // 1. Extraire address depuis input
        // 2. Appeler service de validation
        // 3. Retourner résultat
    }
}
```

---

##### `handlers/CheckAddressHistoryHandler.java`

**Rôle :** Vérifier l'historique d'adresses pour détecter comportements suspects

**Logic métier :**
- Récupérer historique depuis DynamoDB
- Calculer score de suspicion (0.0 - 1.0)
- Détecter patterns suspects (changements fréquents, zones à risque)

**Output Step Functions :**
```json
{
  "suspiciousScore": 0.3,
  "changeCount": 1,
  "reason": "Low risk - stable customer",
  "previousAddresses": [...]
}
```

**Template de base :**
```java
public class CheckAddressHistoryHandler implements RequestHandler<Map<String, Object>, AddressHistoryCheck> {

    private final DynamoDbClient dynamoDb;
    private final AddressHistoryService historyService;

    @Override
    public AddressHistoryCheck handleRequest(Map<String, Object> input, Context context) {
        String clientId = (String) input.get("clientId");

        // 1. Récupérer historique DynamoDB
        List<Address> history = getAddressHistory(clientId);

        // 2. Calculer score de suspicion
        double score = historyService.calculateSuspiciousScore(history, input.get("address"));

        // 3. Retourner résultat
        return AddressHistoryCheck.builder()
            .suspiciousScore(score)
            .changeCount(history.size())
            .build();
    }
}
```

---

##### `handlers/AddressMdmaeClientHandler.java`

**Rôle :** Envoyer la mise à jour d'adresse à MDMAE (Master Data Management)

**Logic métier :**
- Récupérer credentials MDMAE depuis Secrets Manager
- Appeler API MDMAE
- Gérer retry et error handling

**Template de base :**
```java
public class AddressMdmaeClientHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final MdmaeClient mdmaeClient;

    public AddressMdmaeClientHandler() {
        String secretArn = System.getenv("MDMAE_SECRET_ARN");
        Map<String, String> credentials = getSecretValue(secretArn);

        this.mdmaeClient = new MdmaeClient(
            credentials.get("url"),
            credentials.get("api_key")
        );
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        // 1. Préparer payload MDMAE
        // 2. Appeler API MDMAE
        // 3. Retourner résultat (transactionId, status)
    }
}
```

---

#### 3. **Models** (DTOs)

##### `models/Address.java`

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Address {
    private String street;
    private String city;
    private String province;
    private String postalCode;
    private String country;
    private String type; // HOME, WORK, BILLING
}
```

##### `models/AddressValidationResult.java`

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AddressValidationResult {
    private boolean isValid;
    private List<String> errors;
    private List<String> warnings;
    private Address normalizedAddress;
}
```

##### `models/AddressHistoryCheck.java`

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AddressHistoryCheck {
    private double suspiciousScore;
    private int changeCount;
    private String reason;
    private List<Address> previousAddresses;
}
```

---

#### 4. **Validators**

##### `validators/ClientIdValidator.java`

```java
public class ClientIdValidator {

    private static final Pattern CLIENT_ID_PATTERN = Pattern.compile("^\\d{9}$");

    public boolean isValid(String clientId) {
        if (clientId == null || clientId.trim().isEmpty()) {
            return false;
        }
        return CLIENT_ID_PATTERN.matcher(clientId).matches();
    }

    public String normalize(String clientId) {
        return clientId != null ? clientId.trim() : null;
    }
}
```

##### `validators/AddressValidator.java`

```java
public class AddressValidator {

    public Map<String, String> validate(Address address) {
        Map<String, String> errors = new HashMap<>();

        if (address == null) {
            errors.put("address", "Address is required");
            return errors;
        }

        // Validate street
        if (isBlank(address.getStreet())) {
            errors.put("street", "Street is required");
        }

        // Validate city
        if (isBlank(address.getCity())) {
            errors.put("city", "City is required");
        }

        // Validate province
        if (isBlank(address.getProvince())) {
            errors.put("province", "Province is required");
        } else if (!isValidProvinceCode(address.getProvince())) {
            errors.put("province", "Invalid province code");
        }

        // Validate postal code
        if (isBlank(address.getPostalCode())) {
            errors.put("postalCode", "Postal code is required");
        } else if ("CA".equals(address.getCountry())) {
            if (!isValidCanadianPostalCode(address.getPostalCode())) {
                errors.put("postalCode", "Invalid Canadian postal code format");
            }
        }

        return errors;
    }

    private boolean isValidCanadianPostalCode(String postalCode) {
        return postalCode.matches("^[A-Z]\\d[A-Z] ?\\d[A-Z]\\d$");
    }

    private boolean isValidProvinceCode(String province) {
        return Arrays.asList("AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT")
                     .contains(province.toUpperCase());
    }
}
```

---

#### 5. **Services**

##### `services/AddressValidationService.java`

**Rôle :** Logique métier de validation complète + normalisation

```java
@Slf4j
public class AddressValidationService {

    private static final Pattern CANADIAN_POSTAL_CODE = Pattern.compile("^[A-Z]\\d[A-Z] ?\\d[A-Z]\\d$");

    public AddressValidationResult validate(Address address) {
        List<String> errors = new ArrayList<>();
        List<String> warnings = new ArrayList<>();

        // Validation country
        if (!Arrays.asList("CA", "US").contains(address.getCountry())) {
            errors.add("Country must be CA or US");
        }

        // Validation postal code format
        if ("CA".equals(address.getCountry())) {
            if (!CANADIAN_POSTAL_CODE.matcher(address.getPostalCode().toUpperCase()).matches()) {
                errors.add("Invalid Canadian postal code format");
            }
        }

        // Normalize address
        Address normalizedAddress = normalizeAddress(address);

        return AddressValidationResult.builder()
            .isValid(errors.isEmpty())
            .errors(errors)
            .warnings(warnings)
            .normalizedAddress(normalizedAddress)
            .build();
    }

    private Address normalizeAddress(Address address) {
        return Address.builder()
            .street(normalizeString(address.getStreet()))
            .city(normalizeString(address.getCity()))
            .province(address.getProvince().toUpperCase())
            .postalCode(normalizePostalCode(address.getPostalCode()))
            .country(address.getCountry().toUpperCase())
            .type(address.getType() != null ? address.getType().toUpperCase() : "HOME")
            .build();
    }

    private String normalizePostalCode(String postalCode) {
        String normalized = postalCode.toUpperCase().trim();
        // H1A1A1 → H1A 1A1
        if (normalized.length() == 6) {
            return normalized.substring(0, 3) + " " + normalized.substring(3);
        }
        return normalized;
    }
}
```

##### `services/AddressHistoryService.java`

**Rôle :** Calculer score de suspicion basé sur historique

```java
@Slf4j
public class AddressHistoryService {

    public double calculateSuspiciousScore(List<Address> history, Address newAddress) {
        double score = 0.0;

        // Règle 1 : Plus de 3 changements en 6 mois = suspect
        int recentChanges = getRecentChanges(history, 6);
        if (recentChanges > 3) {
            score += 0.3;
        }

        // Règle 2 : Changement vers zone à risque
        if (isHighRiskArea(newAddress.getPostalCode())) {
            score += 0.5;
        }

        // Règle 3 : Province différente de l'adresse actuelle
        if (history.size() > 0 && !history.get(0).getProvince().equals(newAddress.getProvince())) {
            score += 0.2;
        }

        // Règle 4 : Pays différent
        if (history.size() > 0 && !history.get(0).getCountry().equals(newAddress.getCountry())) {
            score += 0.4;
        }

        return Math.min(score, 1.0); // Cap à 1.0
    }

    private int getRecentChanges(List<Address> history, int months) {
        LocalDate cutoff = LocalDate.now().minusMonths(months);
        return (int) history.stream()
            .filter(addr -> addr.getChangedAt().isAfter(cutoff))
            .count();
    }

    private boolean isHighRiskArea(String postalCode) {
        // Liste de codes postaux à risque (exemple)
        List<String> highRiskPrefixes = Arrays.asList("H1Z", "H2Z", "M5A");
        return highRiskPrefixes.stream()
            .anyMatch(prefix -> postalCode.startsWith(prefix));
    }
}
```

---

#### 6. **Utils**

##### `utils/LoggingUtils.java`

**Rôle :** Logging structuré pour Datadog/Splunk

```java
@Slf4j
public class LoggingUtils {

    public static String buildLogContext(Object... keyValuePairs) {
        if (keyValuePairs.length % 2 != 0) {
            throw new IllegalArgumentException("Arguments must be key-value pairs");
        }

        Map<String, Object> context = new LinkedHashMap<>();
        for (int i = 0; i < keyValuePairs.length; i += 2) {
            context.put(keyValuePairs[i].toString(), keyValuePairs[i + 1]);
        }

        try {
            return new ObjectMapper().writeValueAsString(context);
        } catch (JsonProcessingException e) {
            return context.toString();
        }
    }
}
```

**Usage :**
```java
log.info("ADDRESS_UPDATE_REQUEST", LoggingUtils.buildLogContext(
    "event", "REQUEST_RECEIVED",
    "requestId", requestId,
    "clientId", clientId,
    "timestamp", Instant.now().toString()
));

// Output JSON structuré :
// {"event":"REQUEST_RECEIVED","requestId":"abc123","clientId":"123456789","timestamp":"2026-09-24T10:30:00Z"}
```

##### `utils/MetricsUtils.java`

**Rôle :** Métriques custom pour Datadog

```java
public class MetricsUtils {

    private final CloudWatchClient cloudWatch;

    public MetricsUtils() {
        this.cloudWatch = CloudWatchClient.builder().build();
    }

    public void incrementCounter(String metricName) {
        cloudWatch.putMetricData(PutMetricDataRequest.builder()
            .namespace("BNC/MCP")
            .metricData(MetricDatum.builder()
                .metricName(metricName)
                .value(1.0)
                .unit(StandardUnit.COUNT)
                .timestamp(Instant.now())
                .build())
            .build());
    }

    public void recordLatency(String metricName, long durationMs) {
        cloudWatch.putMetricData(PutMetricDataRequest.builder()
            .namespace("BNC/MCP")
            .metricData(MetricDatum.builder()
                .metricName(metricName)
                .value((double) durationMs)
                .unit(StandardUnit.MILLISECONDS)
                .timestamp(Instant.now())
                .build())
            .build());
    }
}
```

**Usage :**
```java
metricsUtils.incrementCounter("address_update.success");
metricsUtils.recordLatency("address_update.controller_latency", 150);
```

---

#### 7. **Tests**

##### `controllers/ClientAddressUpdateControllerTest.java`

```java
class ClientAddressUpdateControllerTest {

    @Mock
    private SfnClient sfnClient;

    @Mock
    private Context context;

    private ClientAddressUpdateController controller;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        controller = new ClientAddressUpdateController(sfnClient);
        when(context.getRequestId()).thenReturn("test-request-id");
    }

    @Test
    void testValidRequest() {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent();
        request.setPathParameters(Map.of("clientId", "123456789"));
        request.setBody("{\"street\":\"123 Main St\",\"city\":\"Montreal\",\"province\":\"QC\",\"postalCode\":\"H1A 1A1\",\"country\":\"CA\"}");

        when(sfnClient.startExecution(any())).thenReturn(
            StartExecutionResponse.builder()
                .executionArn("arn:aws:states:...:execution:test")
                .build()
        );

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(202, response.getStatusCode());
        verify(sfnClient, times(1)).startExecution(any());
    }

    @Test
    void testInvalidClientId() {
        // Arrange
        APIGatewayProxyRequestEvent request = new APIGatewayProxyRequestEvent();
        request.setPathParameters(Map.of("clientId", "INVALID"));

        // Act
        APIGatewayProxyResponseEvent response = controller.handleRequest(request, context);

        // Assert
        assertEquals(400, response.getStatusCode());
        verify(sfnClient, never()).startExecution(any());
    }
}
```

---

#### 8. **Modifier `pom.xml`** (si nouvelles dépendances)

Ajouter dépendances manquantes :

```xml
<dependencies>
    <!-- AWS Lambda Core -->
    <dependency>
        <groupId>com.amazonaws</groupId>
        <artifactId>aws-lambda-java-core</artifactId>
        <version>1.2.2</version>
    </dependency>

    <!-- AWS Lambda Events -->
    <dependency>
        <groupId>com.amazonaws</groupId>
        <artifactId>aws-lambda-java-events</artifactId>
        <version>3.11.0</version>
    </dependency>

    <!-- AWS SDK v2 - Step Functions -->
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>sfn</artifactId>
        <version>2.20.0</version>
    </dependency>

    <!-- AWS SDK v2 - DynamoDB -->
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>dynamodb</artifactId>
        <version>2.20.0</version>
    </dependency>

    <!-- AWS SDK v2 - Secrets Manager -->
    <dependency>
        <groupId>software.amazon.awssdk</groupId>
        <artifactId>secretsmanager</artifactId>
        <version>2.20.0</version>
    </dependency>

    <!-- Lombok -->
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <version>1.18.30</version>
        <scope>provided</scope>
    </dependency>

    <!-- Jackson for JSON -->
    <dependency>
        <groupId>com.fasterxml.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
        <version>2.15.2</version>
    </dependency>

    <!-- JUnit 5 -->
    <dependency>
        <groupId>org.junit.jupiter</groupId>
        <artifactId>junit-jupiter</artifactId>
        <version>5.10.0</version>
        <scope>test</scope>
    </dependency>

    <!-- Mockito -->
    <dependency>
        <groupId>org.mockito</groupId>
        <artifactId>mockito-core</artifactId>
        <version>5.5.0</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```

**Build configuration :**

```xml
<build>
    <plugins>
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
                                <mainClass>com.bnc.mcp.controllers.ClientAddressUpdateController</mainClass>
                            </transformer>
                        </transformers>
                    </configuration>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

---

## Checklist complète d'implémentation

### Phase Infrastructure (mcp-infrastructure) - Déjà fait ✅

- [x] Créer workflow Step Functions JSON
- [x] Déclarer Lambdas dans Terraform
- [x] Créer tables DynamoDB (si besoin)
- [x] Configurer API Gateway routes
- [x] Définir IAM permissions
- [x] `terraform apply` pour créer ressources

---

### Phase Service Métier (mcp-local) - À faire 🚀

#### 1. Création de la structure

- [ ] Créer dossier `controllers/` si inexistant
- [ ] Créer dossier `validators/` si inexistant
- [ ] Créer dossier `utils/` si inexistant

#### 2. Implémentation des Controllers

- [ ] Créer `ClientAddressUpdateController.java`
- [ ] Implémenter validation HTTP (clientId, body)
- [ ] Implémenter enrichissement métadonnées
- [ ] Implémenter logging structuré
- [ ] Implémenter démarrage Step Functions
- [ ] Implémenter retour HTTP 202

#### 3. Implémentation des Handlers (Step Functions)

- [ ] Créer `AddressValidatorHandler.java`
  - [ ] Extraire address depuis input
  - [ ] Appeler service de validation
  - [ ] Retourner résultat structuré

- [ ] Créer `CheckAddressHistoryHandler.java`
  - [ ] Récupérer historique DynamoDB
  - [ ] Calculer score de suspicion
  - [ ] Retourner résultat avec raison

- [ ] Créer `AddressMdmaeClientHandler.java`
  - [ ] Récupérer credentials Secrets Manager
  - [ ] Appeler API MDMAE
  - [ ] Gérer retry et erreurs
  - [ ] Retourner transactionId

#### 4. Création des Models (DTOs)

- [ ] Créer `Address.java`
- [ ] Créer `AddressValidationResult.java`
- [ ] Créer `AddressHistoryCheck.java`

#### 5. Implémentation des Validators

- [ ] Créer `ClientIdValidator.java`
  - [ ] Pattern validation (9 chiffres)
  - [ ] Normalisation

- [ ] Créer `AddressValidator.java`
  - [ ] Validation champs obligatoires
  - [ ] Validation format postal code
  - [ ] Validation province code

#### 6. Implémentation des Services

- [ ] Créer `AddressValidationService.java`
  - [ ] Validation complète
  - [ ] Normalisation adresse
  - [ ] Gestion warnings

- [ ] Créer `AddressHistoryService.java`
  - [ ] Calcul score de suspicion
  - [ ] Détection patterns suspects
  - [ ] Règles métier (changements fréquents, zones à risque)

#### 7. Réutilisation/Modification des Clients

- [ ] Vérifier `DynamoDBClient.java` (réutiliser)
- [ ] Modifier `MdmaeClient.java` si besoin (méthode `updateAddress`)
- [ ] Vérifier `SecretsManagerClient.java` (réutiliser)

#### 8. Création des Utils

- [ ] Créer `LoggingUtils.java`
  - [ ] Méthode `buildLogContext()`
  - [ ] Format JSON structuré

- [ ] Créer `MetricsUtils.java`
  - [ ] Méthode `incrementCounter()`
  - [ ] Méthode `recordLatency()`

- [ ] Créer `AddressUtils.java` (si besoin)
  - [ ] Méthodes helper spécifiques

#### 9. Tests unitaires

- [ ] Créer `ClientAddressUpdateControllerTest.java`
  - [ ] Test requête valide
  - [ ] Test clientId invalide
  - [ ] Test body manquant
  - [ ] Test validation échouée

- [ ] Créer `AddressValidatorHandlerTest.java`
  - [ ] Test adresse valide
  - [ ] Test adresse invalide
  - [ ] Test normalisation

- [ ] Créer `CheckAddressHistoryHandlerTest.java`
  - [ ] Test score faible
  - [ ] Test score élevé
  - [ ] Test historique vide

- [ ] Créer `AddressValidatorTest.java`
  - [ ] Test postal code canadien valide
  - [ ] Test postal code invalide
  - [ ] Test province invalide

- [ ] Créer `AddressValidationServiceTest.java`
  - [ ] Test validation complète
  - [ ] Test normalisation

#### 10. Configuration Maven

- [ ] Vérifier dépendances `pom.xml`
- [ ] Ajouter dépendances manquantes (AWS SDK v2, Jackson, etc.)
- [ ] Configurer `maven-shade-plugin` pour JARs

#### 11. Build local

- [ ] Exécuter `mvn clean package`
- [ ] Vérifier que les JARs sont créés dans `target/`
- [ ] Vérifier taille des JARs (devrait être 1-5 MB)
- [ ] Exécuter `mvn test` et vérifier 100% tests passent

#### 12. Déploiement via GitHub Actions

- [ ] Commit et push vers branche feature
- [ ] Créer Pull Request
- [ ] Code Review et approbation
- [ ] Merger dans `main`
- [ ] Déclencher workflow "Deploy Lambda Code"
  - [ ] Branch: `main`
  - [ ] Environment: `dev`
- [ ] Vérifier logs GitHub Actions
- [ ] Vérifier JARs uploadés sur S3
- [ ] Vérifier Lambdas mises à jour (CodeSha256 changed)

#### 13. Vérification post-déploiement

- [ ] Tester endpoint API Gateway
  ```bash
  curl -X PUT https://xyz.execute-api.ca-central-1.amazonaws.com/dev/api/clients/123456789/address \
    -H "Content-Type: application/json" \
    -d '{"street":"123 Main St","city":"Montreal","province":"QC","postalCode":"H1A 1A1","country":"CA"}'
  ```
- [ ] Vérifier exécution Step Functions (AWS Console)
- [ ] Vérifier logs CloudWatch (toutes Lambdas)
- [ ] Vérifier données DynamoDB (historique sauvegardé)
- [ ] Vérifier métriques CloudWatch (invocations, erreurs, latence)

---

## Exemple concret : Workflow "Client Address Update"

### Récapitulatif des fichiers créés

#### mcp-infrastructure (Déjà fait)

```
modules/step_functions/state_machines/client-address-update.json  (400 lignes)
modules/lambda/variables.tf                                       (modifié)
modules/api_gateway/main.tf                                       (modifié)
environments/dev/main.tf                                          (modifié)
```

#### mcp-local (À faire)

```
controllers/ClientAddressUpdateController.java           (250 lignes)

handlers/AddressValidatorHandler.java                    (100 lignes)
handlers/CheckAddressHistoryHandler.java                 (120 lignes)
handlers/AddressMdmaeClientHandler.java                  (130 lignes)

models/Address.java                                      (30 lignes)
models/AddressValidationResult.java                      (25 lignes)
models/AddressHistoryCheck.java                          (30 lignes)

validators/ClientIdValidator.java                        (40 lignes)
validators/AddressValidator.java                         (80 lignes)

services/AddressValidationService.java                   (150 lignes)
services/AddressHistoryService.java                      (120 lignes)

utils/LoggingUtils.java                                  (40 lignes)
utils/MetricsUtils.java                                  (60 lignes)

tests/controllers/ClientAddressUpdateControllerTest.java (150 lignes)
tests/handlers/AddressValidatorHandlerTest.java          (100 lignes)
tests/handlers/CheckAddressHistoryHandlerTest.java       (100 lignes)
tests/validators/AddressValidatorTest.java               (80 lignes)
tests/services/AddressValidationServiceTest.java         (100 lignes)

pom.xml                                                  (modifié)

TOTAL : ~1,600 lignes de code Java (production + tests)
```

---

## Ordre de déploiement

### Séquence complète

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. DÉVELOPPEMENT INFRASTRUCTURE (mcp-infrastructure)            │
├─────────────────────────────────────────────────────────────────┤
│ • Créer workflow Step Functions JSON                            │
│ • Déclarer Lambdas dans Terraform                               │
│ • Créer tables DynamoDB (si besoin)                             │
│ • Configurer API Gateway                                        │
│ • Commit + Push                                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. DÉPLOIEMENT INFRASTRUCTURE                                   │
├─────────────────────────────────────────────────────────────────┤
│ GitHub Actions → Terraform Deploy                               │
│ • Branch: main                                                  │
│ • Environment: dev                                              │
│ • Action: plan → vérifier                                       │
│ • Action: apply → déployer                                      │
│                                                                 │
│ Résultat : Lambdas créées (avec code placeholder vide)         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. DÉVELOPPEMENT SERVICE MÉTIER (mcp-local)                     │
├─────────────────────────────────────────────────────────────────┤
│ • Créer Controllers, Handlers, Models, Validators, Services    │
│ • Implémenter logique métier                                   │
│ • Écrire tests unitaires                                       │
│ • Build local : mvn clean package                              │
│ • Tests locaux : mvn test                                      │
│ • Commit + Push                                                │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. DÉPLOIEMENT SERVICE MÉTIER                                   │
├─────────────────────────────────────────────────────────────────┤
│ GitHub Actions → Deploy Lambda Code                             │
│ • Branch: main                                                  │
│ • Environment: dev                                              │
│                                                                 │
│ Workflow :                                                      │
│   1. Build JARs (mvn package)                                  │
│   2. Upload to S3 (bnc-mcp-lambda-artifacts/dev/)              │
│   3. Update Lambda functions (aws lambda update-function-code) │
│   4. Verify deployments                                        │
│                                                                 │
│ Résultat : Lambdas mises à jour avec code Java fonctionnel     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. TESTS & VALIDATION                                           │
├─────────────────────────────────────────────────────────────────┤
│ • Test API Gateway endpoint (Postman/curl)                      │
│ • Vérifier exécution Step Functions (AWS Console)              │
│ • Vérifier logs CloudWatch (toutes Lambdas)                    │
│ • Vérifier données DynamoDB                                    │
│ • Tests d'intégration E2E                                      │
│                                                                 │
│ ✅ Workflow fonctionnel sur DEV                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 6. DÉPLOIEMENT PRODUCTION (optionnel)                           │
├─────────────────────────────────────────────────────────────────┤
│ Même processus mais avec Environment: prod                      │
│ • Terraform apply (env=prod)                                   │
│ • Deploy Lambda Code (env=prod)                                │
│ • Tests smoke PROD                                             │
│                                                                 │
│ ✅ Workflow fonctionnel sur PROD                                │
└─────────────────────────────────────────────────────────────────┘
```

---

### Timeline estimée

| Phase | Durée estimée | Responsable |
|-------|--------------|-------------|
| **1. Développement Infrastructure** | 2-4 heures | DevOps/Infra |
| **2. Déploiement Infrastructure** | 15-20 min | GitHub Actions |
| **3. Développement Service Métier** | 1-2 jours | Développeur Backend |
| **4. Déploiement Service Métier** | 5-10 min | GitHub Actions |
| **5. Tests & Validation** | 2-4 heures | QA/Développeur |
| **TOTAL** | **2-3 jours** | |

---

### Points de vérification

#### Après Phase 2 (Infrastructure déployée)

```bash
# Vérifier que les Lambdas existent (même avec code vide)
aws lambda list-functions --query "Functions[?contains(FunctionName, 'dev-mcp-address')]" --output table

# Vérifier Step Functions créé
aws stepfunctions list-state-machines --query "stateMachines[?name=='dev-client-address-update']"

# Vérifier API Gateway
aws apigateway get-rest-apis --query "items[?name=='dev-mcp-api']"
```

#### Après Phase 4 (Service déployé)

```bash
# Vérifier que les JARs ont été uploadés
aws s3 ls s3://bnc-mcp-lambda-artifacts/dev/

# Vérifier CodeSha256 des Lambdas (devrait avoir changé)
aws lambda get-function --function-name dev-mcp-address-validator \
  --query 'Configuration.[LastModified,CodeSha256]'

# Test endpoint
curl -X PUT https://xyz.execute-api.ca-central-1.amazonaws.com/dev/api/clients/123/address \
  -H "Content-Type: application/json" \
  -d '{"street":"123 Main","city":"Montreal","province":"QC","postalCode":"H1A 1A1","country":"CA"}'
```

---

## Résumé exécutif

### Ce qui a été fait (Infrastructure)

✅ **Orchestration définie** : Step Functions workflow JSON (QUOI, QUAND)
✅ **Ressources créées** : Lambdas, DynamoDB, API Gateway, IAM
✅ **Déployé sur AWS** : Infrastructure prête, Lambdas vides

### Ce qu'il faut faire (Service Métier)

🚀 **Logique métier** : Implémenter le code Java (COMMENT)
🚀 **Controllers** : Lambda Controller pour API Gateway
🚀 **Handlers** : Lambdas pour chaque étape Step Functions
🚀 **Validators** : Validation des données
🚀 **Services** : Logique métier (calculs, transformations)
🚀 **Tests** : Tests unitaires complets
🚀 **Build & Deploy** : GitHub Actions automatique

### Ordre impératif

```
1. Infrastructure (Terraform) → Crée les ressources
2. Service Métier (Java) → Implémente la logique
3. GitHub Actions → Déploie le code
4. Tests → Valide le workflow
```

**⚠️ IMPORTANT** : Ne jamais inverser l'ordre. Le code a besoin que l'infrastructure existe d'abord.

---

**Dernière mise à jour** : 2026-09-24
**Auteur** : Claude Code
**Version** : 1.0