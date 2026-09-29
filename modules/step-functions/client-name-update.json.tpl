{
  "Comment": "Client Name Update Workflow",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "${client_profile_reader_arn}",
      "Next": "ValidateName"
    },
    "ValidateName": {
      "Type": "Task",
      "Resource": "${name_validator_arn}",
      "Next": "CheckMDMAE"
    },
    "CheckMDMAE": {
      "Type": "Task",
      "Resource": "${mdmae_client_arn}",
      "Next": "SendToFCC"
    },
    "SendToFCC": {
      "Type": "Task",
      "Resource": "${fcc_sender_arn}",
      "End": true
    }
  }
}