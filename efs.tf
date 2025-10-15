# EFS - Custom implementation without module to avoid unwanted policies and access points
# This configuration creates a plain EFS with no IAM policy and no access points
# Compatible with plain NFS4 mount without requiring EFS helper or IAM authentication

locals {
  service_name = "${var.prefix}-${var.environment}-pritunl-data"
  tags = merge(
    {
      Terraform   = "true"
      Environment = var.environment
    },
    var.tags
  )
}

# EFS File System - encrypted but no IAM policy
resource "aws_efs_file_system" "pritunl" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = merge({
    Name = "${local.service_name}-efs"
  }, local.tags)

  lifecycle {
    prevent_destroy = false
  }
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${local.service_name}-efs-sg"
  description = "Security group for Pritunl EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({
    Name = "${local.service_name}-efs-sg"
  }, local.tags)
}

# EFS Mount Targets - one per subnet
resource "aws_efs_mount_target" "pritunl" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.pritunl.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Backup Policy
resource "aws_efs_backup_policy" "pritunl" {
  count          = var.enabled_backup ? 1 : 0
  file_system_id = aws_efs_file_system.pritunl.id

  backup_policy {
    status = var.efs_backup_policy_enabled ? "ENABLED" : "DISABLED"
  }
}

# NO aws_efs_file_system_policy resource - this allows plain NFS4 mount
# NO aws_efs_access_point resources - this avoids POSIX user enforcement
