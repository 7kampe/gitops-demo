terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.6.0"
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}


module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "gitops-lab-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  map_public_ip_on_launch = true

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Environment = "lab"
    Project     = "aws-gitops-lab"
  }
}

# module "ebs_csi_irsa_role" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
#   version = "~> 6.0"

  
#   attach_ebs_csi_policy = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
#     }
#   }
# }

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni = {
      before_compute = true
    }
    # aws-ebs-csi-driver = { most_recent = true

    # }
  }

  # Optional
  endpoint_public_access = true


  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true


  eks_managed_node_groups = {
    lab = {
      desired_size = 1
      max_size     = 1
      min_size     = 1

      instance_types = ["t3.medium"]
      network_interfaces = [{
        associate_public_ip_address = true
      }]

    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  tags = {
    Environment = "lab"
    Project     = "aws-gitops-lab"
  }
}
