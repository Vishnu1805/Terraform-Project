
############################
# 1. NETWORKING (VPC, SUBNET)
############################

resource "aws_vpc" "web_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "webapp-vpc" }
}

resource "aws_subnet" "web_subnet" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "webapp-subnet" }
}

resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id
  tags   = { Name = "webapp-igw" }
}

resource "aws_route_table" "web_route_table" {
  vpc_id = aws_vpc.web_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }
  tags = { Name = "webapp-rt" }
}

resource "aws_route_table_association" "web_rta" {
  subnet_id      = aws_subnet.web_subnet.id
  route_table_id = aws_route_table.web_route_table.id
}

############################
# 2. SECURITY GROUPS
############################

resource "aws_security_group" "web_sg" {
  name        = "webapp-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.web_vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
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

  tags = { Name = "webapp-sg" }
}

############################
# 3. EC2 INSTANCE
############################

resource "aws_instance" "web_server" {
  ami                         = "ami-0c02fb55956c7d316" # Amazon Linux 2 (ap-south-1)
  instance_type               = t2.micro
  subnet_id                   = aws_subnet.web_subnet.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y git nodejs npm
              cd /home/ec2-user
              git clone https://github.com/Vishnu1805/TASK-MANAGER.git
              cd app
              npm install
              npx expo start
              EOF

  tags = {
    Name = "webapp-ec2"
  }
}

############################
# 4. S3 BUCKET (STATIC FILES)
############################

resource "aws_s3_bucket" "static_bucket" {
  bucket = "webapp-static-${random_id.bucket_suffix.hex}"
  acl    = "public-read"
  tags   = { Name = "webapp-static" }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

############################
# 5. RDS (MYSQL DATABASE)
############################

resource "aws_db_instance" "web_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = "webappdb"
  username             = "admin"
  password             = var.db_password
  publicly_accessible  = false
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  db_subnet_group_name = aws_db_subnet_group.web_db_subnet_group.name

  tags = { Name = "webapp-db" }
}

resource "aws_db_subnet_group" "web_db_subnet_group" {
  name       = "web-db-subnet-group"
  subnet_ids = [aws_subnet.web_subnet.id]
  tags       = { Name = "webapp-db-subnet-group" }
}

############################
# 6. LOAD BALANCER
############################

resource "aws_lb" "web_alb" {
  name               = "webapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.web_subnet.id]
  tags = { Name = "webapp-alb" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "webapp-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.web_vpc.id
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "web_attachment" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web_server.id
  port             = 80
}
