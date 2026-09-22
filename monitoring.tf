# ---------------------------------------------------------------------------
# CloudWatch alarms and dashboard
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  count = var.alarm_email == "" ? 0 : 1
  name  = "${var.project_name}-alarms"

  kms_master_key_id = "alias/aws/sns" # encryption at rest with the AWS-managed key
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alarms[0].arn]
}

# Fires when at least one instance behind the ALB is unhealthy.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  alarm_description   = "At least one web server fails the ALB health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }
}

# Fires when the backend returns server errors.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project_name}-target-5xx"
  alarm_description   = "Web servers return HTTP 5xx errors."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

resource "aws_cloudwatch_dashboard" "web" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Requests through the ALB"
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.web.arn_suffix]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Average CPU of the Auto Scaling Group"
          region  = var.aws_region
          stat    = "Average"
          period  = 60
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web.name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Healthy / unhealthy instances"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.web.arn_suffix, "LoadBalancer", aws_lb.web.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.web.arn_suffix, "LoadBalancer", aws_lb.web.arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Instances in service (ASG)"
          region  = var.aws_region
          stat    = "Average"
          period  = 60
          metrics = [["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.web.name]]
        }
      }
    ]
  })
}
