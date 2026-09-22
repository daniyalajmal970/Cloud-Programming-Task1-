output "website_url" {
  description = "Public HTTPS URL of the website (CloudFront)."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}

output "whoami_url" {
  description = "Uncached page showing which instance/AZ answered."
  value       = "https://${aws_cloudfront_distribution.web.domain_name}/whoami.html"
}

output "alb_dns_name" {
  description = "DNS name of the load balancer (direct access returns 403 by design)."
  value       = aws_lb.web.dns_name
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group (used by the test scripts)."
  value       = aws_autoscaling_group.web.name
}

output "cloudwatch_dashboard_url" {
  description = "Link to the CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.web.dashboard_name}"
}
