# ---------------------------------------------------------------------------
# Application Load Balancer spanning all public subnets (multi-AZ)
# ---------------------------------------------------------------------------

resource "aws_lb" "web" {
  #checkov:skip=CKV_AWS_150:Deletion protection is off so the course environment can be destroyed.
  #checkov:skip=CKV_AWS_91:Access logs omitted to avoid extra S3 costs; CloudWatch metrics are used instead.
  #checkov:skip=CKV2_AWS_28:WAF is optional (cost); the ALB only accepts CloudFront traffic with a secret header.
  #checkov:skip=CKV2_AWS_20:Viewers use HTTPS at CloudFront; without a custom domain the ALB has no certificate.
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  enable_deletion_protection = false # keep false so `terraform destroy` works for the course
}

resource "aws_lb_target_group" "web" {
  #checkov:skip=CKV_AWS_378:Traffic from the ALB to the instances stays inside the private VPC.
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:No custom domain/certificate; HTTPS is terminated at CloudFront (see README).
  #checkov:skip=CKV_AWS_103:See CKV_AWS_2.
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  # Default: reject everything that does not come through CloudFront.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied - please use the CloudFront URL."
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_secret.result]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
