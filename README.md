# AWS Hands-On Resume Projects — Terraform Guide

## Prerequisites
- AWS CLI installed and configured (`aws configure`)
- Terraform installed (v1.5+)
- An AWS account (Free Tier works for all projects)

---

## How to deploy any project

```bash
cd project1-ha-webapp/   # or project2 / project3

terraform init           # Download providers
terraform plan           # Preview what will be created
terraform apply          # Deploy (type 'yes' to confirm)

terraform destroy        # IMPORTANT: tear down when done to avoid charges
```

---

## Project 1 — HA Web App (EC2 + ALB + ASG)
**Before deploying:** Edit `key_pair_name` variable with your actual EC2 key pair name.
**After deploying:** Visit the `alb_dns_name` output URL in your browser.
**Free tier note:** t2.micro instances are free tier. ALB costs ~$0.02/hour — destroy when done.

---

## Project 2 — Serverless REST API (API Gateway + Lambda + DynamoDB)
**After deploying:** Use the `api_test_commands` output to test your API with curl.
**Free tier note:** Lambda and DynamoDB have generous free tiers. API Gateway is ~$3.50 per million requests.

---

## Project 3 — Monitoring & Alerting (CloudWatch + SNS)
**Before deploying:** Edit the `alert_email` variable with your real email.
**After deploying:** Check your email and confirm the SNS subscription — alerts won't work until you do.
**Free tier note:** CloudWatch has a free tier (10 alarms, 5GB logs). t2.micro is free tier.

---

## CV Bullet Points (copy these)

**Project 1:**
> Deployed a highly available web application on AWS using EC2, Application Load Balancer, and Auto Scaling Groups across multiple availability zones, provisioned entirely with Terraform.

**Project 2:**
> Built and deployed a serverless REST API with full CRUD operations using AWS API Gateway, Lambda (Python), and DynamoDB, with least-privilege IAM policies enforced via Terraform.

**Project 3:**
> Implemented centralised infrastructure monitoring using CloudWatch metrics, custom alarms, and SNS email alerting for CPU, memory, disk, and instance health checks, deployed as Infrastructure as Code with Terraform.

---

## GitHub README tip
Push each project folder to its own GitHub repo. In the README, include:
1. Architecture diagram (draw one on draw.io — free)
2. A screenshot of it working (ALB URL, API response, CloudWatch dashboard)
3. The CV bullet point above
