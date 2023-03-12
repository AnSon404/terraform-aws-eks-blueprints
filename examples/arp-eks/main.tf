provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

locals {
  name   = "arp-airflow-poc"
  region = "ap-east-1"

  vpc_cidr = "172.16.0.0/16"
  azs = ["ap-east-1a", "ap-east-1b", "ap-east-1c"]

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

  cluster_endpoint_public_access = false
  cluster_endpoint_private_access = true

  # EKS Addons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }
  /*
  map_roles_count = 1
  map_roles = [
    {
      rolearn  = aws_iam_role.bastion_iam_role.arn
      username = "kubectl"
      groups   = ["system:masters"]
    },
  ]
  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  */
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.eks[*].id

    eks_managed_node_groups = {
    eks-worker-node = {
      instance_types = ["t3.medium"]
      min_size     = 2
      max_size     = 3
      desired_size = 2
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Addons
################################################################################

module "eks_blueprints_kubernetes_addons" {
  source = "../../modules/kubernetes-addons"

  eks_cluster_id       = module.eks.cluster_name
  eks_cluster_endpoint = module.eks.cluster_endpoint
  eks_oidc_provider    = module.eks.oidc_provider
  eks_cluster_version  = module.eks.cluster_version

  # Add-ons
  enable_airflow = true
  
  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

resource "aws_vpc" "this" {
  tags = merge(
    local.tags,
    {
      Name = "arp-airflow-poc-vpc"
    },
  )
  cidr_block = local.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = "${local.azs[count.index]}"
  map_public_ip_on_launch = true
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-public-subnet"
    },
  )
}

resource "aws_subnet" "file" {
  count = length(var.file_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.file_subnet_cidrs[count.index]
  availability_zone       = "${local.azs[count.index]}"
  map_public_ip_on_launch = false
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-file-subnet-${local.azs[count.index]}"
    },
  )
}

resource "aws_subnet" "db" {
  count = length(var.db_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.db_subnet_cidrs[count.index]
  availability_zone       = "${local.azs[count.index]}"
  map_public_ip_on_launch = false
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-db-subnet-${local.azs[count.index]}"
    },
  )
}

resource "aws_subnet" "eks" {
  count = length(var.db_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.eks_subnet_cidrs[count.index]
  availability_zone       = "${local.azs[count.index]}"
  map_public_ip_on_launch = false
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-eks-subnet-${local.azs[count.index]}"
    },
  )
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.this.id
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-internet-gateway"
    },
  )
}

resource "aws_route_table" "public_rt" {
 vpc_id = aws_vpc.this.id
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 tags = merge(
    local.tags,
    {
      Name = "${local.name}-public-subnet-route-table"
    },
  )
}
resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_subnet_cidrs)
 subnet_id      = element(aws_subnet.public[*].id, count.index)
 route_table_id = aws_route_table.public_rt.id
}

# Charges may occur
# Reserve EIPs
resource "aws_eip" "nat" {
  vpc = true
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-nat-eip"
    },
  )
}

resource "aws_nat_gateway" "zone_a" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(
    local.tags,
    {
      Name = "${local.name}-nat-gateway"
    },
  )
  depends_on = [
    aws_subnet.public
  ]
}

resource "aws_route_table" "file_rt" {
 vpc_id = aws_vpc.this.id
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_nat_gateway.zone_a.id
 }
 tags = merge(
    local.tags,
    {
      Name = "${local.name}-file-subnet-route-table"
    },
  )
}
resource "aws_route_table_association" "file_subnet_asso" {
 count = length(var.file_subnet_cidrs)
 subnet_id      = element(aws_subnet.file[*].id, count.index)
 route_table_id = aws_route_table.file_rt.id
}

resource "aws_route_table" "db_rt" {
 vpc_id = aws_vpc.this.id
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_nat_gateway.zone_a.id
 }
 tags = merge(
    local.tags,
    {
      Name = "${local.name}-db-subnet-route-table"
    },
  )
}
resource "aws_route_table_association" "db_subnet_asso" {
 count = length(var.db_subnet_cidrs)
 subnet_id      = element(aws_subnet.db[*].id, count.index)
 route_table_id = aws_route_table.db_rt.id
}

resource "aws_route_table" "eks_rt" {
 vpc_id = aws_vpc.this.id
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_nat_gateway.zone_a.id
 }
 tags = merge(
    local.tags,
    {
      Name = "${local.name}-eks-subnet-route-table"
    },
  )
}
resource "aws_route_table_association" "eks_subnet_asso" {
 count = length(var.eks_subnet_cidrs)
 subnet_id      = element(aws_subnet.eks[*].id, count.index)
 route_table_id = aws_route_table.eks_rt.id
}

# Create Bastion EC2 at Public Subnet
# Generates a secure private key and encodes it as PEM
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# Create the Key Pair
resource "aws_key_pair" "key_pair" {
  key_name   = "${local.name}-key-pair"
  public_key = tls_private_key.key_pair.public_key_openssh
}
# Save file
resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.key_pair.key_name}.pem"
  content  = tls_private_key.key_pair.private_key_pem
}
# security group of Bastion
resource "aws_security_group" "bastion_sg" {
  name        = "${local.name}-bastion-sg"
  description = "Allow incoming traffic to the Linux EC2 Instance"
  vpc_id      = aws_vpc.this.id
  ingress {
    description = "Allow incoming HTTP connections"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming SSH connections"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.tags
}
# IAM role for Bastion
resource "aws_iam_instance_profile" "test" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.bastion_iam_role.name
}
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "bastion_iam_role" {
  name               = "${local.name}-bastion-iam-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
data "aws_iam_policy_document" "eks" {
  statement {
    effect    = "Allow"
    actions   = [
                "eks:DescribeCluster",
                "eks:ListClusters"
                ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "eks" {
  name        = "${local.name}-eks-policy"
  description = "A eks policy"
  policy      = data.aws_iam_policy_document.eks.json
}
resource "aws_iam_role_policy_attachment" "eks" {
  role       = aws_iam_role.bastion_iam_role.name
  policy_arn = aws_iam_policy.eks.arn
}
# launch Bastion
data "aws_ami" "amazon-linux-2" {
 most_recent = true
 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }
 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}
resource "aws_instance" "test" {
 ami                         = "${data.aws_ami.amazon-linux-2.id}"
 associate_public_ip_address = true
 iam_instance_profile        = "${aws_iam_instance_profile.test.id}"
 instance_type               = "t3.micro"
 key_name                    = aws_key_pair.key_pair.key_name
 vpc_security_group_ids      = ["${aws_security_group.bastion_sg.id}"]
 subnet_id                   = aws_subnet.public[0].id
 root_block_device {
    volume_size           = 8
    volume_type           = "gp2"
    delete_on_termination = true
    encrypted             = true
  }
  tags = merge(
    local.tags,
    {
      Name = "arp-airflow-poc-bastion-ec2"
    },
  )
}