# Remote state — one state file per environment.
#
# Initialize with the correct key for your environment:
#
#   terraform init \
#     -backend-config="key=dev/terraform.tfstate"        # dev
#     -backend-config="key=staging/terraform.tfstate"    # staging
#     -backend-config="key=prod/terraform.tfstate"       # prod
#
# The bucket and DynamoDB table must be created BEFORE running terraform init.
# See the bootstrap script in the repo README for one-time setup instructions.

terraform {
  backend "s3" {
    bucket         = "platform-terraform-state-v1"   # replace with your bucket name
    region         = "eu-central-1"
    dynamodb_table = "platform-terraform-locks-v1"
    encrypt        = true
    # key is provided at init time via -backend-config="key=<env>/terraform.tfstate"
  }
}
