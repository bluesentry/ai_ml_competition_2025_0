# 2025 | Season 1: AI-Assisted CI/CD Optimization

## Overview
This competition challenges teams to integrate AI/ML techniques into CI/CD pipelines, optimizing performance, improving failure analysis, and enhancing log summarization. Teams will work on a predefined GitHub repository and follow an agile sprint structure to iteratively develop their solutions.

### Competition Duration
- **Total Duration:** 2.5 months (5 sprints)
- **Sprint Length:** 2 weeks per sprint
- **Final Deliverable:** A working solution presented in a live demo, including cost considerations.
- **Start Date:** March 17, 2025
- **End Date:** May 30, 2025

## Repository Structure
```
.
├── docker
│   └── game
├── img
├── k8s
│   ├── devops
│   │   ├── Chart.yaml
│   │   ├── templates
│   │   └── values.yaml
│   ├── master
│   │   ├── Chart.yaml
│   │   ├── templates
│   │   └── values.yaml
│   └── microservices
│       ├── Chart.yaml
│       ├── templates
│       └── values.yaml
├── README.md
└── terraform
    ├── backend.tf
    ├── ecr.tf
    ├── eks.tf
    ├── github_secrets.tf
    ├── k8s.tf
    ├── local.tf
    ├── oidc_provider.tf
    ├── output.tf
    ├── plan.out
    ├── terraform.tfvars
    ├── variables.tf
    ├── versions.tf
    └── vpc.tf
```

## Setup Instructions

### 1. Set Up Terraform
Terraform is required to set up the EKS cluster and supporting AWS infrastructure.

```bash
# Initialize Terraform
cd terraform
terraform init

# Validate Terraform configuration
terraform validate

# Plan the deployment
terraform plan -out=plan.out

# Apply Terraform configuration
terraform apply plan.out
```

### 2. Install ArgoCD with Helm
ArgoCD will be used for managing deployments within Kubernetes.

```bash
# Add the ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with insecure mode for ALB access
helm install argo-cd argo/argo-cd --namespace argocd --create-namespace --set server.extraArgs={--insecure}
```

### 3. Deploy ArgoCD Applications
Once ArgoCD is installed, deploy the initial set of applications.

```bash
# Navigate to the k8s master directory
cd ../k8s/master

# Deploy all ArgoCD applications
helm template . | kubectl apply -f -
```

## Rewards and Recognition
🏆 **First Place:** $500

🥈 **Second Place:** $200

🥉 **Third Place:** $100

- Winners earn the internal title **"DevOps AI Master"** for the quarter.
- **First Place** winners earn a **public badge** for "DevOps AI Winner."
- All projects will be showcased in lightning talks.

## Participating Teams

### Storm Troopers
- Dallin Rasmuson
- Ryan Young
- Blake Warner
- Mahmood Rahimi
- Brandon DeLallo
- Jonathan Leaver

**Focus:** Failure Analysis & Root Cause Detection

### Autom8s
- Mike Olivieri
- Robbie Douglas
- Stefan Dalecki
- Caleb Cohen
- Steffan Williams

**Focus:** Build Performance Optimization

### Team Vader
- Andrew Deweever
- Tyler Jenkins
- Max Bado
- Niraj Visana
- Ashley Ellis
- Trey Buckingham

**Focus:** Build Performance Optimization

### First Order
- Andrew Huddleston
- Will Ahlborn
- Mo Banjo
- Scott Griffith
- Khane Mitchell

**Focus:** AI-Driven Log Summarization
