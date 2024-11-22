resource "aws_lambda_function" "kafka_producer_lambda_function" {
  function_name = "kafka-producer-to-serverless-msk"
  description = "Python Kafka Producer"
  runtime = "python3.11"
  timeout = 60
  handler = "index.lambda_handler"
  role = aws_iam_role.kafka_producer_lambda_execution_role.arn
  environment {
    variables = {
      MESSAGE_COUNT = 0
      BOOTSTRAP_SERVER = ""
      TOPIC_NAME = ""
    }
  }
  code_signing_config_arn = {
    ZipFile = "import json
import os
from kafka.admin import KafkaAdminClient, NewTopic
from kafka import KafkaProducer
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
import ssl

MESSAGE_COUNT = os.environ.get('MESSAGE_COUNT')
TOPIC_NAME = os.environ.get('TOPIC_NAME')
BOOTSTRAP_SERVER = os.environ.get('BOOTSTRAP_SERVER')

# Define an event (message) to send
kafka_event = {
    'event_type': 'order_placed',
    'order_id': 123,
    'customer_id': 456,
    'items': [
        {'product_id': 789, 'quantity': 2},
        {'product_id': 101, 'quantity': 1}
    ]
}

class MSKTokenProvider:
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(os.environ["AWS_REGION"])
        return token

def create_topic(token_provider):
    # Create an instance of KafkaAdminClient
    admin_client = KafkaAdminClient(
        bootstrap_servers=BOOTSTRAP_SERVER,
        client_id="topic_creator",
        security_protocol='SASL_SSL',
        sasl_mechanism='OAUTHBEARER',
        sasl_oauth_token_provider=token_provider
    )
    
    # Check if a topic with the same name exists in the MSK Serverless cluster
    existing_topics = admin_client.list_topics()
    if TOPIC_NAME in existing_topics:
        print(f"Topic '{TOPIC_NAME}' is already created")
        return

    # Define the topic configuration
    num_partitions = 3
    replication_factor = 2
    
    # Create a NewTopic object
    topic = NewTopic(
        name=TOPIC_NAME,
        num_partitions=num_partitions,
        replication_factor=replication_factor
    )

    # Create the topic
    admin_client.create_topics(new_topics=[topic], validate_only=False)
    print(f"Topic '{TOPIC_NAME}' created successfully!")
    
    # Close the AdminClient
    admin_client.close()

def lambda_handler(event, context):
    if not TOPIC_NAME or not BOOTSTRAP_SERVER:
        raise ValueError("TOPIC_NAME and BOOTSTRAP_SERVER environment variables must be set")
    
    token_provider = MSKTokenProvider()
    
    create_topic(token_provider)
    
    producer = KafkaProducer(bootstrap_servers=[BOOTSTRAP_SERVER],
                            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                            client_id="event_producer",
                            security_protocol='SASL_SSL',
                            sasl_mechanism='OAUTHBEARER',
                            sasl_oauth_token_provider=token_provider)

    for i in range(int(MESSAGE_COUNT)):
        producer.send(TOPIC_NAME, kafka_event)
    
    print(f"Finished writing '{MESSAGE_COUNT}' messages!")
    return {
        'statusCode': 200,
        'body': json.dumps('Lambda function executed!')
    }
"
  }
  layers = [
    aws_lambda_layer_version.msk_producer_lambda_layer.arn
  ]
  vpc_config {
    security_group_ids = [
      aws_security_group.kafka_client_instance_security_group.arn
    ]
    subnet_ids = [
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKOne,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKTwo,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKThree
    ]
  }
}

resource "aws_lambda_layer_version" "msk_producer_lambda_layer" {
  layer_name = "msk-producer-lambda-layer"
  description = "MSK Kafka Producer Lambda Layer"
  // CF Property(Content) = {
  //   S3Bucket = local.mappings["AssetsBucketMap"][data.aws_region.current.name]["BucketName"]
  //   S3Key = "c2b72b6f-666b-4596-b8bc-bafa5dcca741/producer-dependencies-layer.zip"
  // }
  compatible_runtimes = [
    "python3.11"
  ]
}

resource "aws_iam_role" "kafka_producer_lambda_execution_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
  ]
  force_detach_policies = [
    {
      PolicyName = "MSKAccessPolicy"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "kafka-cluster:Connect",
              "kafka-cluster:DescribeCluster",
              "kafka-cluster:CreateTopic",
              "kafka-cluster:DescribeTopic",
              "kafka-cluster:WriteData"
            ]
            Resource = [
              "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/*",
              "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/*"
            ]
          }
        ]
      }
    }
  ]
}

resource "aws_cloudwatch_event_rule" "kafka_producer_event_bridge_rule" {
  description = "Trigger Kafka Python producer function every minute"
  schedule_expression = "rate(1 minute)"
  state = "DISABLED"
  // CF Property(Targets) = [
  //   {
  //     Arn = aws_lambda_function.kafka_producer_lambda_function.arn
  //     Id = "KafkaProducerLambdaFunction"
  //   }
  // ]
}

resource "aws_lambda_permission" "kafka_producer_event_bridge_rule_permissions" {
  function_name = aws_lambda_function.kafka_producer_lambda_function.arn
  action = "lambda:InvokeFunction"
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.kafka_producer_event_bridge_rule.arn
}

resource "aws_cloudformation_stack" "mskvpc_stack" {
  template_url = "https://aws-streaming-artifacts.s3.amazonaws.com/msk-lab-resources/MSKLabs/MSKPrivateVPCOnly.yml"
}

resource "aws_security_group" "kafka_client_instance_security_group" {
  description = "Enable SSH access via port 22 from BastionHostSecurityGroup"
  vpc_id = aws_cloudformation_stack.mskvpc_stack.outputs.VPCId
  ingress = [
    {
      protocol = "tcp"
      from_port = 22
      to_port = 22
      cidr_blocks = "10.0.0.0/24"
    },
    {
      protocol = "tcp"
      from_port = 3500
      to_port = 3500
      cidr_blocks = "10.0.0.0/24"
    },
    {
      protocol = "tcp"
      from_port = 3600
      to_port = 3600
      cidr_blocks = "10.0.0.0/24"
    },
    {
      protocol = "tcp"
      from_port = 3800
      to_port = 3800
      cidr_blocks = "10.0.0.0/24"
    },
    {
      protocol = "tcp"
      from_port = 3900
      to_port = 3900
      cidr_blocks = "10.0.0.0/24"
    }
  ]
}

resource "aws_vpc_security_group_ingress_rule" "kafka_client_instance_security_group8081" {
  description = "Enable access to Schema Registry inside the KafkaClientInstanceSecurityGroup"
  referenced_security_group_id = aws_security_group.kafka_client_instance_security_group.id
  ip_protocol = "tcp"
  from_port = 8081
  to_port = 8081
  security_group_id = aws_security_group.kafka_client_instance_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "kafka_client_instance_security_group8083" {
  description = "Enable access to Kafka Connect inside the KafkaClientInstanceSecurityGroup"
  referenced_security_group_id = aws_security_group.kafka_client_instance_security_group.id
  ip_protocol = "tcp"
  from_port = 8083
  to_port = 8083
  security_group_id = aws_security_group.kafka_client_instance_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "kafka_client_instance_security_group_lambda" {
  description = "Enable access to Kafka from Kafka Producer Lambda"
  referenced_security_group_id = aws_security_group.kafka_client_instance_security_group.id
  ip_protocol = "tcp"
  from_port = 0
  to_port = 65535
  security_group_id = aws_security_group.kafka_client_instance_security_group.id
}

resource "aws_ec2_instance_state" "kafka_client_ec2_instance" {
  instance_id = aws_iam_instance_profile.ec2_instance_profile.arn
  // CF Property(AvailabilityZone) = element(// Unable to resolve Fn::GetAZs with value: data.aws_region.current.name because cannot access local variable 'az_data' where it is not associated with a value, 0)
  // CF Property(SubnetId) = aws_cloudformation_stack.mskvpc_stack.outputs.PublicSubnetOne
  // CF Property(SecurityGroupIds) = [
  //   aws_security_group.kafka_client_instance_security_group.id
  // ]
  // CF Property(ImageId) = var.latest_ami_id
  // CF Property(BlockDeviceMappings) = [
  //   {
  //     DeviceName = "/dev/xvda"
  //     Ebs = {
  //       VolumeSize = 20
  //       VolumeType = "gp2"
  //       DeleteOnTermination = true
  //     }
  //   }
  // ]
  // CF Property(UserData) = base64encode("#!/bin/bash
  // yum update -y
  // yum install java-1.8.0-openjdk-devel -y
  // yum install nmap-ncat -y
  // yum install git -y
  // yum erase awscli -y
  // yum install jq -y
  // amazon-linux-extras install docker -y
  // amazon-linux-extras install python3.8 -y
  // service docker start
  // usermod -a -G docker ec2-user
  // unlink /usr/bin/python3
  // ln -s /usr/bin/python3.8 /usr/bin/python3
  // sudo wget https://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo
  // sudo sed -i s/\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo
  // sudo yum install -y apache-maven
  // 
  // cd /home/ec2-user
  // su -c "ln -s /usr/bin/python3.8 /usr/bin/python3" -s /bin/sh ec2-user
  // su -c "pip3 install boto3 --user" -s /bin/sh ec2-user
  // su -c "pip3 install awscli --user" -s /bin/sh ec2-user
  // su -c "pip3 install kafka-python --user" -s /bin/sh ec2-user
  // 
  // # install AWS CLI 2 - access with aws2
  // su -c "ln -s /usr/local/bin/aws2/aws ~/.local/bin/aws2" -s /bin/sh ec2-user
  // 
  // # Create dirs, get Apache Kafka 3.5.1 unpack it
  // su -c "mkdir -p kafka351 confluent" -s /bin/sh ec2-user
  // su -c "mkdir -p /tmp/kafka" -s /bin/sh ec2-user
  // 
  // cd /home/ec2-user
  // ln -s /home/ec2-user/kafka351 /home/ec2-user/kafka
  // cd kafka351
  // su -c "wget https://archive.apache.org/dist/kafka/3.5.1/kafka_2.13-3.5.1.tgz" -s /bin/sh ec2-user
  // su -c "tar -xzf kafka_2.13-3.5.1.tgz --strip 1" -s /bin/sh ec2-user
  // 
  // # Get Confluent Community and unpack it
  // cd /home/ec2-user
  // cd confluent
  // su -c "wget http://packages.confluent.io/archive/5.4/confluent-community-5.4.1-2.12.tar.gz" -s /bin/sh ec2-user
  // su -c "tar -xzf confluent-community-5.4.1-2.12.tar.gz --strip 1" -s /bin/sh ec2-user
  // 
  // 
  // # get kafka producer dependencies 
  // su -c "git -C /home/ec2-user/kafka clone https://github.com/aws-samples/sasl-scram-secrets-manager-client-for-msk.git" -l ec2-user
  // su -c "cd /home/ec2-user/kafka/sasl-scram-secrets-manager-client-for-msk/ && mvn clean install -f pom.xml && cp target/SaslScramSecretsManagerClient-1.0-SNAPSHOT.jar /tmp/kafka && cp /tmp/kafka/SaslScramSecretsManagerClient-1.0-SNAPSHOT.jar /home/ec2-user/kafka" -l ec2-user
  // su -c "cd /home/ec2-user/kafka && rm -rf sasl-scram-secrets-manager-client-for-msk" -l ec2-user
  // 
  // su -c "git -C /home/ec2-user/kafka clone https://github.com/aws-samples/clickstream-producer-for-apache-kafka.git" -l ec2-user
  // su -c "cd /home/ec2-user/kafka/clickstream-producer-for-apache-kafka/ && mvn clean package -f pom.xml && cp target/KafkaClickstreamClient-1.0-SNAPSHOT.jar /tmp/kafka && cp /tmp/kafka/KafkaClickstreamClient-1.0-SNAPSHOT.jar /home/ec2-user/kafka" -l ec2-user
  // su -c "cd /home/ec2-user/kafka && rm -rf clickstream-producer-for-apache-kafka" -l ec2-user
  // 
  // # get prometheus config 
  // su -c "mkdir -p /home/ec2-user/prometheus" -s /bin/sh ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/kafka-connect.yml /home/ec2-user/prometheus" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/kafka-producer-consumer.yml /home/ec2-user/prometheus" -l ec2-user
  // 
  // # Initialize the Kafka cert trust store
  // su -c 'find /usr/lib/jvm/ -name "cacerts" -exec cp {} /tmp/kafka.client.truststore.jks \;' -s /bin/sh ec2-user
  // 
  // cd /tmp
  // 
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/producer.properties_msk /tmp/kafka && cp /tmp/kafka/producer.properties_msk  /home/ec2-user/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/consumer.properties /tmp/kafka && cp /tmp/kafka/consumer.properties_msk  /home/ec2-user/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/jars/KafkaClickstreamClient-1.0-SNAPSHOT.jar /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/jars/KafkaClickstreamConsumer-1.0-SNAPSHOT.jar /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/jars/CustomMM2ReplicationPolicy-1.0-SNAPSHOT.jar /home/ec2-user/confluent/share/java/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/jars/MM2GroupOffsetSync-1.0-SNAPSHOT.jar /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/MSKLabs/schema-registry-ssl/schema-registry.properties /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/generatePropertiesFiles.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/generateStartupFile.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/AuthMSK-1.0-SNAPSHOT.jar /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/connect-distributed.properties /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/kafka-consumer-python.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/setup-env.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/setup-policy.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/GlobalSeqNo.py /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/mm2-msc.json /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/mm2-hbc.json /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/mm2-cpc.json /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/mm2-cpc-cust-repl-policy.json /tmp/kafka" -l ec2-user
  // su -c "aws s3 cp s3://aws-streaming-artifacts/msk-lab-resources/mm2-msc-cust-repl-policy.json /tmp/kafka" -l ec2-user
  // 
  // # Setup unit in systemd for Schema Registry
  // echo -n "
  // [Unit]
  // Description=Confluent Schema Registry
  // After=network.target
  // 
  // [Service]
  // Type=simple
  // User=ec2-user
  // ExecStart=/bin/sh -c '/home/ec2-user/confluent/bin/schema-registry-start /tmp/kafka/schema-registry.properties > /tmp/kafka/schema-registry.log 2>&1'
  // ExecStop=/home/ec2-user/confluent/bin/schema-registry-stop
  // Restart=on-abnormal
  // 
  // [Install]
  // WantedBy=multi-user.target" > /etc/systemd/system/confluent-schema-registry.service
  // 
  // # Setup unit in systemd for Kafka Connect
  // echo -n "
  // [Unit]
  // Description=Kafka Connect
  // After=network.target
  // 
  // [Service]
  // Type=simple
  // User=ec2-user
  // ExecStart=/bin/sh -c '/home/ec2-user/kafka/bin/connect-distributed.sh /tmp/kafka/connect-distributed.properties > /tmp/kafka/kafka-connect.log 2>&1'
  // Restart=on-abnormal
  // 
  // [Install]
  // WantedBy=multi-user.target" > /etc/systemd/system/kafka-connect.service
  // 
  // #setup bash env
  // su -c "echo 'export PS1=\"KafkaClientEC2Instance1 [\u@\h \W]$ \"' >> /home/ec2-user/.bash_profile" -s /bin/sh ec2-user
  // su -c "echo '[ -f /tmp/kafka/setup_env ] && . /tmp/kafka/setup_env' >> /home/ec2-user/.bash_profile" -s /bin/sh ec2-user
  // ")
  // CF Property(tags) = {
  //   Name = "KafkaClientInstance"
  // }
}

resource "aws_iam_role" "ec2_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid = ""
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  path = "/"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonMSKFullAccess",
    "arn:aws:iam::aws:policy/AWSCloudFormationFullAccess",
    "arn:aws:iam::aws:policy/CloudWatchFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/AWSCertificateManagerPrivateCAFullAccess",
    "arn:aws:iam::aws:policy/IAMFullAccess",
    "arn:aws:iam::aws:policy/AmazonKinesisFirehoseFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
  ]
  force_detach_policies = [
    {
      PolicyName = "MSKConfigurationAccess"
      PolicyDocument = "{ "Version": "2012-10-17", "Statement": [ { "Sid": "VisualEditor0", "Effect": "Allow", "Action": "kafka:CreateConfiguration", "Resource": "*" } ] }"
    },
    {
      PolicyName = "CloudformationDeploy"
      PolicyDocument = "{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": [ "iam:*" ], "Resource": "*" } ] }"
    },
    {
      PolicyName = "MSKProducerPermissions"
      PolicyDocument = {
        Version = "2012-10-17"
        Statement = [
          {
            Sid = "SecretsAccess"
            Effect = "Allow"
            Action = [
              "secretsmanager:*",
              "kms:*",
              "glue:*Schema*",
              "iam:CreatePolicy",
              "iam:Tag*",
              "iam:AttachRolePolicy"
            ]
            Resource = "*"
          }
        ]
      }
    },
    {
      PolicyName = "MSKConnectAuthentication"
      PolicyDocument = "{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": [ "kafka-cluster:*Topic*", "kafka-cluster:Connect", "kafka-cluster:AlterCluster", "kafka-cluster:DescribeCluster", "kafka-cluster:DescribeClusterDynamicConfiguration" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/MSKCluster-${local.stack_name}/*" ] }, { "Effect": "Allow", "Action": [ "kafka-cluster:*Topic*", "kafka-cluster:WriteData", "kafka-cluster:ReadData" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*" ] }, { "Effect": "Deny", "Action": [ "kafka-cluster:WriteData", "kafka-cluster:ReadData" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*/testiamfail" ] }, { "Effect": "Allow", "Action": [ "kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/MSKCluster-${local.stack_name}/*" ] } ] }"
    }
  ]
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = join("-", ["EC2MMMSKCFProfile", local.stack_name])
  role = [
    aws_iam_role.ec2_role.arn
  ]
}

resource "aws_acmpca_certificate_authority" "root_ca" {
  type = "ROOT"
  key_storage_security_standard = "RSA_2048"
  // CF Property(SigningAlgorithm) = "SHA256WITHRSA"
  // CF Property(Subject) = {
  //   Country = "US"
  //   Organization = "Amazon"
  //   OrganizationalUnit = "AWS"
  //   State = "New York"
  //   CommonName = "MyMSKPCA"
  // }
  revocation_configuration {
    crl_configuration {
      enabled = false
    }
  }
}

resource "aws_acmpca_certificate" "root_ca_certificate" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root_ca.id
  certificate_signing_request = aws_acmpca_certificate_authority.root_ca.certificate_signing_request
  signing_algorithm = "SHA256WITHRSA"
  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"
  validity = {
    Type = "YEARS"
    Value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "root_ca_activation" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root_ca.id
  certificate = aws_acmpca_certificate.root_ca_certificate.certificate
  // CF Property(Status) = "ACTIVE"
}

resource "aws_acmpca_permission" "root_ca_permission" {
  actions = [
    "IssueCertificate",
    "GetCertificate",
    "ListPermissions"
  ]
  certificate_authority_arn = aws_acmpca_certificate_authority.root_ca.id
  principal = "acm.amazonaws.com"
}

resource "aws_kms_key" "mks_custom_key" {
  description = "Amazon MSK custom Key"
  is_enabled = true
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "kms:*"
        Resource = "*"
      }
    ]
  }
}

resource "aws_secretsmanager_secret" "secret_user_alice" {
  description = "AmazonMSK User Alice"
  kms_key_id = aws_kms_key.mks_custom_key.arn
  name = "AmazonMSK_alice"
  force_overwrite_replica_secret = "{"username":"alice","password":"alice-secret"}"
}

resource "aws_secretsmanager_secret" "secret_user_nancy" {
  description = "AmazonMSK User Nancy"
  kms_key_id = aws_kms_key.mks_custom_key.arn
  name = "AmazonMSK_nancy"
  force_overwrite_replica_secret = "{"username":"nancy","password":"nancy-secret"}"
}

resource "aws_security_group" "msk_security_group" {
  description = "MSK Security Group"
  vpc_id = aws_cloudformation_stack.mskvpc_stack.outputs.VPCId
  ingress = [
    {
      protocol = "tcp"
      from_port = 2181
      to_port = 2181
      security_groups = aws_security_group.kafka_client_instance_security_group.id
    },
    {
      protocol = "tcp"
      from_port = 9094
      to_port = 9094
      security_groups = aws_security_group.kafka_client_instance_security_group.id
    },
    {
      protocol = "tcp"
      from_port = 9096
      to_port = 9096
      security_groups = aws_security_group.kafka_client_instance_security_group.id
    },
    {
      protocol = "tcp"
      from_port = 9092
      to_port = 9092
      security_groups = aws_security_group.kafka_client_instance_security_group.id
    },
    {
      protocol = "tcp"
      from_port = 9098
      to_port = 9098
      security_groups = aws_security_group.kafka_client_instance_security_group.id
    }
  ]
}

resource "aws_vpc_security_group_ingress_rule" "msk_self_ingress_allow_rule" {
  referenced_security_group_id = aws_security_group.msk_security_group.arn
  ip_protocol = "tcp"
  from_port = 9092
  to_port = 9098
  security_group_id = aws_security_group.msk_security_group.arn
}

resource "aws_msk_cluster" "msk_cluster_mtls" {
  count = local.MTLS ? 1 : 0
  broker_node_group_info = {
    ClientSubnets = [
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKOne,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKTwo,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKThree
    ]
    InstanceType = "kafka.m5.large"
    SecurityGroups = [
      aws_security_group.msk_security_group.id
    ]
    StorageInfo = {
      EBSStorageInfo = {
        VolumeSize = 1000
      }
    }
  }
  cluster_name = join("-", ["MSKCluster", local.stack_name])
  encryption_info = {
    EncryptionInTransit = {
      ClientBroker = "TLS_PLAINTEXT"
      InCluster = true
    }
  }
  client_authentication = {
    Sasl = {
      Scram = {
        Enabled = true
      }
      Iam = {
        Enabled = true
      }
    }
    Tls = {
      CertificateAuthorityArnList = [
        aws_acmpca_certificate_authority.root_ca.arn
      ]
    }
    Unauthenticated = {
      Enabled = true
    }
  }
  enhanced_monitoring = "DEFAULT"
  kafka_version = var.msk_kafka_version
  number_of_broker_nodes = 3
}

resource "aws_msk_cluster" "msk_cluster_no_mtls" {
  count = local.noMTLS ? 1 : 0
  broker_node_group_info = {
    ClientSubnets = [
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKOne,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSKTwo,
      aws_cloudformation_stack.mskvpc_stack.outputs.PrivateSubnetMSK
    ]
    InstanceType = "kafka.m5.large"
    SecurityGroups = [
      aws_security_group.msk_security_group.id
    ]
    StorageInfo = {
      EBSStorageInfo = {
        VolumeSize = 1000
      }
    }
  }
  cluster_name = join("-", ["MSKCluster", local.stack_name])
  encryption_info = {
    EncryptionInTransit = {
      ClientBroker = "TLS_PLAINTEXT"
      InCluster = true
    }
  }
  enhanced_monitoring = "DEFAULT"
  kafka_version = var.msk_kafka_version
  number_of_broker_nodes = 3
}

resource "aws_s3_bucket" "firehose_target_bucket" {
  bucket = "firehose-msk-lab-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-target-bucket"
}

resource "aws_iam_role" "firehose_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid = ""
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
  path = "/"
  force_detach_policies = [
    {
      PolicyName = "MSKConfigurationAccess"
      PolicyDocument = "{ "Version": "2012-10-17", "Statement": [ { "Sid": "VisualEditor0", "Effect": "Allow", "Action": "kafka:CreateConfiguration", "Resource": "*" } ] }"
    },
    {
      PolicyName = "MSKConnectAuthentication"
      PolicyDocument = "{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": [ "kafka-cluster:*Topic*", "kafka-cluster:Connect", "kafka-cluster:AlterCluster", "kafka-cluster:DescribeCluster", "kafka-cluster:DescribeClusterDynamicConfiguration", "kms:Decrypt", "kinesis:DescribeStream", "kinesis:GetShardIterator", "kinesis:GetRecords", "kinesis:ListShards", "logs:PutLogEvents", "lambda:InvokeFunction", "lambda:GetFunctionConfiguration", "kms:GenerateDataKey", "kms:Decrypt", "glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions", "ec2:DeleteNetworkInterface", "ec2:DescribeDhcpOptions", "ec2:DescribeSecurityGroups", "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:CreateNetworkInterfacePermission", "ec2:DescribeVpcs", "ec2:DescribeSubnets", "kafka-cluster:Connect", "kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:DeleteTopic", "kafka-cluster:WriteData", "kafka-cluster:ReadData", "kafka-cluster:*Topic*", "kafka:CreateVpcConnection", "s3:*", "s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject", "kafka:CreateVpcConnection", "kafka:GetBootstrapBrokers", "kafka:DescribeCluster", "kafka:DescribeClusterV2" ], "Resource": [ "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog", "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:s3:::firehose-msk-lab-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-target-bucket", "arn:aws:s3:::firehose-msk-lab-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-target-bucket/*", "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/*:log-stream:*", "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%:log-stream:*", "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/%FIREHOSE_POLICY_TEMPLATE_PLACEHOLDER%", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/msk-serverless-cluster/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/msk-serverless-cluster/*/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/msk-serverless-cluster/*/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/MSKCluster-${local.stack_name}/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*/*", "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/MSKCluster-${local.stack_name}/*/*" ] }, { "Effect": "Allow", "Action": [ "kafka-cluster:*Topic*", "kafka-cluster:WriteData", "kafka-cluster:ReadData" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/MSKCluster-${local.stack_name}/*" ] }, { "Effect": "Allow", "Action": [ "kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup" ], "Resource": [ "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/MSKCluster-${local.stack_name}/*" ] } ] }"
    }
  ]
}

