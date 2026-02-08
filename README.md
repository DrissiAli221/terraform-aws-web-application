# AWS Cloud Infrastructure

This project represents my first deep dive into **Infrastructure as Code (IaC)**. Transitioning from manual server provisioning, I used **Terraform** to define and manage the entire infrastructure state for a web application on AWS. Before this, I mostly deployed things manually, this project was my introduction to Terraform and IaC.

## Architecture

![Cloud Architecture Diagram](<AWS%20(2025)%20horizontal%20framework.png>)

## Highlights

- **Monolithic Architecture**: Provisioned a straightforward architecture using AWS EC2 for compute and RDS (PostgreSQL) for data persistence.
- **High Availability**: Implemented an Application Load Balancer (ALB) to distribute traffic across instances.
- **Security First**: Configured strict Security Groups to limit access to necessary HTTP/TCP ports.
- **State Management**: Learned to manage Terraform state securely using S3 with DynamoDB locking to prevent concurrent modifications.
- **DNS Configuration**: Configured Route53 for DNS management of the custom domain `rini.me`.

## Tech Stack

- **Terraform**
- **AWS (EC2, ALB, RDS)**
- **AWS Route53**
- **AWS S3**

## Getting Started

If you want to spin this up yourself to see how it works:

### 1. Prerequisites

You'll need the [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) and the [AWS CLI](https://aws.amazon.com/cli/) configured on your machine.

### 2. Infrastructure Setup

First, I set up the backend (S3 + DynamoDB) to store the Terraform state file securely.

```bash
cd aws-backend
terraform init
terraform apply
```

Then, I deployed the actual application infrastructure.

```bash
cd ../web-app
terraform init
terraform apply
```

> [!NOTE]
> **Learning Note**: Since this is a demo/learning project, the database password in `web-app/main.tf` is hardcoded. In a real-world production environment, I would use AWS Secrets Manager or Terraform variables to handle this securely!

## Clean Up

Don't forget to destroy resources to avoid AWS charges:

```bash
cd web-app
terraform destroy
# ... confirm destroy ...
cd ../aws-backend
terraform destroy
```
