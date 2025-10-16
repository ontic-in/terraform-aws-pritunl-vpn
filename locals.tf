locals {
  tags = merge(
    {
      "Environment" = var.environment,
      "Terraform"   = "true"
    },
    var.tags
  )

  # Base name construction
  base_name = format("%s-%s-%s", var.prefix, var.environment, "vpn")

  # Intelligent name truncation to fit AWS 32-character limit for load balancers
  # NLB names need room for suffixes like "-public-lb" (11 chars) or "-private-lb" (12 chars)
  # Target group names need room for "-public-0" (9 chars) or "-private-0" (10 chars)
  # We'll use max 20 characters for base name to ensure all resources fit
  name_max_length = 20

  # Truncate intelligently: if name is too long, use abbreviations
  name = length(local.base_name) <= local.name_max_length ? local.base_name : (
    # For long names, abbreviate environment and truncate prefix
    format("%s-%s-vpn",
      substr(var.prefix, 0, min(length(var.prefix), local.name_max_length - length(var.environment) - 5)),
      substr(var.environment, 0, 3) # "integration" -> "int", "production" -> "pro"
    )
  )

  profile_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess"]
  security_group_ids  = concat(var.additional_sg_attacment_ids, var.is_create_security_group ? [aws_security_group.this[0].id] : [])

  vpc_zone_identifier = var.is_create_lb ? var.private_subnet_ids : var.public_subnet_ids

  console_rule = [{
    port                  = 443,
    protocol              = "TCP"
    health_check_protocol = "TCP"
  }]
  public_rule              = concat(var.public_rule, var.is_enabled_https_public ? local.console_rule : [])
  private_rule             = concat(var.private_rule, local.console_rule)
  default_https_allow_cidr = var.is_enabled_https_public ? ["0.0.0.0/0"] : [data.aws_vpc.this.cidr_block]

  # Dynamically generate security group rules based on NLB listener ports
  # This allows access from anywhere (0.0.0.0/0) but only on the specific ports used by listeners
  dynamic_listener_rules = merge(
    # Rules for public NLB listeners (if enabled)
    var.is_create_lb ? {
      for idx, rule in local.public_rule :
      "allow_public_listener_${rule.port}_${lower(rule.protocol)}" => {
        port        = rule.port
        protocol    = lower(rule.protocol)
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow access to public NLB listener on port ${rule.port}/${upper(rule.protocol)}"
      }
    } : {},
    # Rules for private NLB listeners (if enabled)
    var.is_create_private_lb ? {
      for idx, rule in local.private_rule :
      "allow_private_listener_${rule.port}_${lower(rule.protocol)}" => {
        port        = rule.port
        protocol    = lower(rule.protocol)
        cidr_blocks = ["0.0.0.0/0"]
        description = "Allow access to private NLB listener on port ${rule.port}/${upper(rule.protocol)}"
      }
    } : {}
  )

  security_group_ingress_rules = merge(
    # Dynamic rules based on NLB listeners
    local.dynamic_listener_rules,
    # NFS access for EFS (self-referencing)
    {
      allow_nfs_from_self = {
        port                     = "2049"
        protocol                 = "tcp"
        source_security_group_id = var.is_create_security_group ? aws_security_group.this[0].id : null
        description              = "NFS access for EFS mount targets"
      }
    },
    # User-provided custom rules (highest precedence)
    var.security_group_ingress_rules
  )

  network_interfaces = var.is_create_lb ? [] : [{
    associate_public_ip_address = true
    security_groups             = local.security_group_ids
  }]

  vpc_security_group_ids = var.is_create_lb ? local.security_group_ids : []

}
