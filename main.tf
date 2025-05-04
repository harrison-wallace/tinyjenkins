terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "placeholder-bucket"
    key            = "jenkins/terraform.tfstate"
    region         = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "jenkins-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "jenkins-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "jenkins-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "jenkins-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "Allow Jenkins and SSH access"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "jenkins-sg"
  }
}

# IAM Role for EC2
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "jenkins_policy" {
  name = "jenkins_s3_policy"
  role = aws_iam_role.jenkins_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.backups.arn}",
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins_instance_profile"
  role = aws_iam_role.jenkins_role.name
}

# Launch Template
resource "aws_launch_template" "jenkins" {
  name_prefix   = "jenkins-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name
  iam_instance_profile {
    name = aws_iam_instance_profile.jenkins_profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups            = [aws_security_group.jenkins_sg.id]
  }
  user_data = base64encode(templatefile("user_data.sh", { backup_bucket = aws_s3_bucket.backups.bucket }))

  # Ensure the latest version is set as default
  lifecycle {
    create_before_destroy = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Jenkins-Spot"
    }
  }

  # Track the latest version
  default_version = 2  # Set explicitly to the latest version after update
}

# Auto-Scaling Group
resource "aws_autoscaling_group" "jenkins_asg" {
  name                = "jenkins-asg"
  max_size            = 1
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.public.id]
  launch_template {
    id      = aws_launch_template.jenkins.id
    version = aws_launch_template.jenkins.latest_version  # Explicitly use the latest version
  }
  health_check_type         = "EC2"
  health_check_grace_period = 300
  tag {
    key                 = "Name"
    value               = "Jenkins-Spot"
    propagate_at_launch = true
  }

  # Force update to use new launch template version
  lifecycle {
    create_before_destroy = true
  }
}

# Fetch Instances Managed by ASG
data "aws_instances" "jenkins_instances" {
  instance_tags = {
    Name = "Jenkins-Spot"
  }
  depends_on = [aws_autoscaling_group.jenkins_asg]
}

# Local Variable for Public IP
locals {
  public_ip = length(data.aws_instances.jenkins_instances.public_ips) > 0 ? data.aws_instances.jenkins_instances.public_ips[0] : "127.0.0.1"
}

# S3 Bucket for Backups
resource "aws_s3_bucket" "backups" {
  bucket = "jenkins-backups-${random_string.suffix.result}"
  tags = {
    Name = "jenkins-backups"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter {
      prefix = ""
    }
    expiration {
      days = 7
    }
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Route 53
data "aws_route53_zone" "jenkins" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.jenkins.zone_id
  name    = "jenkins.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = length(data.aws_instances.jenkins_instances.public_ips) > 0 ? [data.aws_instances.jenkins_instances.public_ips[0]] : ["127.0.0.1"]
  depends_on = [aws_autoscaling_group.jenkins_asg]
}

# SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "jenkins_alarms" {
  name = "jenkins-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.jenkins_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_usage" {
  alarm_name          = "jenkins-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when CPU usage exceeds 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.jenkins_alarms.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_health" {
  alarm_name          = "jenkins-instance-health"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Triggers when EC2 instance fails health checks"
  alarm_actions       = [aws_sns_topic.jenkins_alarms.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_asg.name
  }
}

# AMI Data
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

output "jenkins_url" {
  value = "http://jenkins.${var.domain_name}:8080"
}