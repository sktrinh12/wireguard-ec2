provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

provider "aws" {
  alias   = "bucket"
  region  = var.bucket_region
  profile = var.aws_profile
}
