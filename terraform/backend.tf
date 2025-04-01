terraform {
  backend "s3" {
    bucket = "bsc.sandbox.terraform.state"
    key    = "ai_ml_competition_2025_0/terraform.tfstate"
    region = "us-east-2"

    use_lockfile = true
  }
}
