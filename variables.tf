variable "region" {
     description = "AWS region"
     default     = "us-east-1"
     type        = string
   }

   variable "instance_type" {
     description = "EC2 instance type"
     default     = "t3.micro"
     type        = string
   }

   variable "key_name" {
     description = "Name of the SSH key pair"
     type        = string
   }

   variable "allowed_cidr" {
     description = "CIDR block allowed for SSH access"
     type        = string
   }

   variable "domain_name" {
     description = "Existing domain name managed in Route 53 (e.g., example.com)"
     type        = string
   }

   variable "alert_email" {
     description = "Email for CloudWatch alarm notifications"
     type        = string
   }

   variable "state_bucket" {
     description = "S3 bucket for Terraform state"
     type        = string
   }