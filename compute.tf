# ---------------------------------------------------------------------------
# Web servers: launch template + Auto Scaling Group + scaling policies
# ---------------------------------------------------------------------------

# Always use the latest Amazon Linux 2023 AMI published by AWS.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.web.arn
  }

  # Enforce IMDSv2 (security best practice).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true # 1-minute CloudWatch metrics -> faster scaling reactions
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    project_name = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-web" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.web.arn]

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  # Replace instances that fail the ALB health check, not only EC2 status checks.
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_instance_warmup   = 120

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  # Rolling replacement when the launch template changes (zero downtime).
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }
}

# Scaling policy 1: keep the average CPU utilisation around the target.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project_name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}

# Scaling policy 2: keep the number of requests per instance around the target.
# (The ASG scales out if EITHER policy asks for more capacity.)
resource "aws_autoscaling_policy" "requests" {
  name                   = "${var.project_name}-requests-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.web.arn_suffix}/${aws_lb_target_group.web.arn_suffix}"
    }
    target_value = var.requests_per_target
  }

  # The listener rule must exist before traffic (and this metric) can flow.
  depends_on = [aws_lb_listener_rule.from_cloudfront]
}
