
terraform {
  required_version = ">= 0.12"

  # vars are not allowed in this block
  # see: https://github.com/hashicorp/terraform/issues/22088
  backend "s3" {}
}

provider "aws" {
  region  = var.region
  access_key = var.aws_key
  secret_key = var.aws_secret
}

output "sns_topic_arn" {
  value = "test"
}
