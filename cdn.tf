# ---------------------------------------------------------------------------
# CloudFront: global edge caching, HTTPS for viewers, ALB as origin
# ---------------------------------------------------------------------------

# AWS-managed cache policies.
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# AWS-managed policy adding HSTS, X-Content-Type-Options, X-Frame-Options, etc.
data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "web" {
  #checkov:skip=CKV_AWS_174:The default *.cloudfront.net certificate is used (no custom domain).
  #checkov:skip=CKV2_AWS_42:See CKV_AWS_174.
  #checkov:skip=CKV_AWS_68:WAF is optional (cost) for a static hello-world page.
  #checkov:skip=CKV2_AWS_47:See CKV_AWS_68.
  #checkov:skip=CKV_AWS_86:Access logging omitted to avoid extra S3 costs.
  #checkov:skip=CKV_AWS_374:The site must be reachable worldwide, so no geo restriction.
  #checkov:skip=CKV_AWS_310:A single multi-AZ ALB origin is already highly available.
  enabled             = true
  comment             = "${var.project_name} - Cloud Programming Task 1"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id   = "alb"
    domain_name = aws_lb.web.dns_name

    # Secret header checked by the ALB listener rule.
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_secret.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # no custom domain -> no certificate on the ALB (see README)
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default: cache the static page at the edge.
  default_cache_behavior {
    target_origin_id           = "alb"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
    compress                   = true
  }

  # /whoami.html is never cached, so every request reaches an instance.
  # Used to demonstrate load balancing and autoscaling.
  ordered_cache_behavior {
    path_pattern               = "/whoami.html"
    target_origin_id           = "alb"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Free default certificate for *.cloudfront.net (no custom domain needed).
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------------------------------------------------------------------------
# OPTIONAL - custom domain with Route 53 + ACM.
# Requires a domain in a Route 53 hosted zone. The certificate must be
# created in us-east-1 for CloudFront. Uncomment and adapt if you own a domain.
# ---------------------------------------------------------------------------
# provider "aws" {
#   alias  = "us_east_1"
#   region = "us-east-1"
# }
#
# data "aws_route53_zone" "main" {
#   name = "example.com"
# }
#
# resource "aws_acm_certificate" "site" {
#   provider          = aws.us_east_1
#   domain_name       = "www.example.com"
#   validation_method = "DNS"
# }
#
# (+ aws_route53_record for validation, aws_acm_certificate_validation,
#  `aliases` and `viewer_certificate { acm_certificate_arn = ... }` in the
#  distribution, and an alias A/AAAA record pointing to the distribution.)
