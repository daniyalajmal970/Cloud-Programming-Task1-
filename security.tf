# ---------------------------------------------------------------------------
# Security groups (least privilege) and the IAM role of the web servers
# ---------------------------------------------------------------------------

# AWS-managed list of the IP ranges CloudFront uses to reach origins.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: HTTP only from CloudFront edge servers"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  #checkov:skip=CKV_AWS_260:Source is the CloudFront managed prefix list, not 0.0.0.0/0.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront origin-facing servers"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP to the web servers"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web servers: HTTP only from the ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  #checkov:skip=CKV_AWS_260:Source is the ALB security group, not 0.0.0.0/0.
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Outbound HTTPS (package repos via the S3 endpoint, SSM endpoints).
# The private route table has no internet route, so this cannot reach the internet.
resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to VPC endpoints"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_security_group" "endpoints" {
  name        = "${var.project_name}-endpoints-sg"
  description = "Interface endpoints: HTTPS from the web servers"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-endpoints-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_web" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the web servers"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# IAM role for the instances: only the permissions SSM Session Manager needs.
resource "aws_iam_role" "web" {
  name = "${var.project_name}-web-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.project_name}-web-profile"
  role = aws_iam_role.web.name
}

# Secret header that CloudFront adds to every origin request. The ALB only
# forwards requests carrying it, so nobody can bypass CloudFront.
resource "random_password" "origin_secret" {
  length  = 32
  special = false
}
