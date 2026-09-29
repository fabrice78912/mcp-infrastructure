{
  "Comment": "Client Phone Update Workflow - Validates phone, checks history, sends OTP, updates MDMAE and systems",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${client_profile_reader_arn}",
        "Payload": {
          "clientId.$": "$.clientId"
        }
      },
      "ResultPath": "$.clientProfile",
      "ResultSelector": {
        "clientId.$": "$.Payload.clientId",
        "currentPhone.$": "$.Payload.currentPhone",
        "newPhone.$": "$.Payload.newPhone",
        "country.$": "$.Payload.country",
        "status.$": "$.Payload.status"
      },
      "Next": "ParallelValidations",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "ParallelValidations": {
      "Type": "Parallel",
      "ResultPath": "$.validations",
      "Next": "EvaluateFraudRisk",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ],
      "Branches": [
        {
          "StartAt": "ValidatePhoneFormat",
          "States": {
            "ValidatePhoneFormat": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${phone_validator_arn}",
                "Payload": {
                  "phoneNumber.$": "$.clientProfile.newPhone",
                  "country.$": "$.clientProfile.country"
                }
              },
              "ResultSelector": {
                "isValid.$": "$.Payload.isValid",
                "phoneType.$": "$.Payload.phoneType",
                "carrier.$": "$.Payload.carrier",
                "message.$": "$.Payload.message"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "CheckPhoneHistory",
          "States": {
            "CheckPhoneHistory": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${check_phone_history_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.clientProfile.newPhone"
                }
              },
              "ResultSelector": {
                "changeCount.$": "$.Payload.changeCount",
                "lastChangeDate.$": "$.Payload.lastChangeDate",
                "isSuspicious.$": "$.Payload.isSuspicious",
                "reason.$": "$.Payload.reason"
              },
              "End": true
            }
          }
        }
      ]
    },
    "EvaluateFraudRisk": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.validations[0].isValid",
          "BooleanEquals": false,
          "Next": "PhoneValidationFailed"
        },
        {
          "And": [
            {
              "Variable": "$.validations[1].isSuspicious",
              "BooleanEquals": true
            },
            {
              "Variable": "$.validations[1].changeCount",
              "NumericGreaterThanEquals": 3
            }
          ],
          "Next": "SendToFraudReview"
        }
      ],
      "Default": "RecordPhoneHistory"
    },
    "SendToFraudReview": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage",
      "Parameters": {
        "QueueUrl": "${fraud_review_queue_url}",
        "MessageBody": {
          "clientId.$": "$.clientProfile.clientId",
          "currentPhone.$": "$.clientProfile.currentPhone",
          "newPhone.$": "$.clientProfile.newPhone",
          "changeCount.$": "$.validations[1].changeCount",
          "reason.$": "$.validations[1].reason",
          "taskToken.$": "$$.Task.Token"
        }
      },
      "ResultPath": "$.fraudReview",
      "Next": "WaitForHumanApproval",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "WaitForHumanApproval": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters": {
        "FunctionName": "${human_approval_handler_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "taskToken.$": "$$.Task.Token"
        }
      },
      "ResultPath": "$.approval",
      "Next": "CheckApprovalResult",
      "TimeoutSeconds": 86400,
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "ResultPath": "$.error",
          "Next": "ApprovalTimeout"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "CheckApprovalResult": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.approval.Payload.approved",
          "BooleanEquals": false,
          "Next": "ApprovalRejected"
        }
      ],
      "Default": "RecordPhoneHistory"
    },
    "RecordPhoneHistory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Parameters": {
        "TableName": "${phone_history_table_name}",
        "Item": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          },
          "timestamp": {
            "N.$": "$$.State.EnteredTime"
          },
          "oldPhone": {
            "S.$": "$.clientProfile.currentPhone"
          },
          "newPhone": {
            "S.$": "$.clientProfile.newPhone"
          },
          "country": {
            "S.$": "$.clientProfile.country"
          },
          "changeCount": {
            "N.$": "States.Format('{}', $.validations[1].changeCount)"
          },
          "expiresAt": {
            "N.$": "States.Format('{}', States.MathAdd($$.State.EnteredTime, 15552000))"
          }
        }
      },
      "ResultPath": "$.historyRecord",
      "Next": "SendOTPSMS",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "SendOTPSMS": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${send_otp_sms_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "phoneNumber.$": "$.clientProfile.newPhone"
        }
      },
      "ResultPath": "$.otp",
      "ResultSelector": {
        "otpId.$": "$.Payload.otpId",
        "expiresAt.$": "$.Payload.expiresAt",
        "sent.$": "$.Payload.sent"
      },
      "Next": "WaitForOTP",
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
    "WaitForOTP": {
      "Type": "Wait",
      "Seconds": 60,
      "Next": "CheckOTPStatus"
    },
    "CheckOTPStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${check_otp_status_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "otpId.$": "$.otp.otpId"
        }
      },
      "ResultPath": "$.otpStatus",
      "ResultSelector": {
        "status.$": "$.Payload.status",
        "validated.$": "$.Payload.validated",
        "attempts.$": "$.Payload.attempts"
      },
      "Next": "EvaluateOTP",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },
    "EvaluateOTP": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.otpStatus.status",
          "StringEquals": "VALIDATED",
          "Next": "UpdateMDMAE"
        },
        {
          "Variable": "$.otpStatus.status",
          "StringEquals": "EXPIRED",
          "Next": "OTPExpired"
        },
        {
          "And": [
            {
              "Variable": "$.otpStatus.status",
              "StringEquals": "PENDING"
            },
            {
              "Variable": "$.otpStatus.attempts",
              "NumericLessThan": 3
            }
          ],
          "Next": "WaitForOTP"
        }
      ],
      "Default": "OTPMaxAttemptsReached"
    },
    "UpdateMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${phone_mdmae_client_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "newPhone.$": "$.clientProfile.newPhone",
          "country.$": "$.clientProfile.country"
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
          "Next": "CompensateMDMAEFailure"
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
      "Default": "ParallelSystemUpdates"
    },
    "ParallelSystemUpdates": {
      "Type": "Parallel",
      "ResultPath": "$.systemUpdates",
      "Next": "UpdateClientProfileSuccess",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "PartialSystemUpdateFailure"
        }
      ],
      "Branches": [
        {
          "StartAt": "SendToFCC",
          "States": {
            "SendToFCC": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${fcc_sender_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.clientProfile.newPhone",
                  "mdmaeId.$": "$.mdmae.mdmaeId"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success",
                "messageId.$": "$.Payload.messageId"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 3,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "UpdateCRM",
          "States": {
            "UpdateCRM": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${crm_updater_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.clientProfile.newPhone"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "UpdateNotificationService",
          "States": {
            "UpdateNotificationService": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${notification_updater_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.clientProfile.newPhone"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
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
        "UpdateExpression": "SET #phone = :phone, #status = :status, #updatedAt = :updatedAt, #mdmaeId = :mdmaeId, #fccMessageId = :fccMessageId",
        "ExpressionAttributeNames": {
          "#phone": "phoneNumber",
          "#status": "status",
          "#updatedAt": "updatedAt",
          "#mdmaeId": "mdmaeId",
          "#fccMessageId": "fccMessageId"
        },
        "ExpressionAttributeValues": {
          ":phone": {
            "S.$": "$.clientProfile.newPhone"
          },
          ":status": {
            "S": "PHONE_UPDATED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":mdmaeId": {
            "S.$": "$.mdmae.mdmaeId"
          },
          ":fccMessageId": {
            "S.$": "$.systemUpdates[0].messageId"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowSuccess"
    },
    "PhoneValidationFailed": {
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
            "S": "PHONE_VALIDATION_FAILED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":errorMessage": {
            "S.$": "$.validations[0].message"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowValidationFailed"
    },
    "ApprovalRejected": {
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
            "S": "APPROVAL_REJECTED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowApprovalRejected"
    },
    "ApprovalTimeout": {
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
            "S": "APPROVAL_TIMEOUT"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowApprovalTimeout"
    },
    "OTPExpired": {
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
            "S": "OTP_EXPIRED"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowOTPExpired"
    },
    "OTPMaxAttemptsReached": {
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
            "S": "OTP_MAX_ATTEMPTS"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowOTPFailed"
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
    "CompensateMDMAEFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${phone_history_table_name}",
        "Key": {
          "clientId": {
            "S.$": "$.clientProfile.clientId"
          },
          "timestamp": {
            "N.$": "$.historyRecord.timestamp"
          }
        },
        "UpdateExpression": "SET #compensated = :compensated",
        "ExpressionAttributeNames": {
          "#compensated": "compensated"
        },
        "ExpressionAttributeValues": {
          ":compensated": {
            "BOOL": true
          }
        }
      },
      "ResultPath": "$.compensation",
      "Next": "MDAEFailed"
    },
    "PartialSystemUpdateFailure": {
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
            "S": "PARTIAL_UPDATE_FAILURE"
          },
          ":updatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":errorMessage": {
            "S": "MDMAE updated but some systems failed"
          }
        }
      },
      "ResultPath": "$.dbUpdate",
      "Next": "WorkflowPartialFailure"
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
    "WorkflowValidationFailed": {
      "Type": "Fail",
      "Error": "PhoneValidationFailed",
      "Cause": "Phone number validation failed"
    },
    "WorkflowApprovalRejected": {
      "Type": "Fail",
      "Error": "ApprovalRejected",
      "Cause": "Human approval was rejected"
    },
    "WorkflowApprovalTimeout": {
      "Type": "Fail",
      "Error": "ApprovalTimeout",
      "Cause": "Human approval timed out after 24 hours"
    },
    "WorkflowOTPExpired": {
      "Type": "Fail",
      "Error": "OTPExpired",
      "Cause": "OTP code expired"
    },
    "WorkflowOTPFailed": {
      "Type": "Fail",
      "Error": "OTPMaxAttempts",
      "Cause": "Maximum OTP validation attempts reached"
    },
    "WorkflowMDAEFailed": {
      "Type": "Fail",
      "Error": "MDAEFailed",
      "Cause": "MDMAE API call failed"
    },
    "WorkflowPartialFailure": {
      "Type": "Fail",
      "Error": "PartialFailure",
      "Cause": "MDMAE succeeded but downstream systems failed"
    },
    "WorkflowFailed": {
      "Type": "Fail",
      "Error": "WorkflowError",
      "Cause": "An error occurred during workflow execution"
    }
  }
}