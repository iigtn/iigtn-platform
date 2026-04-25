output "api_endpoint" {
  description = <<-EOT
    API Gateway HTTP API のデフォルトエンドポイント
    (`https://<api_id>.execute-api.<region>.amazonaws.com`)。
    CloudFront の追加 origin として使う。`https://` プレフィクスなしの
    ホスト名だけ取り出すには cloudfront 配線側で replace() する。
  EOT
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_endpoint_host" {
  description = "API Gateway のホスト名のみ (https:// なし)。CloudFront origin に直で使える"
  value       = replace(aws_apigatewayv2_api.this.api_endpoint, "https://", "")
}

output "api_id" {
  description = "API Gateway HTTP API ID"
  value       = aws_apigatewayv2_api.this.id
}

output "lambda_function_name" {
  description = "Lambda 関数名"
  value       = aws_lambda_function.contact.function_name
}

output "lambda_function_arn" {
  description = "Lambda 関数 ARN"
  value       = aws_lambda_function.contact.arn
}

output "table_name" {
  description = "DynamoDB テーブル名"
  value       = aws_dynamodb_table.contacts.name
}

output "table_arn" {
  description = "DynamoDB テーブル ARN"
  value       = aws_dynamodb_table.contacts.arn
}

output "log_group_name" {
  description = "Lambda の CloudWatch Logs グループ名"
  value       = aws_cloudwatch_log_group.contact.name
}
