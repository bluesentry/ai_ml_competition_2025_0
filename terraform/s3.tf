data "aws_kms_key" "aws_s3" {
  key_id = "alias/aws/s3"
}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.6.0"

  bucket        = "first-order-application-logs"
  force_destroy = true
  tags          = var.tags

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = data.aws_kms_key.aws_s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}