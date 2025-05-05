variable "REGION" {
  description = "AWS region"
  default     = "us-east-1"
  type        = string
}

variable "INSTANCE_TYPE" {
  description = "EC2 instance type"
  default     = "t3.micro"
  type        = string
}

variable "KEY_NAME" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "ALLOWED_CIDR" {
  description = "CIDR block allowed for SSH access"
  type        = string
}

variable "DOMAIN_NAME" {
  description = "Existing domain name managed in Route 53 (e.g., example.com)"
  type        = string
}

variable "ALERT_EMAIL" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
}

variable "STATE_BUCKET" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "ENABLE_HTTPS" {
  description = "Enable HTTPS with ACM certificate and Nginx"
  default     = false
  type        = bool
}

variable "ENABLE_DYNAMIC_DNS" {
  description = "Enable Route 53 health checks and Lambda for dynamic DNS updates"
  default     = true
  type        = bool
}