/*
  ALB / AWS Load Balancer Controller - Terraform placeholder & instructions

  This file contains instructions and a minimal example to create the IAM role
  for the AWS Load Balancer Controller via the cluster OIDC provider. Installing
  the controller requires:
    1) An IAM role with a trust relation to the EKS cluster OIDC provider
    2) A policy with the permissions the controller needs
    3) A Kubernetes ServiceAccount bound to that role (via IRSA)
    4) Helm install of the controller chart

  Notes:
  - We do not run Terraform apply here automatically. This file documents the
    recommended steps and provides a small example you can adapt into your
    environment.
  - If you'd like, I can convert these into a full Terraform module that
    creates the policy document and role (requires adding the full managed
    policy JSON). For now this is a safe, non-destructive guidance file.

  Quick manual steps (recommended for first run):
  - Create IAM OIDC provider (if not present):
      aws eks describe-cluster --name <cluster-name> --query "cluster.identity.oidc.issuer" --output text
      aws iam create-open-id-connect-provider --url <oidc-url> --client-id-list sts.amazonaws.com --thumbprint-list <thumbprint>

  - Create IAM role for service account (example using eksctl):
      eksctl create iamserviceaccount \
        --cluster=<cluster-name> \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn=arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy \
        --approve

  - Install the controller with Helm (example):
      helm repo add eks https://aws.github.io/eks-charts
      helm repo update
      helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system --create-namespace \
        --set clusterName=<cluster-name> \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller

  If you want a Terraform-native implementation, I can add a module that
  creates the IAM role, inlines the required policy (sourced from AWS docs),
  and optionally creates the Kubernetes service account via the Kubernetes
  provider (using the cluster kubeconfig output).

*/

/* Example Terraform module invocation (commented) - adapt to your environment:
module "alb" {
  source = "../../modules/alb"
  cluster_name = module.eks.cluster_name
  oidc_provider = module.eks.oidc_provider_url
  region = "ap-south-1"
}

*/
