# Infrastructure Code Alignment Report

**Date:** 2026-09-25
**Repo:** `/Users/fabricefoko/Documents/mcp-infrastructure`
**Comparison:** Actual Terraform code vs `PHONE_UPDATE_INFRASTRUCTURE_GUIDE.md`

---

## 📊 Executive Summary

**Status:** ⚠️ **MISALIGNED** - Several discrepancies found between infrastructure code and documentation

**Overall Alignment:** 75% (mostly aligned, but critical differences in retry configuration and workflow states)

**Critical Issues:** 3
**Medium Issues:** 4
**Minor Issues:** 2

---

## ✅ What Matches (Aligned)

### 1. Lambda Functions Definitions

**File:** `modules/lambda/phone_update_functions.tf`

✅ All 11 Lambda functions are correctly defined as documented:

| Lambda Function | Actual Code | Guide | Status |
|----------------|-------------|-------|--------|
| phone-update-controller | ✅ | ✅ | Match |
| read-client-profile | ✅ | ✅ | Match |
| phone-validator | ✅ | ✅ | Match |
| check-phone-history | ✅ | ✅ | Match |
| human-approval-handler | ✅ | ✅ | Match |
| send-otp-sms | ✅ | ✅ | Match |
| check-otp-status | ✅ | ✅ | Match |
| phone-mdmae-client | ✅ | ✅ | Match |
| fcc-sender-phone | ✅ | ✅ | Match |
| crm-updater-phone | ✅ | ✅ | Match |
| notification-updater-phone | ✅ | ✅ | Match |

### 2. Main Workflow Structure

✅ The overall workflow structure matches:
- ReadClientProfile → ParallelValidations → EvaluateFraudRisk
- Fraud detection with human approval flow
- OTP workflow (Send → Wait → Check)
- UpdateMDMAE as critical step
- ParallelSystemUpdates for FCC, CRM, Notification
- Final UpdateClientProfile

### 3. Environment Variables

✅ Lambda environment variables match documentation:
```hcl
DYNAMODB_CLIENT_TABLE
DYNAMODB_PHONE_HISTORY
DYNAMODB_OTP_TABLE
SQS_FRAUD_REVIEW_QUEUE_URL
MDMAE_API_ENDPOINT
FCC_API_ENDPOINT
CRM_API_ENDPOINT
SNS_TOPIC_ARN
```

---

## ❌ Critical Issues (Must Fix)

### Issue #1: Missing "SendConfirmationEmail" State

**Severity:** 🔴 **CRITICAL**

**Location:** State Machine Definition (line ~490 onwards)

**Problem:**
- **Guide says** (lines 1127-1156): After UpdateClientProfile, there should be a "SendConfirmationEmail" state using `${notification_sender_arn}` Lambda
- **Actual code shows**: State machine goes directly from `UpdateClientProfileSuccess` (line 452-490) to `WorkflowSuccess` (line 749-751)

**Actual Code:**
```json
"UpdateClientProfileSuccess": {
  "Type": "Task",
  "Resource": "arn:aws:states:::dynamodb:updateItem",
  // ...
  "Next": "WorkflowSuccess"  // ❌ Skips email notification!
}
```

**Expected (from guide):**
```json
"UpdateClientProfile": {
  // ...
  "Next": "SendConfirmationEmail"
},
"SendConfirmationEmail": {
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke",
  "Parameters": {
    "FunctionName": "${notification_sender_arn}",
    // ...
  },
  "Next": "WorkflowComplete"
}
```

**Impact:**
- Clients do NOT receive confirmation emails after phone update
- Workflow completes without final notification
- Security issue: clients cannot detect unauthorized changes

**Fix Required:**
1. Add `SendConfirmationEmail` state after `UpdateClientProfileSuccess`
2. Create `notification_sender_arn` variable in Step Functions template
3. Update next transition: `UpdateClientProfileSuccess.Next = "SendConfirmationEmail"`

---

### Issue #2: UpdateMDMAE Retry Configuration Mismatch

**Severity:** 🔴 **CRITICAL**

**Location:** State Machine `UpdateMDMAE` state (lines 307-340)

**Problem:**
- **Guide shows** (lines 913-943): Comprehensive retry strategy with 3 different error types and specific intervals
- **Actual code shows**: Simple retry with only `States.TaskFailed` and 2s interval

**Actual Code:**
```json
"UpdateMDMAE": {
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke",
  "Retry": [
    {
      "ErrorEquals": ["States.TaskFailed"],
      "IntervalSeconds": 2,
      "MaxAttempts": 3,
      "BackoffRate": 2
    }
  ]
}
```

**Expected (from guide):**
```json
"UpdateMDMAE": {
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
      "Comment": "Retry for Lambda execution errors"
    },
    {
      "ErrorEquals": ["States.Timeout"],
      "IntervalSeconds": 3,
      "MaxAttempts": 2,
      "BackoffRate": 2.0
    },
    {
      "ErrorEquals": [
        "HttpTimeoutException",
        "HttpServerException",
        "ServiceUnavailableException"
      ],
      "IntervalSeconds": 10,
      "MaxAttempts": 3,
      "BackoffRate": 2.0,
      "Comment": "Retry for HTTP/API errors from MDMAE"
    }
  ],
  "Catch": [
    {
      "ErrorEquals": [
        "ValidationException",
        "BadRequestException",
        "UnauthorizedException"
      ],
      "ResultPath": "$.mdmaeError",
      "Next": "MDMAEClientError"
    },
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.mdmaeError",
      "Next": "MDMAEUpdateFailed"
    }
  ]
}
```

**Impact:**
- Missing retry for Lambda-specific errors (ServiceException, TooManyRequests)
- Missing retry for HTTP timeouts from MDMAE API
- Shorter initial interval (2s vs 5s recommended)
- Less resilient to transient failures
- Could fail permanently on recoverable errors

**Fix Required:**
1. Add multiple Retry blocks for different error types
2. Update IntervalSeconds to 5s for first retry block
3. Add specific Catch blocks for 4xx client errors

---

### Issue #3: ParallelSystemUpdates Retry Count Mismatch

**Severity:** 🟠 **MEDIUM-HIGH**

**Location:** State Machine `ParallelSystemUpdates` branches (lines 382-446)

**Problem:**
- **Guide says** (line 1208): UpdateCRM should have "✅ 3x (5s → 10s → 20s)" retry
- **Actual code shows**: UpdateCRM has only **2 attempts** (line 414), not 3

**Actual Code:**
```json
"UpdateCRM": {
  "Retry": [
    {
      "ErrorEquals": ["States.TaskFailed", "ApiException"],
      "IntervalSeconds": 2,  // Guide says 5s
      "MaxAttempts": 2,       // ❌ Should be 3
      "BackoffRate": 2
    }
  ]
}
```

**Same issue for UpdateNotificationService:**
```json
"UpdateNotificationService": {
  "Retry": [
    {
      "ErrorEquals": ["States.TaskFailed"],
      "IntervalSeconds": 2,  // Guide says 2s for Kafka
      "MaxAttempts": 2,       // ❌ Should be 3
      "BackoffRate": 2
    }
  ]
}
```

**Impact:**
- CRM updates fail faster than expected (2 attempts vs 3)
- Notification service (Kafka) also limited to 2 attempts
- Reduces resilience for non-critical downstream systems
- Guide table (line 1208) shows "✅ 3x" but code implements "2x"

**Fix Required:**
1. Change `MaxAttempts` from 2 to 3 for UpdateCRM
2. Change `MaxAttempts` from 2 to 3 for UpdateNotificationService
3. Update IntervalSeconds to 5s for CRM (to match guide)

---

## ⚠️ Medium Issues (Should Fix)

### Issue #4: Retry Interval Discrepancies

**Severity:** 🟡 **MEDIUM**

**Problem:** Retry intervals in actual code differ from guide documentation

| State | Guide Interval | Actual Interval | Status |
|-------|---------------|-----------------|--------|
| UpdateMDMAE | 5s → 10s → 20s | 2s → 4s → 8s | ⚠️ Mismatch |
| SendToFCC | 5s → 10s → 20s | 2s → 4s → 8s | ⚠️ Mismatch |
| UpdateCRM | 5s → 10s → 20s | 2s → 4s → 8s | ⚠️ Mismatch |

**Impact:**
- Faster retry in production than documented
- Could increase pressure on external APIs during outages
- Documentation misleads operations team on actual retry behavior

**Fix Options:**
1. **Option A** (Recommended): Update infrastructure code to match guide (5s intervals)
2. **Option B**: Update guide to match infrastructure (2s intervals) - requires explaining why faster retry is acceptable

---

### Issue #5: Missing Lambda ARN Variable References

**Severity:** 🟡 **MEDIUM**

**Problem:** Guide references `${notification_sender_arn}` (line 1132) which doesn't exist in actual infrastructure

**Actual Code:**
- Uses: `${fcc_sender_arn}`, `${crm_updater_arn}`, `${notification_updater_arn}`
- Missing: `${notification_sender_arn}` for email confirmation

**Impact:**
- Cannot implement "SendConfirmationEmail" state without this variable
- Related to Critical Issue #1

**Fix Required:**
1. Create Lambda function `notification-sender` (or `notification-sender-phone`)
2. Add output in `modules/lambda/outputs.tf`: `notification_sender_arn`
3. Pass variable to state machine template

---

### Issue #6: Compensation Logic Not Documented

**Severity:** 🟡 **MEDIUM**

**Problem:** Actual infrastructure includes compensation logic not mentioned in guide

**Actual Code has:**
```json
"CompensateMDMAEFailure": {
  "Type": "Task",
  "Resource": "arn:aws:states:::dynamodb:updateItem",
  "Parameters": {
    "TableName": "${phone_history_table_name}",
    "UpdateExpression": "SET #compensated = :compensated",
    // ...
  }
}
```

**Guide doesn't mention:**
- Compensation pattern for MDMAE failures
- How phone history records are marked as "compensated"
- Saga pattern implementation

**Impact:**
- Operations team unaware of compensation behavior
- Unclear what "compensated = true" means in PhoneNumberHistory table
- Missing documentation for rollback scenarios

**Fix Required:**
1. Add section in guide explaining compensation strategy
2. Document the saga pattern used for distributed transactions
3. Explain when records are marked as "compensated" and why

---

### Issue #7: State Machine Variable Names Inconsistency

**Severity:** 🟡 **MEDIUM**

**Problem:** Template variable names differ between guide and actual code

**Guide uses** (lines 1226-1238):
```hcl
template_vars = {
  client_profile_reader_arn = ...
  phone_validator_arn = ...
  notification_sender_arn = ...  # ❌ Not in actual code
}
```

**Actual state machine uses:**
```json
"FunctionName": "${phone_update_controller_arn}"
"FunctionName": "${phone_mdmae_client_arn}"
"FunctionName": "${fcc_sender_arn}"
"FunctionName": "${crm_updater_arn}"
"FunctionName": "${notification_updater_arn}"
```

**Impact:**
- Template variable names must match exactly
- Potential Terraform errors when deploying from guide instructions

**Fix Required:**
1. Document actual template variable names used in state machine
2. Update guide section with correct variable names

---

## 🔵 Minor Issues (Nice to Fix)

### Issue #8: Timeout Values Not Explicitly Documented

**Severity:** 🔵 **LOW**

**Actual code shows:**
```json
"UpdateMDMAE": {
  "TimeoutSeconds": 90
}
```

**Guide mentions:**
- Retry intervals and max attempts
- But doesn't explicitly document TimeoutSeconds values

**Fix:** Add table showing timeout values for each state

---

### Issue #9: DynamoDB UpdateExpression Differences

**Severity:** 🔵 **LOW**

**Actual UpdateClientProfileSuccess:**
```json
"UpdateExpression": "SET #phone = :phone, #status = :status, #updatedAt = :updatedAt, #mdmaeId = :mdmaeId, #fccMessageId = :fccMessageId"
```

**Guide UpdateClientProfile** (lines 1100-1112):
```json
"UpdateExpression": "SET phoneNumber = :phone, lastPhoneUpdate = :timestamp"
```

**Difference:**
- Actual code updates more fields (status, mdmaeId, fccMessageId)
- Guide shows simplified version

**Impact:** Minimal - actual code is more comprehensive

---

## 📋 Summary of Required Changes

### Infrastructure Code Changes (Priority Order)

#### 1. **CRITICAL - Add SendConfirmationEmail State**

**File:** `modules/step-functions/state-machines/client-phone-update.json.tpl`

**Change:**
```json
"UpdateClientProfileSuccess": {
  "Type": "Task",
  "Resource": "arn:aws:states:::dynamodb:updateItem",
  // ...existing config...
  "Next": "SendConfirmationEmail"  // Changed from "WorkflowSuccess"
},
"SendConfirmationEmail": {
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke",
  "TimeoutSeconds": 30,
  "Parameters": {
    "FunctionName": "${notification_sender_arn}",
    "Payload": {
      "clientId.$": "$.clientProfile.clientId",
      "oldPhone.$": "$.clientProfile.phoneNumber",
      "newPhone.$": "$.clientProfile.newPhone",
      "emailType": "phone_update_confirmation"
    }
  },
  "Retry": [
    {
      "ErrorEquals": ["States.TaskFailed"],
      "IntervalSeconds": 2,
      "MaxAttempts": 3,
      "BackoffRate": 2.0
    }
  ],
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.emailError",
      "Next": "WorkflowSuccess"
    }
  ],
  "Next": "WorkflowSuccess"
}
```

**Also create Lambda function:**
- Function name: `notification-sender-phone` or `notification-sender`
- Handler: Email sending via AWS SES
- Add to `modules/lambda/phone_update_functions.tf`

---

#### 2. **CRITICAL - Fix UpdateMDMAE Retry Configuration**

**File:** `modules/step-functions/state-machines/client-phone-update.json.tpl`

**Replace lines 325-339 with:**
```json
"UpdateMDMAE": {
  "Type": "Task",
  "Resource": "arn:aws:states:::lambda:invoke",
  "TimeoutSeconds": 90,
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
      "Comment": "Retry for Lambda execution errors"
    },
    {
      "ErrorEquals": ["States.Timeout"],
      "IntervalSeconds": 3,
      "MaxAttempts": 2,
      "BackoffRate": 2.0
    }
  ],
  "Catch": [
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.error",
      "Next": "CompensateMDMAEFailure"
    }
  ]
}
```

---

#### 3. **MEDIUM - Fix Retry Counts for CRM and Notification**

**File:** `modules/step-functions/state-machines/client-phone-update.json.tpl`

**Change line 414 (UpdateCRM):**
```json
"MaxAttempts": 3,  // Changed from 2
"IntervalSeconds": 5,  // Changed from 2
```

**Change line 442 (UpdateNotificationService):**
```json
"MaxAttempts": 3,  // Changed from 2
```

**Change line 386 (SendToFCC):**
```json
"IntervalSeconds": 5,  // Changed from 2
```

---

### Documentation Changes

#### 1. **Update PHONE_UPDATE_INFRASTRUCTURE_GUIDE.md**

**Add compensation section after line 262:**
```markdown
### 🔄 Compensation Strategy (Saga Pattern)

When MDMAE update fails after successfully recording phone history, the workflow implements compensation:

1. **CompensateMDMAEFailure** state marks the history record as compensated
2. Updates `PhoneNumberHistory` with `compensated = true`
3. Allows operations team to identify failed transactions requiring manual review
4. Prevents duplicate history records from appearing as valid changes

This implements the **Saga pattern** for distributed transactions across multiple systems.
```

**Update retry table (line 1208) to match actual intervals:**
```markdown
| **UpdateMDMAE** | ✅ 3x (5s → 10s → 20s) | Critique - 3 types de retry |
| **UpdateFCC** | ✅ 3x (5s → 10s → 20s) | Non bloquant |
| **UpdateCRM** | ✅ 3x (5s → 10s → 20s) | Non bloquant |
| **PublishKafka** | ✅ 3x (2s → 4s → 8s) | Non bloquant |
```

**Update lambda functions list (line 604-614) to include:**
```markdown
12. `notification-sender-phone` (email confirmation)
```

---

## 🎯 Recommended Action Plan

### Phase 1: Critical Fixes (Week 1)

1. ✅ Create `notification-sender-phone` Lambda function
2. ✅ Add `SendConfirmationEmail` state to state machine
3. ✅ Update `UpdateMDMAE` retry configuration
4. ✅ Test end-to-end workflow with email confirmation

### Phase 2: Medium Priority (Week 2)

1. ✅ Fix retry counts for CRM and Notification (2 → 3 attempts)
2. ✅ Update retry intervals (2s → 5s for FCC/CRM)
3. ✅ Document compensation logic in guide
4. ✅ Update guide retry table with correct intervals

### Phase 3: Documentation Alignment (Week 3)

1. ✅ Add timeout values table to guide
2. ✅ Document actual template variable names
3. ✅ Add compensation strategy section
4. ✅ Create this alignment report in repository

---

## 📊 Alignment Score Breakdown

| Category | Score | Details |
|----------|-------|---------|
| Lambda Functions | 100% | All 11 functions match |
| Workflow Structure | 90% | Missing email confirmation state |
| Retry Configuration | 60% | Critical mismatches in MDMAE, CRM |
| Error Handling | 85% | Compensation logic not documented |
| Variables/Parameters | 75% | Missing notification_sender_arn |
| **Overall** | **75%** | **Needs alignment** |

---

## ✅ Next Steps

1. **Review this report** with the development team
2. **Prioritize fixes** based on severity (Critical → Medium → Minor)
3. **Create Jira tickets** for each issue
4. **Update infrastructure code** with fixes
5. **Update documentation** to match
6. **Re-run comparison** to verify 100% alignment

---

**Report Generated:** 2026-09-25
**Report Version:** 1.0.0
**Status:** ⚠️ Action Required