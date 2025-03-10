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
            "token.actions.githubusercontent.com:sub" : "repo:bluesentry/ai_ml_competition_2025_0:*"
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