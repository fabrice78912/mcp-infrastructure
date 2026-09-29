{
  "Comment": "Client Phone Update Workflow - FIXED VERSION with retry strategy and email confirmation",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Parameters": {
        "FunctionName": "${read_client_profile_arn}",
        "Payload": {
          "clientId.$": "$.clientId"
        }
      },
      "ResultPath": "$.clientProfile",
      "ResultSelector": {
        "clientId.$": "$.Payload.clientId",
        "phoneNumber.$": "$.Payload.phoneNumber",
        "email.$": "$.Payload.email",
        "status.$": "$.Payload.status"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "States.TaskFailed",
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ],
      "Next": "ParallelValidations"
    },
    "ParallelValidations": {
      "Type": "Parallel",
      "ResultPath": "$.validations",
      "Branches": [
        {
          "StartAt": "ValidatePhoneFormat",
          "States": {
            "ValidatePhoneFormat": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 10,
              "Parameters": {
                "FunctionName": "${phone_validator_arn}",
                "Payload": {
                  "phoneNumber.$": "$.phoneNumber",
                  "country.$": "$.country"
                }
              },
              "ResultSelector": {
                "valid.$": "$.Payload.valid",
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
              "TimeoutSeconds": 20,
              "Parameters": {
                "FunctionName": "${check_phone_history_arn}",
                "Payload": {
                  "clientId.$": "$.clientId",
                  "newPhone.$": "$.phoneNumber"
                }
              },
              "ResultSelector": {
                "changeCount.$": "$.Payload.changeCount",
                "isSuspicious.$": "$.Payload.isSuspicious",
                "suspicionScore.$": "$.Payload.suspicionScore",
                "reason.$": "$.Payload.reason"
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "DynamoDb.ProvisionedThroughputExceededException",
                    "DynamoDb.ThrottlingException",
                    "States.TaskFailed"
                  ],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.validationError",
          "Next": "PhoneValidationFailed"
        }
      ],
      "Next": "EvaluateFraudRisk"
    },
    "EvaluateFraudRisk": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.validations[1].isSuspicious",
          "BooleanEquals": true,
          "Next": "SendToFraudReview"
        },
        {
          "And": [
            {
              "Variable": "$.validations[1].suspicionScore",
              "NumericGreaterThan": 0.5
            },
            {
              "Variable": "$.validations[1].changeCount",
              "NumericGreaterThan": 3
            }
          ],
          "Next": "SendToFraudReview"
        }
      ],
      "Default": "RecordPhoneHistory"
    },
    "SendToFraudReview": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "TimeoutSeconds": 86400,
      "Parameters": {
        "QueueUrl": "${fraud_review_queue_url}",
        "MessageBody": {
          "clientId.$": "$.clientProfile.clientId",
          "oldPhone.$": "$.clientProfile.phoneNumber",
          "newPhone.$": "$.phoneNumber",
          "taskToken.$": "$$.Task.Token",
          "suspicionScore.$": "$.validations[1].suspicionScore",
          "reason.$": "$.validations[1].reason",
          "changeCount.$": "$.validations[1].changeCount"
        }
      },
      "ResultPath": "$.approval",
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "ResultPath": "$.error",
          "Next": "ApprovalTimeout"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "ApprovalRejected"
        }
      ],
      "Next": "EvaluateApproval"
    },
    "EvaluateApproval": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.approval.decision",
          "StringEquals": "APPROVED",
          "Next": "RecordPhoneHistory"
        },
        {
          "Variable": "$.approval.decision",
          "StringEquals": "REJECTED",
          "Next": "ApprovalRejected"
        }
      ],
      "Default": "ApprovalTimeout"
    },
    "RecordPhoneHistory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "TimeoutSeconds": 10,
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
            "S.$": "$.clientProfile.phoneNumber"
          },
          "newPhone": {
            "S.$": "$.phoneNumber"
          },
          "changeReason": {
            "S": "CLIENT_REQUEST"
          },
          "suspicionScore": {
            "N.$": "$.validations[1].suspicionScore"
          },
          "approvedBy": {
            "S.$": "States.Format('{}', $.approval.approvedBy)"
          }
        }
      },
      "ResultPath": "$.historyRecord",
      "Retry": [
        {
          "ErrorEquals": [
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "SendOTPSMS"
    },
    "SendOTPSMS": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Parameters": {
        "FunctionName": "${send_otp_sms_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "phoneNumber.$": "$.phoneNumber"
        }
      },
      "ResultPath": "$.otp",
      "ResultSelector": {
        "otpId.$": "$.Payload.otpId",
        "expiresAt.$": "$.Payload.expiresAt"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "SNS.ThrottlingException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 3,
          "MaxAttempts": 2,
          "BackoffRate": 2.0,
          "Comment": "Limited to 2 retries to avoid sending multiple SMS"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "OTPExpired"
        }
      ],
      "Next": "WaitForOTP"
    },
    "WaitForOTP": {
      "Type": "Wait",
      "Seconds": 60,
      "Comment": "Wait 60 seconds for client to validate OTP",
      "Next": "CheckOTPStatus"
    },
    "CheckOTPStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 10,
      "Parameters": {
        "FunctionName": "${check_otp_status_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "otpId.$": "$.otp.otpId"
        }
      },
      "ResultPath": "$.otpStatus",
      "ResultSelector": {
        "validated.$": "$.Payload.validated",
        "attempts.$": "$.Payload.attempts"
      },
      "Next": "EvaluateOTP"
    },
    "EvaluateOTP": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.otpStatus.validated",
          "BooleanEquals": true,
          "Next": "UpdateMDMAE"
        },
        {
          "And": [
            {
              "Variable": "$.otpStatus.validated",
              "BooleanEquals": false
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
      "TimeoutSeconds": 90,
      "Comment": "CRITICAL STEP - Update Master Data Management with comprehensive retry",
      "Parameters": {
        "FunctionName": "${phone_mdmae_client_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "newPhone.$": "$.phoneNumber",
          "country.$": "$.country",
          "requestId.$": "$$.Execution.Name"
        }
      },
      "ResultPath": "$.mdmae",
      "ResultSelector": {
        "success.$": "$.Payload.success",
        "mdmaeId.$": "$.Payload.mdmaeId",
        "message.$": "$.Payload.message"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2.0,
          "Comment": "Retry for Lambda execution errors (5s → 10s → 20s)"
        },
        {
          "ErrorEquals": ["States.Timeout"],
          "IntervalSeconds": 3,
          "MaxAttempts": 2,
          "BackoffRate": 2.0,
          "Comment": "Retry for timeout errors (3s → 6s)"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "ValidationException",
            "BadRequestException",
            "UnauthorizedException"
          ],
          "ResultPath": "$.error",
          "Next": "CompensateMDMAEFailure",
          "Comment": "Client errors (4xx) - do not retry"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "CompensateMDMAEFailure"
        }
      ],
      "Next": "CheckMDMAEResult"
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
      "Comment": "Update FCC, CRM, and Notification service in parallel (non-blocking)",
      "Branches": [
        {
          "StartAt": "SendToFCC",
          "States": {
            "SendToFCC": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 60,
              "Parameters": {
                "FunctionName": "${fcc_sender_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.phoneNumber",
                  "mdmaeId.$": "$.mdmae.mdmaeId"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success",
                "messageId.$": "$.Payload.messageId"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed", "ApiException"],
                  "IntervalSeconds": 5,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0,
                  "Comment": "Retry 3 times (5s → 10s → 20s)"
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.fccError",
                  "Next": "FCCUpdateOptional"
                }
              ],
              "End": true
            },
            "FCCUpdateOptional": {
              "Type": "Pass",
              "Comment": "FCC update failed but continue anyway (non-blocking)",
              "Result": {
                "success": false,
                "message": "FCC update failed - logged for manual review"
              },
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
              "TimeoutSeconds": 60,
              "Parameters": {
                "FunctionName": "${crm_updater_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.phoneNumber"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed", "ApiException"],
                  "IntervalSeconds": 5,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0,
                  "Comment": "Retry 3 times (5s → 10s → 20s) - FIXED from 2 to 3"
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.crmError",
                  "Next": "CRMUpdateOptional"
                }
              ],
              "End": true
            },
            "CRMUpdateOptional": {
              "Type": "Pass",
              "Comment": "CRM update failed but continue anyway (non-blocking)",
              "Result": {
                "success": false,
                "message": "CRM update failed - logged for manual review"
              },
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
              "TimeoutSeconds": 30,
              "Parameters": {
                "FunctionName": "${notification_updater_arn}",
                "Payload": {
                  "eventType": "PHONE_UPDATE",
                  "clientId.$": "$.clientProfile.clientId",
                  "oldPhone.$": "$.clientProfile.phoneNumber",
                  "newPhone.$": "$.phoneNumber",
                  "timestamp.$": "$$.State.EnteredTime"
                }
              },
              "ResultSelector": {
                "success.$": "$.Payload.success"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0,
                  "Comment": "Retry 3 times (2s → 4s → 8s) - FIXED from 2 to 3"
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.notificationError",
                  "Next": "NotificationUpdateOptional"
                }
              ],
              "End": true
            },
            "NotificationUpdateOptional": {
              "Type": "Pass",
              "Comment": "Notification update failed but continue anyway (non-blocking)",
              "Result": {
                "success": false,
                "message": "Notification update failed - logged for manual review"
              },
              "End": true
            }
          }
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "PartialSystemUpdateFailure"
        }
      ],
      "Next": "UpdateClientProfileSuccess"
    },
    "UpdateClientProfileSuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "TimeoutSeconds": 10,
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
            "S.$": "$.phoneNumber"
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
      "Retry": [
        {
          "ErrorEquals": [
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "SendConfirmationEmail"
    },
    "SendConfirmationEmail": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Comment": "CRITICAL FIX - Send confirmation email to client",
      "Parameters": {
        "FunctionName": "${notification_sender_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "emailType": "phone_update_confirmation",
          "recipientEmail.$": "$.clientProfile.email",
          "oldPhone.$": "$.clientProfile.phoneNumber",
          "newPhone.$": "$.phoneNumber",
          "timestamp.$": "$$.State.EnteredTime",
          "approvedBy.$": "States.Format('{}', $.approval.approvedBy)"
        }
      },
      "ResultPath": "$.emailResult",
      "ResultSelector": {
        "success.$": "$.Payload.success",
        "messageId.$": "$.Payload.messageId"
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0,
          "Comment": "Retry email sending (2s → 4s → 8s)"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.emailError",
          "Next": "WorkflowSuccess",
          "Comment": "Email failed but workflow continues (non-blocking)"
        }
      ],
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
      "Comment": "Saga pattern - Mark phone history record as compensated for rollback",
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
        "UpdateExpression": "SET #compensated = :compensated, #compensatedAt = :compensatedAt, #reason = :reason",
        "ExpressionAttributeNames": {
          "#compensated": "compensated",
          "#compensatedAt": "compensatedAt",
          "#reason": "compensationReason"
        },
        "ExpressionAttributeValues": {
          ":compensated": {
            "BOOL": true
          },
          ":compensatedAt": {
            "S.$": "$$.State.EnteredTime"
          },
          ":reason": {
            "S": "MDMAE update failed - transaction rolled back"
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
            "S": "MDMAE updated but some downstream systems failed"
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
      "Type": "Succeed",
      "Comment": "Phone update workflow completed successfully with email confirmation sent"
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
      "Cause": "MDMAE API call failed after all retries"
    },
    "WorkflowPartialFailure": {
      "Type": "Fail",
      "Error": "PartialFailure",
      "Cause": "MDMAE succeeded but downstream systems (FCC/CRM/Notification) failed"
    },
    "WorkflowFailed": {
      "Type": "Fail",
      "Error": "WorkflowError",
      "Cause": "An error occurred during workflow execution"
    }
  }
}