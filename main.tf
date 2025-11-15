############################
# 1. NETWORKING (VPC, SUBNET, INTERNET)
############################
resource "aws_vpc" "web_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "webapp-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id

  tags = {
    Name = "webapp-igw"
  }
}

# Public Route Table
resource "aws_route_table" "web_rt" {
  vpc_id = aws_vpc.web_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }

  tags = {
    Name = "webapp-rt"
  }
}

# Subnet in AZ 1
resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "webapp-subnet-1"
  }
}

# Subnet in AZ 2
resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.web_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "webapp-subnet-2"
  }
}

# Associate subnets with Route Table
resource "aws_route_table_association" "subnet_1_assoc" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.web_rt.id
}

resource "aws_route_table_association" "subnet_2_assoc" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.web_rt.id
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

  ingress {
  description = "Allow app traffic (port 8081)"
  from_port   = 8081
  to_port     = 8081
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}


  tags = { Name = "webapp-sg" }
}

############################
# 3. EC2 INSTANCE
############################

resource "aws_instance" "web_server" {
  ami                         = "ami-03695d52f0d883f65" # Amazon Linux 2 (ap-south-1)
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

user_data = <<-EOF
#!/bin/bash
yum update -y

# Install dependencies
yum install -y git nodejs npm

#!/bin/bash

# Step 1: Clone the repository
cd /home/ec2-user
git clone https://github.com/Vishnu1805/TASK-MANAGER.git
cd TASK-MANAGER

# Step 2: Install Node.js dependencies
npm install

# Step 3: Build the Expo web app
sudo npx expo export --platform web

# Step 4: Install NGINX
sudo dnf install nginx -y  

# Step 5: Remove default NGINX content and copy web build files
sudo rm -rf /usr/share/nginx/html/*      
sudo cp -r dist/* /usr/share/nginx/html/ 

# Step 6: Restart NGINX to apply changes
sudo systemctl restart nginx

# Step 7: Enable and start NGINX
sudo systemctl enable nginx
sudo systemctl start nginx

# Step 8: Check NGINX status
sudo systemctl status nginx
EOF

  tags = {
    Name = "webapp-ec2"
  }
}

############################
# 4. S3 BUCKET (STATIC FILES)
############################
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create S3 Bucket
resource "aws_s3_bucket" "static_bucket" {
  bucket = "webapp-static-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "webapp-static"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_ownership_controls" "static_bucket" {
  bucket = aws_s3_bucket.static_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "static_bucket" {
  bucket = aws_s3_bucket.static_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "static_bucket_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.static_bucket,
    aws_s3_bucket_public_access_block.static_bucket
  ]
  bucket = aws_s3_bucket.static_bucket.id
  acl    = "public-read"
}

############################
# 5. RDS (MYSQL DATABASE)
############################

resource "aws_db_subnet_group" "web_db_subnet_group" {
  name       = "web-db-subnet-group"
  subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  tags       = { Name = "webapp-db-subnet-group" }
}

resource "aws_db_instance" "web_db" {
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  db_name                 = "webappdb"
  username                = "admin"
  password                = var.db_password
  publicly_accessible     = false
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.web_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.web_db_subnet_group.name

  tags = { Name = "webapp-db" }
}

############################
# 6. LOAD BALANCER
############################

resource "aws_lb" "web_alb" {
  name               = "webapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [
    aws_subnet.subnet_1.id,
    aws_subnet.subnet_2.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "webapp-alb"
  }
}

resource "aws_lb_target_group" "web_tg" {
  name        = "webapp-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.web_vpc.id
  target_type = "instance"

  health_check {
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = {
    Name = "webapp-tg"
  }
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
