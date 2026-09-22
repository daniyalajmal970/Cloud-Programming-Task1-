variable "aws_region" {
  description = "AWS region for the regional part of the stack (VPC, ALB, EC2)."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name prefix used for all resources."
  type        = string
  default     = "hello-web"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread the stack over (min. 2 for high availability)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 Availability Zones for a highly available setup."
  }
}

variable "instance_type" {
  description = "EC2 instance type of the web servers."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of web servers (>= 2 keeps one per AZ)."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Initial number of web servers."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of web servers the Auto Scaling Group may launch."
  type        = number
  default     = 6
}

variable "cpu_target_percent" {
  description = "Target average CPU utilisation for the target-tracking scaling policy."
  type        = number
  default     = 50
}

variable "requests_per_target" {
  description = "Target number of ALB requests per instance per minute for the second scaling policy."
  type        = number
  default     = 1000
}

variable "cloudfront_price_class" {
  description = "CloudFront price class. PriceClass_All = all edge locations worldwide (lowest global latency)."
  type        = string
  default     = "PriceClass_All"
}

variable "enable_ssm_endpoints" {
  description = "Create interface endpoints so SSM Session Manager works in the private subnets (costs ~0.01 USD/h per endpoint and AZ)."
  type        = bool
  default     = false
}

variable "alarm_email" {
  description = "Optional e-mail address for CloudWatch alarm notifications (leave empty to disable)."
  type        = string
  default     = ""
}
