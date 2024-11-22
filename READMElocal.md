Step-by-Step Guide to Deploy Terraform Configurations

    Install Terraform:

        If you haven't installed Terraform yet, download it from the Terraform Website and follw the installation instructins for your operating system.  

Set Up Your Working Directory:
    Ensure all your .tf files (output.tf, resources.tf, variables.tf, locals.tf, and data.tf) are in the same directory.

Initialize the Terraform Working Directory:
    Open your terminal and navigate to the directory containing your .tf files.
    Run the following command to initialize the working directory, which will download the necessary provider plugins:


terraform init


Review the Terraform Plan:
    Before applying the configuration, it's good practice to review what Terraform will do.
    Run the following command to generate and show the execution plan:


terrform plan


Apply the Terraform Configuration:
    Once you’ve reviewed the plan and are satisfied with the changes, you can apply the configuration.
    Run the following command to create the resources defined in your .tf files:
 
terrform apply

    Terraform will prompt you to confirm before proceeding. Type yes and press Enter.
Verify the Deployment:
    Check your cloud provider's console or management interface to verify that the resources have been created as expected.

Here more examples

# Navigate to the directory containing your Terraform configuration files
cd path/to/your/terraform/configuration

# Initialize the working directory
terraform init

# Generate and review the execution plan
terraform plan

# Apply the configuration to create the resources
terraform apply


TESTING THE CONFIGURATIN

1. Testing the Configuration
Plan Command

    The terraform plan command generates an execution plan, allowing you to see what changes Terraform will make without actually applying them. This helps to verify that your configuration is correct.

terraform plan

Using terraform apply with -auto-approve=false
    When you run terraform apply, you can use the -auto-approve=false flag to ensure Terraform prompts for confirmation before proceeding. This lets you review the plan one more time before applying it.

terraform apply -auto-approve=false


2. Confirming Destruction
Simulate Resource Destruction

    After applying the configuration, you can simulate the destruction of resources using the terraform destroy command with the -target flag. This allows you to target specific resources and see what will be destroyed without actually destroying anything.

terraform plan -destroy -target=resource_type.resource_name

Performing terraform destroy

    Once you are confident that your resources can be destroyed successfully, you can use the terraform destroy command to remove all resources created by your configuration. Use the -auto-approve flag to skip the interactive approval step.

terraform destroy -auto-approve

