{
  "Comment": "Client Name Update Workflow - Reads profile, validates, calls MDMAE, sends to FCC",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 300,
      "Parameters": {
        "FunctionName": "${client_profile_reader_arn}",
        "Payload": {
          "clientId.$": "$.clientId"
        }
      },
      "ResultPath": "$.clientProfile",
      "ResultSelector": {
        "clientId.$": "$.Payload.clientId",
        "currentName.$": "$.Payload.currentName",
        "newName.$": "$.Payload.newName",
        "status.$": "$.Payload.status"
      },
      "Next": "ValidateNameChange",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "ValidateNameChange": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 300,
      "Parameters": {
        "FunctionName": "${name_validator_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "currentName.$": "$.clientProfile.currentName",
          "newName.$": "$.clientProfile.newName"
        }
      },
      "ResultPath": "$.validation",
      "ResultSelector": {
        "isValid.$": "$.Payload.isValid",
        "requiresHumanReview.$": "$.Payload.requiresHumanReview",
        "validationMessage.$": "$.Payload.message"
      },
      "Next": "CheckValidation",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "CheckValidation": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.validation.requiresHumanReview",
          "BooleanEquals": true,
          "Next": "HumanReviewRequired"
        },
        {
          "Variable": "$.validation.isValid",
          "BooleanEquals": false,
          "Next": "ValidationFailed"
        }
      ],
      "Default": "CallMDMAE"
    },
    "CallMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 300,
      "Parameters": {
        "FunctionName": "${mdmae_client_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "newName.$": "$.clientProfile.newName"
        }
      },
      "ResultPath": "$.mdmae",
      "ResultSelector": {
        "success.$": "$.Payload.success",
        "mdmaeId.$": "$.Payload.mdmaeId",
        "message.$": "$.Payload.message"
      },
      "Next": "CheckMDMAEResult",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "CheckMDMAEResult": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.mdmae.success",
          "BooleanEquals": false,
          "Next": "MDAEFailed"
        }
      ],
      "Default": "SendToFCC"
    },
    "SendToFCC": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 300,
      "Parameters": {
        "FunctionName": "${fcc_sender_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "newName.$": "$.clientProfile.newName",
          "mdmaeId.$": "$.mdmae.mdmaeId"
        }
      },
      "ResultPath": "$.fcc",
      "ResultSelector": {
        "success.$": "$.Payload.success",
        "messageId.$": "$.Payload.messageId",
        "message.$": "$.Payload.message"
      },
      "Next": "UpdateClientProfileSuccess",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "UpdateClientProfileSuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          }
        },
        "UpdateExpression": "SET #status = :status, #updatedAt = :updatedAt, #mdmaeId = :mdmaeId, #fccMessageId = :fccMessageId",
        "ExpressionAttributeNames": {
          "#status": "status",
          "#updatedAt": "updatedAt",
          "#mdmaeId": "mdmaeId",
          "#fccMessageId": "fccMessageId"
        },
        "ExpressionAttributeValues": {
          ":status": {
            "S": "FCC_SENT"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":mdmaeId": {
            "S.$": "$.mdmae.mdmaeId"
          },
          ":fccMessageId": {
            "S.$": "$.fcc.messageId"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowSuccess"
    },
    "HumanReviewRequired": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 300,
      "Parameters": {
        "FunctionName": "${human_review_handler_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "currentName.$": "$.clientProfile.currentName",
          "newName.$": "$.clientProfile.newName",
          "reason.$": "$.validation.validationMessage"
        }
      },
      "ResultPath": "$.humanReview",
      "Next": "UpdateClientProfileHumanReview"
    },
    "UpdateClientProfileHumanReview": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          }
        },
        "UpdateExpression": "SET #status = :status, #updatedAt = :updatedAt",
        "ExpressionAttributeNames": {
          "#status": "status",
          "#updatedAt": "updatedAt"
        },
        "ExpressionAttributeValues": {
          ":status": {
            "S": "HUMAN_REVIEW"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowHumanReview"
    },
    "ValidationFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          }
        },
        "UpdateExpression": "SET #status = :status, #updatedAt = :updatedAt, #errorMessage = :errorMessage",
        "ExpressionAttributeNames": {
          "#status": "status",
          "#updatedAt": "updatedAt",
          "#errorMessage": "errorMessage"
        },
        "ExpressionAttributeValues": {
          ":status": {
            "S": "VALIDATION_FAILED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":errorMessage": {
            "S.$": "$.validation.validationMessage"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowValidationFailed"
    },
    "MDAEFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          }
        },
        "UpdateExpression": "SET #status = :status, #updatedAt = :updatedAt, #errorMessage = :errorMessage",
        "ExpressionAttributeNames": {
          "#status": "status",
          "#updatedAt": "updatedAt",
          "#errorMessage": "errorMessage"
        },
        "ExpressionAttributeValues": {
          ":status": {
            "S": "MDMAE_FAILED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":errorMessage": {
            "S.$": "$.mdmae.message"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowMDAEFailed"
    },
    "HandleError": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          }
        },
        "UpdateExpression": "SET #status = :status, #updatedAt = :updatedAt, #errorMessage = :errorMessage",
        "ExpressionAttributeNames": {
          "#status": "status",
          "#updatedAt": "updatedAt",
          "#errorMessage": "errorMessage"
        },
        "ExpressionAttributeValues": {
          ":status": {
            "S": "ERROR"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":errorMessage": {
            "S.$": "$.error.Cause"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowFailed"
    },
    "WorkflowSuccess": {
      "Type": "Succeed"
    },
    "WorkflowHumanReview": {
      "Type": "Succeed"
    },
    "WorkflowValidationFailed": {
      "Type": "Fail",
      "Error": "ValidationFailed",
      "Cause": "Client name validation failed"
    },
    "WorkflowMDAEFailed": {
      "Type": "Fail",
      "Error": "MDAEFailed",
      "Cause": "MDMAE API call failed"
    },
    "WorkflowFailed": {
      "Type": "Fail",
      "Error": "WorkflowError",
      "Cause": "An error occurred during workflow execution"
    }
  }
}