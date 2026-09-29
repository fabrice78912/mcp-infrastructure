# Lambda Function Packages

This directory contains the deployment packages (JAR files) for all Lambda functions.

## Building Lambda JARs

Use the build script from the project root:

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
./scripts/build-lambda-packages.sh
```

This script will:
1. Build each service from `/Users/fabricefoko/Downloads/mcp-local`
2. Copy the JAR files to the appropriate function directories
3. Rename them to `function.jar`

## Function Directories

Each directory should contain a `function.jar` file:

- **client-profile-reader/** - Reads client profile from DynamoDB
- **name-validator/** - Validates client name changes
- **mdmae-client/** - Calls MDMAE API for client updates
- **fcc-sender/** - Sends requests to FCC (IBM MQ)
- **human-review-handler/** - Handles manual review cases
- **mq-poller/** - Polls IBM MQ for FCC responses
- **fcc-response-processor/** - Processes FCC responses from SQS

## Manual Build

If you prefer to build manually:

```bash
cd /Users/fabricefoko/Downloads/mcp-local/mcp-api
./gradlew clean build -x test

# Copy the JAR
cp build/libs/mcp-api-*.jar \
  /Users/fabricefoko/Documents/mcp-infrastructure/modules/lambda/functions/client-profile-reader/function.jar
```

Repeat for each service.

## Spring Boot Lambda Handler

Ensure each Spring Boot application uses the AWS Lambda handler:

```java
// Handler class should implement RequestHandler or use SpringBootRequestHandler
public class LambdaHandler implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {
    // ...
}
```

## Environment Variables

Lambda functions receive environment variables configured in Terraform:
- `DYNAMODB_TABLE_NAME`
- `SQS_QUEUE_URL`
- `MSK_BOOTSTRAP_SERVERS`
- `SECRETS_ARN_*` (for IBM MQ, MDMAE credentials)
- etc.

See `environments/dev/main.tf` for the complete list.