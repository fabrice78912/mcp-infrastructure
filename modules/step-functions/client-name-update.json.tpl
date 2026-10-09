{
  "Comment": "Client Name Update Workflow - Reads profile, validates, calls MDMAE, sends to FCC",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "${client_profile_reader_arn}",
      "TimeoutSeconds": 300,
      "Next": "ValidateName"
    },
    "ValidateName": {
      "Type": "Task",
      "Resource": "${name_validator_arn}",
      "TimeoutSeconds": 300,
      "Next": "CheckMDMAE"
    },
    "CheckMDMAE": {
      "Type": "Task",
      "Resource": "${mdmae_client_arn}",
      "TimeoutSeconds": 300,
      "Next": "SendToFCC"
    },
    "SendToFCC": {
      "Type": "Task",
      "Resource": "${fcc_sender_arn}",
      "TimeoutSeconds": 300,
      "End": true
    }
  }
}