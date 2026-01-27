##############################################
# EKS Data + Auth
##############################################

data "aws_caller_identity" "current" {}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Using the module output ensures the provider waits for the cluster to exist
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

##############################################
# EKS Control Plane + Node Groups
##############################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.32"

  # REQUIRED: This tells EKS to use the new Access Entry API 
  authentication_mode                         = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions    = true
  cluster_endpoint_public_access             = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnets
  control_plane_subnet_ids = var.private_subnets

  # ... (Keep your existing Add-ons and Node Group config as is) ...

  ##############################################
  # Access entries - Fixed for Pipeline Auth
  ##############################################
  access_entries = {
    # 1. THE FIX: Automatically add the current runner (Local or Pipeline)
    current_caller = {
      principal_arn     = data.aws_caller_identity.current.arn
      kubernetes_groups = ["eks-admins"]
      policy_associations = [
        {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      ]
    }

    # 2. Your specific user for local fallback
    Shollz-demo = {
      kubernetes_groups = ["eks-admins"]
      principal_arn     = "arn:aws:iam::805703880776:user/Shollz-demo"
      policy_associations = [
        {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      ]
    }

    # 3. Your specific runner role
    github_runner = {
      kubernetes_groups = ["eks-admins"]
      principal_arn     = "arn:aws:iam::805703880776:role/github-runner-ssm-role"
      policy_associations = [
        {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      ]
    }
  }

  tags = local.common_tags
}

##############################################
# RBAC Bindings & Namespaces
##############################################

# We use the module output for depends_on to ensure access_entries are created first
resource "kubernetes_namespace_v1" "fintech" {
  metadata {
    name = "fintech"
  }
  depends_on = [module.eks]
}

# ... (Repeat for other namespaces and bindings) ...