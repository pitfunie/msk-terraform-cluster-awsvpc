locals {
  mappings = {
    AssetsBucketMap = {
      us-east-1 = {
        BucketName = "ws-assets-prod-iad-r-iad-ed304a55c2ca1aee"
      }
      us-east-2 = {
        BucketName = "ws-assets-prod-iad-r-cmh-8d6e9c21a4dec77d"
      }
      us-west-1 = {
        BucketName = "ws-assets-prod-iad-r-sfo-f61fc67057535f1b"
      }
      us-west-2 = {
        BucketName = "ws-assets-prod-iad-r-pdx-f3b3f9f1a7d6a3d0"
      }
    }
  }
  MTLS = var.tls_mutual_authentication == true
  noMTLS = var.tls_mutual_authentication == false
  WorkshopStudioAWSAccount = var.workshop_studio_aws_account == true
  OwnAWSAccount = var.workshop_studio_aws_account == false
  stack_name = "msk"
}

