output "sns_topic_arn" {
  description = "アラーム通知用 SNS Topic ARN"
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "作成したアラーム名のリスト (CF アラームは envs root で別途作成)"
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_duration.alarm_name,
    aws_cloudwatch_metric_alarm.apigw_5xx.alarm_name,
  ]
}

output "budget_name" {
  description = "AWS Budgets リソース名（alarm_email 未設定なら null）"
  value       = try(aws_budgets_budget.monthly[0].name, null)
}
