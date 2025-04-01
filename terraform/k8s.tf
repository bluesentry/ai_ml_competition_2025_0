data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [data.aws_route53_zone.public.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

data "aws_region" "this" {}

data "aws_route53_zone" "public" {
  name = var.domain

  private_zone = false
}

locals {
  aws_eks_elb_controller_role_name = "${local.environment}-AmazonEKSLoadBalancerController"

  aws_eks_external_dns_role_name = "${local.environment}-AmazonEKSRoute53ExternalDNS"
}

locals {
  k8s_domains = {
    argo = "argocd-${local.environment}.${var.domain}"
    game = "game-${local.environment}.${var.domain}"
  }

  validation_records = flatten([
    for cert_key, cert in aws_acm_certificate.k8s :
    [
      for dvo in cert.domain_validation_options :
      {
        cert_name = cert_key
        name      = dvo.resource_record_name
        record    = dvo.resource_record_value
        type      = dvo.resource_record_type
      }
    ]
  ])

  validation_records_map = zipmap(
    [for i in range(length(local.validation_records)) : "${local.validation_records[i].cert_name}-${i}"],
    local.validation_records
  )
}

resource "aws_acm_certificate" "k8s" {
  for_each = local.k8s_domains

  domain_name       = each.value
  validation_method = "DNS"

  tags = merge(var.tags, {
    Name = each.value
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_policy" "eks_alb" {
  name = "${var.environment}_alb"
  policy = jsonencode(
    {
      Statement = [
        {
          Action = [
            "iam:CreateServiceLinkedRole",
          ]
          Condition = {
            StringEquals = {
              "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
            }
          }
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action   = "elasticloadbalancing:AddTags"
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "ec2:DescribeAccountAttributes",
            "ec2:DescribeAddresses",
            "ec2:DescribeAvailabilityZones",
            "ec2:DescribeInternetGateways",
            "ec2:DescribeVpcs",
            "ec2:DescribeVpcPeeringConnections",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeInstances",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DescribeTags",
            "ec2:GetCoipPoolUsage",
            "ec2:DescribeCoipPools",
            "elasticloadbalancing:DescribeLoadBalancers",
            "elasticloadbalancing:DescribeListenerAttributes",
            "elasticloadbalancing:DescribeListenerCertificates",
            "elasticloadbalancing:DescribeListeners",
            "elasticloadbalancing:DescribeLoadBalancerAttributes",
            "elasticloadbalancing:DescribeRules",
            "elasticloadbalancing:DescribeSSLPolicies",
            "elasticloadbalancing:DescribeTags",
            "elasticloadbalancing:DescribeTargetGroupAttributes",
            "elasticloadbalancing:DescribeTargetGroups",
            "elasticloadbalancing:DescribeTargetHealth",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "cognito-idp:DescribeUserPoolClient",
            "acm:ListCertificates",
            "acm:DescribeCertificate",
            "iam:ListServerCertificates",
            "iam:GetServerCertificate",
            "waf-regional:GetWebACL",
            "waf-regional:GetWebACLForResource",
            "waf-regional:AssociateWebACL",
            "waf-regional:DisassociateWebACL",
            "wafv2:GetWebACL",
            "wafv2:GetWebACLForResource",
            "wafv2:AssociateWebACL",
            "wafv2:DisassociateWebACL",
            "shield:GetSubscriptionState",
            "shield:DescribeProtection",
            "shield:CreateProtection",
            "shield:DeleteProtection",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:RevokeSecurityGroupIngress",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "ec2:CreateSecurityGroup",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "ec2:CreateTags",
          ]
          Condition = {
            Null = {
              "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
            }
            StringEquals = {
              "ec2:CreateAction" = "CreateSecurityGroup"
            }
          }
          Effect   = "Allow"
          Resource = "arn:aws:ec2:*:*:security-group/*"
        },
        {
          Action = [
            "ec2:CreateTags",
            "ec2:DeleteTags",
          ]
          Condition = {
            Null = {
              "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
              "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
            }
          }
          Effect   = "Allow"
          Resource = "arn:aws:ec2:*:*:security-group/*"
        },
        {
          Action = [
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:RevokeSecurityGroupIngress",
            "ec2:DeleteSecurityGroup",
          ]
          Condition = {
            Null = {
              "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
            }
          }
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "elasticloadbalancing:CreateLoadBalancer",
            "elasticloadbalancing:CreateTargetGroup",
          ]
          Condition = {
            Null = {
              "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
            }
          }
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "elasticloadbalancing:CreateListener",
            "elasticloadbalancing:DeleteListener",
            "elasticloadbalancing:CreateRule",
            "elasticloadbalancing:DeleteRule",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "elasticloadbalancing:AddTags",
            "elasticloadbalancing:RemoveTags",
          ]
          Condition = {
            Null = {
              "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
              "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
            }
          }
          Effect = "Allow"
          Resource = [
            "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
            "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
            "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
          ]
        },
        {
          Action = [
            "elasticloadbalancing:AddTags",
            "elasticloadbalancing:RemoveTags",
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
            "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
            "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
            "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
          ]
        },
        {
          Action = [
            "elasticloadbalancing:ModifyLoadBalancerAttributes",
            "elasticloadbalancing:SetIpAddressType",
            "elasticloadbalancing:SetSecurityGroups",
            "elasticloadbalancing:SetSubnets",
            "elasticloadbalancing:DeleteLoadBalancer",
            "elasticloadbalancing:ModifyTargetGroup",
            "elasticloadbalancing:ModifyTargetGroupAttributes",
            "elasticloadbalancing:DeleteTargetGroup",
          ]
          Condition = {
            Null = {
              "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
            }
          }
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "elasticloadbalancing:RegisterTargets",
            "elasticloadbalancing:DeregisterTargets",
          ]
          Effect   = "Allow"
          Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
          Action = [
            "elasticloadbalancing:SetWebAcl",
            "elasticloadbalancing:ModifyListener",
            "elasticloadbalancing:AddListenerCertificates",
            "elasticloadbalancing:RemoveListenerCertificates",
            "elasticloadbalancing:ModifyRule",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
      Version = "2012-10-17"
  })
}

resource "aws_iam_policy" "external_dns" {
  name = local.aws_eks_external_dns_role_name

  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_iam_role" "AmazonEKSLoadBalancerControllerRole" {
  name = local.aws_eks_elb_controller_role_name

  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
              "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            }
          }
          Effect = "Allow"
          Principal = {
            Federated = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:oidc-provider/${module.eks.oidc_provider}"
          }
        },
      ]
      Version = "2012-10-17"
    }
  )

  tags = var.tags
}

resource "aws_iam_role" "external_dns" {
  name = local.aws_eks_external_dns_role_name

  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
              "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:external-dns"
            }
          }
          Effect = "Allow"
          Principal = {
            Federated = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:oidc-provider/${module.eks.oidc_provider}"
          }
        },
      ]
      Version = "2012-10-17"
    }
  )

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "AmazonEKSLoadBalancerController" {
  policy_arn = aws_iam_policy.eks_alb.arn
  role       = aws_iam_role.AmazonEKSLoadBalancerControllerRole.name
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}

resource "aws_route53_record" "k8s_verify" {
  for_each = local.validation_records_map

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.public.zone_id
}