locals {
  account_id = data.aws_caller_identity.this.account_id

  availability_zones = [
    data.aws_availability_zones.main.names[0],
    data.aws_availability_zones.main.names[1],
    data.aws_availability_zones.main.names[2],
  ]

  database_subnets = [
    cidrsubnet(var.vpc_cidr, 6, 7),
    cidrsubnet(var.vpc_cidr, 6, 8),
    cidrsubnet(var.vpc_cidr, 6, 9),
  ]

  environment = replace(var.environment, "_", "-")
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 6, 4),
    cidrsubnet(var.vpc_cidr, 6, 5),
    cidrsubnet(var.vpc_cidr, 6, 6),
  ]

  public_subnets = [
    cidrsubnet(var.vpc_cidr, 6, 0),
    cidrsubnet(var.vpc_cidr, 6, 1),
    cidrsubnet(var.vpc_cidr, 6, 2),
  ]

  vpc_route_tables = flatten([
    module.vpc.private_route_table_ids,
    module.vpc.public_route_table_ids,
  ])
}
