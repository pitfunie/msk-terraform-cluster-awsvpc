
With Amazon Managed Streaming for Apache Kafka (Amazon MSK), you pay only for what you use. There are no minimum fees or upfront commitments. You do not pay for Apache ZooKeeper or Apache Kafka Raft (KRaft) controller nodes that Amazon MSK 
provisions for you for metadata management. You also do not pay for data transfer between brokers or between the metadata management nodes and brokers within your clusters. Amazon MSK pricing is based on the type of resource you create. 
There are two types of clusters MSK Provisioned clusters and MSK Serverless clusters. With MSK Provisioned clusters, you can specify and then scale cluster capacity to meet your needs. With MSK Serverless clusters, you don't need to specify 
or scale cluster capacity. You can also create Kafka Connect connectors using Amazon MSK Connect. See the following tabs for detailed pricing and examples.


![2024-11-21_20-57-18](https://github.com/user-attachments/assets/3eeeb209-7e8a-4eaa-ac48-4ab69bfb5c0e)



sudo -u ec2-user -i

Copy and paste the bash script below in the opened terminal. This will set up some Amazon MSK environment variables. - in the EC2 instance's bash_profile. if you are running this from your AWS account , change the stack_name to your cloud formation
stack name

export AWS_REGION=$(TOKEN=`curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` \
&& curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
export stack_name=msk-labs-default # IMPORTANT: If running in your own account, set MSK_STACK=MSK
cd /tmp/kafka
python3 ./setup-env.py --stackName $stack_name --region $AWS_REGION
. ./setup_env $stack_name
source ~/.bash_profile


CREATE CLUSTER

The MSK cluster will be deployed into an existing VPC that has been provisioned for you in advance. The brokers will be deployed across 3 private subnets, with one broker per AZ. If you are running this workshop in your own AWS account, please ensure 
that there is a private subnet available in each AZ where you want to deploy the MSK cluster.

If you chose to deploy and MSK cluster using the AWS CLI, you will need to provide several inputs. It can be helpful to have a text editor open to keep track of the necessary details.


![2024-11-21_20-50-18](https://github.com/user-attachments/assets/08d4d31e-1f32-44d1-9f4b-5174c8ae5766)


The architecture diagram illustrates the interaction between the following components:

Broker nodes - When creating an Amazon MSK cluster, you specify how many broker nodes you want Amazon MSK to create in each Availability Zone. In the example cluster shown in the diagram, there is one broker node deployed per Availability Zone.
Each Availability Zone has its own Virtual Private Cloud (VPC) subnet. Amazon MSK offers two options for the Kafka node layout - a 3 Availability Zone configuration or a 2 Availability Zone configuration. Currently, a single Availability Zone (1 AZ) 
Amazon MSK cluster is not available.

ZooKeeper nodes - Amazon MSK also creates the Apache ZooKeeper nodes for you. Apache ZooKeeper is an open-source server that enables highly reliable, distributed coordination. There is a dedicated ZooKeeper ensemble created for each Amazon MSK cluster 
that is fully obfuscated and included with each cluster at no additional cost. From Apache Kafka version 3.7.x on MSK, you can create clusters that use KRaft mode  instead of ZooKeeper mode. The Apache Kafka community developed KRaft to replace Apache Z
ooKeeper for metadata management in Apache Kafka clusters. In KRaft mode, cluster metadata is propagated within a group of Kafka controllers, which are part of the Kafka cluster, instead of across ZooKeeper nodes. KRaft controllers are included at no a
dditional cost to you, and require no additional setup or management from you.

Kafka Client EC2 - Amazon MSK lets you use Apache Kafka data-plane operations to create topics and to produce and consume data. For this workshop, you will be using a Kafka Client running on EC2 to perform the data-plane operations.
AWS CLI - You can use the AWS Command Line Interface (AWS CLI) or the APIs in the SDK to perform control-plane operations. For example, you can use the AWS CLI or the SDK to create or delete an Amazon MSK cluster, list all the clusters in an account,
or 
view the properties of a cluster.



Step 1 - Create an MSK security group
By default, the cluster will be attached to the 'default' security group, which allows all ports between all members of the group. This is fine for testing, but it's not a best practice in production.

We need two security groups - one to attach to producers, consumers, and admin hosts, and the other to attach to the Amazon MSK cluster that references the first.

Create the security group for the Amazon MSK cluster

Click on Services in the top left corner of the console, and select EC2
Select Security Groups  in the left pane
Click Create Security Group
Fill out the form as follows:

Security group name: MSKWorkshop-KafkaService
Description: Access to the Kafka service on the MSK cluster
VPC: [select the VPC you are using for your lab (MSKVPC)]
Create rules
a. Click Add rule under the Inbound rules section. Use:

Type: Custom TCP
Protocol: TCP
Port range: 9092
Source: [paste the value of the KafkaClientInstanceSecurityGroup SG you copied in the previous step, from Cloudformation Outputs (msklab-KafkaClientInstance...)]
Description: Plaintext Kafka
b. Click Add Rule. Use:

Type: Custom TCP
Protocol: TCP
Port range: 9094
Source: [paste the value of the KafkaClientInstanceSecurityGroup SG you copied in the previous step, from Cloudformation Outputs (msklab-KafkaClientInstance...)]
Description: Encrypted Kafka
c. Click Add Rule. Use:

Type: Custom TCP
Protocol: TCP
Port range: 2181
Source: [paste the value of the KafkaClientInstanceSecurityGroup SG you copied in the previous step, from Cloudformation Outputs (msklab-KafkaClientInstance...)]
Description: Zookeeper access



![2024-11-21_20-54-45](https://github.com/user-attachments/assets/dc431099-7877-462d-a0b8-ea24adf8c474)


FOR FURTHER INSTRUCTIONS

https://catalog.us-east-1.prod.workshops.aws/workshops/c2b72b6f-666b-4596-b8bc-bafa5dcca741/en-US/clustercreation/overview






