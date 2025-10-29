terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-rini-2025"
    key            = "web-app/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# The two EC2 Instances 
resource "aws_instance" "instance_1" {
  ami           = "ami-0bc691261a82b32bc"
  instance_type = "t3.micro"
  #   security_groups = [aws_security_group_instances.name] Deprecated
  vpc_security_group_ids = [aws_security_group.instances.id]
  user_data              = <<-EOF
        #!/bin/bash
        echo "Hello World 1 " > index.html
        python3 -m http.server 8080 &
        EOF
}


resource "aws_instance" "instance_2" {
  ami           = "ami-0bc691261a82b32bc"
  instance_type = "t3.micro"
  #   security_groups        = [aws_security_group_instances.name]
  vpc_security_group_ids = [aws_security_group.instances.id]

  user_data = <<-EOF
        #!/bin/bash
        echo "Hello World 2 " > index.html
        python3 -m http.server 8080 &
        EOF
}

# S3 with versioning and sse
resource "aws_s3_bucket" "bucket" {
  bucket        = "terraform-demo-web-app-data"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket-sse" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# We will be using the default VPC
data "aws_vpc" "default_vpc" {
  default = true
}

# Deprecated
# data "aws_subnet_ids" "default_subnet" {
#   vpc_id = data.aws_vpc.default_vpc.id
# }

# All subnets in the default VPC
data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}


# Defining Security Groups 
resource "aws_security_group" "instances" {
  name   = "instance-security-group"
  vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.instances.id

  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_http_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.instances.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Application Load Balancer Setup
resource "aws_lb" "load_balancer" {
  name               = "web-app-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default_subnets.ids
  security_groups    = [aws_security_group.alb.id]
}


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404:page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "instances" {
  name     = "instances-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "instance_1" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "instance_2" {
  target_group_arn = aws_lb_target_group.instances.arn
  target_id        = aws_instance.instance_2.id
  port             = 8080
}


resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.instances.arn
  }
}

resource "aws_security_group" "alb" {
  name = "alb-security-group"
}

resource "aws_security_group_rule" "allow_alb_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "allow_alb_http_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

# Amazon Route53 setup
resource "aws_route53_zone" "primary" {
  name = "rini.me"
}

# Root domain pointing to ALB
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.primary.id
  name    = "rini.me"
  type    = "A"

  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }
}

# www subdomain
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.id
  name    = "www.rini.me"
  type    = "A"

  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }
}

# Temporary relational Database Setup
resource "aws_db_instance" "db_instance" {
  allocated_storage   = 20
  storage_type        = "standard"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  username            = "test"
  password            = "testtest"
  skip_final_snapshot = true
  publicly_accessible = false
}


