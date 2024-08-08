output "webhook_url" {
  value = "${aws_apigatewayv2_api.github_webhook_api.api_endpoint}/webhook"
}
