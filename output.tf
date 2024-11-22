output "msk_security_group_id" {
  description = "The ID of the security group created for the MSK clusters"
  value = aws_security_group.msk_security_group.id
}

output "ssh_kafka_client_ec2_instance" {
  description = "SSH command for Kafka the EC2 instance"
  value = "ssh -A ec2-user@${aws_ec2_instance_state.kafka_client_ec2_instance.state}"
}

output "kafka_client_ec2_instance_security_group_id" {
  description = "The security group id for the EC2 instance"
  value = aws_security_group.kafka_client_instance_security_group.id
}

output "schema_registry_url" {
  description = "The url for the Schema Registry"
  value = "http://${aws_ec2_instance_state.kafka_client_ec2_instance.state}:8081"
}

output "msk_cluster_arn" {
  description = "The Arn for the MSKMMCluster1 MSK cluster"
  value = local.MTLS ? aws_msk_cluster.msk_cluster_mtls[0].arn : aws_msk_cluster.msk_cluster_no_mtls[0].arn
}

output "vpc_stack_name" {
  description = "The name of the VPC Stack"
  value = aws_cloudformation_stack.mskvpc_stack.outputs.VPCStackName
}

