# ============================================================
# PROJECT 3: Centralized Monitoring & Alerting
# Services: CloudWatch + SNS
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "eu-west-2"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alerts"
  type        = string
  default     = "hardikshrivastava8jan@gmail.com" # Replace with your email
}

# ----------------------------
# SNS TOPIC + EMAIL SUBSCRIPTION
# ----------------------------
resource "aws_sns_topic" "alerts" {
  name = "cloudwatch-alerts"
  tags = { Name = "cloudwatch-alerts" }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # NOTE: You must confirm the subscription via email after terraform apply
}

# ----------------------------
# EC2 INSTANCE (to monitor)
# ----------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-sg"
  description = "Allow SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "monitored_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  # Install CloudWatch agent via user data
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-cloudwatch-agent

    # Create CloudWatch agent config
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CONFIG'
    {
      "metrics": {
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "mem": {
            "measurement": ["mem_used_percent"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["disk_used_percent"],
            "resources": ["/"],
            "metrics_collection_interval": 60
          },
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user"],
            "metrics_collection_interval": 60,
            "totalcpu": true
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/ec2/system-logs",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      }
    }
    CONFIG

    # Start the agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOF

  iam_instance_profile = aws_iam_instance_profile.ec2_monitoring_profile.name

  tags = { Name = "monitored-ec2" }
}

# ----------------------------
# IAM FOR EC2 (CloudWatch permissions)
# ----------------------------
resource "aws_iam_role" "ec2_monitoring_role" {
  name = "ec2-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  role       = aws_iam_role.ec2_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_monitoring_profile" {
  name = "ec2-monitoring-profile"
  role = aws_iam_role.ec2_monitoring_role.name
}

# ----------------------------
# CLOUDWATCH ALARMS
# ----------------------------

# Alarm 1: High CPU Usage
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU usage exceeded 80% for 4 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.monitored_ec2.id
  }

  tags = { Name = "high-cpu-alarm" }
}

# Alarm 2: High Memory Usage (requires CloudWatch agent)
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "high-memory-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 120
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Memory usage exceeded 85%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.monitored_ec2.id
  }

  tags = { Name = "high-memory-alarm" }
}

# Alarm 3: Instance Status Check Failed
resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "instance-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance status check failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.monitored_ec2.id
  }

  tags = { Name = "instance-status-alarm" }
}

# Alarm 4: High Disk Usage (requires CloudWatch agent)
resource "aws_cloudwatch_metric_alarm" "high_disk" {
  alarm_name          = "high-disk-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "Disk usage exceeded 90%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.monitored_ec2.id
    path       = "/"
    fstype     = "xfs"
  }

  tags = { Name = "high-disk-alarm" }
}

# ----------------------------
# CLOUDWATCH DASHBOARD
# ----------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "EC2-Monitoring-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title  = "CPU Utilization"
          period = 60
          region = "eu-west-2"
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.monitored_ec2.id]
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title  = "Memory Used %"
          period = 60
          region = "eu-west-2"
          stat   = "Average"
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.monitored_ec2.id]
          ]
        }
      },
      {
        type = "alarm"
        properties = {
          title = "Active Alarms"
          region = "eu-west-2"
          alarms = [
            aws_cloudwatch_metric_alarm.high_cpu.arn,
            aws_cloudwatch_metric_alarm.high_memory.arn,
            aws_cloudwatch_metric_alarm.instance_status.arn,
            aws_cloudwatch_metric_alarm.high_disk.arn,
          ]
        }
      }
    ]
  })
}

# ----------------------------
# LOG GROUP
# ----------------------------
resource "aws_cloudwatch_log_group" "ec2_logs" {
  name              = "/ec2/system-logs"
  retention_in_days = 7
  tags              = { Name = "ec2-system-logs" }
}

# ----------------------------
# OUTPUTS
# ----------------------------
output "instance_id" {
  value = aws_instance.monitored_ec2.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=EC2-Monitoring-Dashboard"
}

output "important_note" {
  value = "IMPORTANT: Check your email (${var.alert_email}) and confirm the SNS subscription to receive alerts!"
}
