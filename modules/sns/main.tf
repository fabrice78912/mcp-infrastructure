# ========================================
# SNS Topics
# ========================================

resource "aws_sns_topic" "this" {
  for_each = var.topics

  name              = "${var.environment}-${var.project_name}-${each.key}"
  display_name      = each.value.display_name
  kms_master_key_id = var.enable_encryption ? "alias/aws/sns" : null

  tags = {
    Name        = "${var.environment}-${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# ========================================
# SNS Topic Subscriptions (optional)
# ========================================

resource "aws_sns_topic_subscription" "this" {
  for_each = var.subscriptions

  topic_arn = aws_sns_topic.this[each.value.topic_key].arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  filter_policy = each.value.filter_policy
}