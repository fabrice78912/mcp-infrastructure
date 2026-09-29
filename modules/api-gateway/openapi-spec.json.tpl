{
  "openapi": "3.0.1",
  "info": {
    "title": "MCP Client Name Update API",
    "description": "API pour la mise à jour des noms de clients MCP. Cette API permet de modifier le nom de famille d'un client et déclenche automatiquement un workflow de validation et de propagation.",
    "version": "1.0.0",
    "contact": {
      "name": "Équipe MCP",
      "email": "support@example.com"
    }
  },
  "servers": [
    {
      "url": "https://${api_id}.execute-api.${region}.amazonaws.com/${environment}",
      "description": "Environnement ${environment}"
    }
  ],
  "tags": [
    {
      "name": "Clients",
      "description": "Opérations sur les profils clients"
    },
    {
      "name": "Documentation",
      "description": "Documentation de l'API"
    }
  ],
  "paths": {
    "/api/clients/{clientId}/nom": {
      "put": {
        "tags": ["Clients"],
        "summary": "Mise à jour du nom de famille d'un client",
        "description": "Met à jour le nom de famille d'un client existant. Cette opération déclenche un workflow Step Functions qui:\n\n1. Valide l'existence du client\n2. Recherche les doublons potentiels (via MDMAE)\n3. Met à jour le profil dans DynamoDB\n4. Publie un événement Kafka\n5. Propage vers le FCC (si applicable)",
        "operationId": "updateClientLastName",
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
          "description": "Nouvelles informations du nom de famille",
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/UpdateNameRequest"
              },
              "examples": {
                "mariage": {
                  "summary": "Changement de nom suite à un mariage",
                  "value": {
                    "newLastName": "Leblanc",
                    "reason": "MARIAGE"
                  }
                },
                "divorce": {
                  "summary": "Changement de nom suite à un divorce",
                  "value": {
                    "newLastName": "Tremblay",
                    "reason": "DIVORCE"
                  }
                },
                "correction": {
                  "summary": "Correction d'une erreur",
                  "value": {
                    "newLastName": "Gagnon",
                    "reason": "CORRECTION"
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
                  "$ref": "#/components/schemas/UpdateNameResponse"
                },
                "example": {
                  "message": "Client name update initiated",
                  "executionArn": "arn:aws:states:${region}:123456789012:execution:${environment}-mcp-client_name_update:abc123-def456"
                }
              }
            }
          },
          "400": {
            "description": "Requête invalide (paramètres manquants ou incorrects)",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/ErrorResponse"
                },
                "example": {
                  "error": "BadRequest",
                  "message": "Le champ 'newLastName' est requis"
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
          },
          "500": {
            "description": "Erreur interne du serveur",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/ErrorResponse"
                },
                "example": {
                  "error": "InternalServerError",
                  "message": "Une erreur inattendue s'est produite"
                }
              }
            }
          }
        }
      }
    },
    "/swagger.json": {
      "get": {
        "tags": ["Documentation"],
        "summary": "Récupère la spécification OpenAPI",
        "description": "Retourne la spécification OpenAPI complète de l'API au format JSON",
        "operationId": "getOpenAPISpec",
        "responses": {
          "200": {
            "description": "Spécification OpenAPI",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    },
    "/docs": {
      "get": {
        "tags": ["Documentation"],
        "summary": "Interface Swagger UI",
        "description": "Affiche l'interface interactive Swagger UI pour tester l'API",
        "operationId": "getSwaggerUI",
        "responses": {
          "200": {
            "description": "Page HTML Swagger UI",
            "content": {
              "text/html": {
                "schema": {
                  "type": "string"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "UpdateNameRequest": {
        "type": "object",
        "required": ["newLastName", "reason"],
        "properties": {
          "newLastName": {
            "type": "string",
            "description": "Nouveau nom de famille du client",
            "minLength": 1,
            "maxLength": 100,
            "example": "Leblanc"
          },
          "reason": {
            "type": "string",
            "description": "Raison du changement de nom",
            "enum": [
              "MARIAGE",
              "DIVORCE",
              "CORRECTION",
              "AUTRE"
            ],
            "example": "MARIAGE"
          }
        }
      },
      "UpdateNameResponse": {
        "type": "object",
        "properties": {
          "message": {
            "type": "string",
            "description": "Message de confirmation",
            "example": "Client name update initiated"
          },
          "executionArn": {
            "type": "string",
            "description": "ARN de l'exécution Step Functions démarrée",
            "example": "arn:aws:states:ca-central-1:123456789012:execution:dev-mcp-client_name_update:abc123-def456"
          }
        }
      },
      "ErrorResponse": {
        "type": "object",
        "properties": {
          "error": {
            "type": "string",
            "description": "Type d'erreur",
            "example": "BadRequest"
          },
          "message": {
            "type": "string",
            "description": "Description détaillée de l'erreur",
            "example": "Le champ 'newLastName' est requis"
          }
        }
      }
    }
  }
}