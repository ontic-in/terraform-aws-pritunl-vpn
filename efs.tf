# EFS - Custom implementation without module to avoid unwanted policies and access points
# This configuration creates a plain EFS with no IAM policy and no access points
# Compatible with plain NFS4 mount without requiring EFS helper or IAM authentication

locals {
  efs_name = "${var.prefix}-${var.environment}-pritunl-data"
  # Use EC2 security group directly for EFS mount targets
  # This allows EC2 instances to access EFS using their own security group
  efs_security_groups = var.is_create_security_group ? [aws_security_group.this[0].id] : []
}

# EFS File System - encrypted but no IAM policy
resource "aws_efs_file_system" "pritunl" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = merge({
    Name = "${local.efs_name}-efs"
  }, local.tags)

  lifecycle {
    prevent_destroy = false
  }
}

# EFS Mount Targets - one per subnet
# Uses the EC2 security group directly - no separate EFS security group needed
# The EC2 security group allows all traffic within itself (self-referencing)
resource "aws_efs_mount_target" "pritunl" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.pritunl.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = local.efs_security_groups
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
