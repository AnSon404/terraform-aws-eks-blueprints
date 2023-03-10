provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  name   = "arp-airflow-poc"
  region = "ap-east-1"

  vpc_cidr = "172.16.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Environment  = "POC"
    "Created by" = "Nextlink"
    Project = "Airflow"
  }
}

################################################################################
# Cluster
################################################################################

#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.9"

  cluster_name    = "arp-airflow-poc-eks"
  cluster_version = "1.24"

  cluster_endpoint_public_access = {
    type        = bool
    default     = false
  }
  cluster_endpoint_private_access = {
    type        = bool
    default     = true
  }

  # EKS Addons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    enable_airflow = true
    airflow_helm_config = {
      name             = "airflow"
      chart            = "airflow"
      repository       = "https://airflow.apache.org"
      version          = "2.5.1"
      namespace        = module.airflow_irsa.namespace
      create_namespace = false
      timeout          = 360
      description      = "Apache Airflow v2 Helm chart deployment configuration"
      # Check the example for `values.yaml` file
      values = [templatefile("${path.module}/values.yaml", {
        # Airflow Postgres RDS Config
        airflow_db_user = "airflow"
        airflow_db_name = module.db.db_instance_name
        airflow_db_host = element(split(":", module.db.db_instance_endpoint), 0)
        # S3 bucket config for Logs
        s3_bucket_name          = aws_s3_bucket.this.id
        webserver_secret_name   = local.airflow_webserver_secret_name
        airflow_service_account = local.airflow_service_account
      })]

      set_sensitive = [
        {
          name  = "data.metadataConnection.pass"
          value = data.aws_secretsmanager_secret_version.postgres.secret_string
        }
      ]
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    name         = "arp-airflow-poc-eks-node-group"
    instance_types = ["t3.small"]
    min_size     = 2
    max_size     = 3
    desired_size = 2
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]

  enable_nat_gateway   = false
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", module.vpc.private_subnets_cidr_blocks)
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "All egress HTTPS"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 3.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}
