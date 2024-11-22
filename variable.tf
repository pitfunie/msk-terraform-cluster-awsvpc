variable latest_ami_id {
  type = string
  default = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

variable msk_kafka_version {
  type = string
  default = "3.5.1"
}

variable tls_mutual_authentication {
  description = "Whether TLS Mutual Auth should be enabled for the Amazon MSK cluster."
  type = string
  default = true
}

variable workshop_studio_aws_account {
  description = "Running the Workshop at an AWS Guided Event."
  type = string
  default = false
}

