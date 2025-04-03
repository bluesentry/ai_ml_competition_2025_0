# Retrieve existing OIDC Provider for GitHub Actions
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_ai_ml_role" {
  name = var.github_actions_oidc_role

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : data.aws_iam_openid_connect_provider.github_actions.arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            # Adjust the repository identifier to match your GitHub org and repo.
            "token.actions.githubusercontent.com:sub" : "repo:bluesentry/first-order-season-1:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_workflow" {
  name = "github-actions-workflow-policy"
  role = aws_iam_role.github_actions_ai_ml_role.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ECRPushPermissions",
        "Effect" : "Allow",
        "Action" : [
          "ecr:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "EKSPermissions",
        "Effect" : "Allow",
        "Action" : [
          "eks:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Route53Permissions",
        "Effect" : "Allow",
        "Action" : [
          "route53:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "LoadBalancerPermissions",
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "S3Permissions",
        "Effect" : "Allow",
        "Action" : [
          "s3:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "S3StateBucketPermissions",
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:HeadObject"
        ],
        "Resource" : [
          "arn:aws:s3:::bsc.sandbox.terraform.state",
          "arn:aws:s3:::bsc.sandbox.terraform.state/*"
        ]
      },
      {
        "Sid" : "S3DeleteObjectPermission",
        "Effect" : "Allow",
        "Action" : [
          "s3:DeleteObject"
        ],
        "Resource" : [
          "arn:aws:s3:::bsc.sandbox.terraform.state/ai_ml_competition_2025_0/terraform.tfstate.tflock",
          "arn:aws:s3:::bsc.sandbox.terraform.state/ai_ml_competition_2025_0/terraform.tfstate"
        ]
      },

      {
        "Sid" : "ECRPermissions",
        "Effect" : "Allow",
        "Action" : [
          "ecr:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "DynamoDBPermissions",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "IAMPermissions",
        "Effect" : "Allow",
        "Action" : [
          "iam:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "SSMPermissions",
        "Effect" : "Allow",
        "Action" : [
          "ssm:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "ACMPermissions",
        "Effect" : "Allow",
        "Action" : [
          "acm:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "EC2Permissions",
        "Effect" : "Allow",
        "Action" : [
          "ec2:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "LogPermissions",
        "Effect" : "Allow",
        "Action" : [
          "logs:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "KmsPermissions",
        "Effect" : "Allow",
        "Action" : [
          "kms:*"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "RDSPermissions",
        "Effect" : "Allow",
        "Action" : [
          "rds:*"
        ],
        "Resource" : "*"
      }


    ]
  })
}


# Fluent Bit IRSA Role
resource "aws_iam_role" "fluentbit" {
  name = "eks-fluentbit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(module.eks.oidc_provider_arn, "arn:aws:iam::${data.aws_caller_identity.this.account_id}:oidc-provider/", "")}:sub" = "system:serviceaccount:logging:fluentbit"
          }
        }
      }
    ]
  })
}


resource "aws_iam_policy" "fluentbit_s3_write" {
  name = "FluentBitS3Policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "AllowS3Put",
        Effect : "Allow",
        Action : ["s3:PutObject", "s3:PutObjectAcl"],
        Resource : "arn:aws:s3:::first-order-application-logs/*"
      },
      {
        Sid : "AllowKMSDecrypt",
        Effect : "Allow",
        Action : ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"],
        Resource : data.aws_kms_key.aws_s3.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fluentbit_attach_s3_write" {
  role       = aws_iam_role.fluentbit.name
  policy_arn = aws_iam_policy.fluentbit_s3_write.arn
}
