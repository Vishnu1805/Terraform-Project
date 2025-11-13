output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web_server.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.web_server.public_dns
}

output "load_balancer_dns" {
  description = "Public DNS name of the Load Balancer"
  value       = aws_lb.web_alb.dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket for static files"
  value       = aws_s3_bucket.static_bucket.bucket
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.web_db.endpoint
}
