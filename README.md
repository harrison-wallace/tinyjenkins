# tinyjenkins

## Jenkins on AWS with Terraform and GitHub Actions

   This project deploys a Jenkins instance on an EC2 spot instance with Auto-Scaling, Ansible configuration, S3 backups, Route 53 DNS, and CloudWatch monitoring. It’s designed for secure personal use in a public repository.

   ## Architecture
   - **EC2 Spot Instance**: Runs Jenkins in a Docker container, managed by an Auto-Scaling Group.
   - **Terraform**: Defines infrastructure (EC2, ASG, S3, Route 53, CloudWatch, SNS).
   - **GitHub Actions**: Automates deployment and Ansible configuration.
   - **Ansible**: Configures Jenkins (plugins, settings) and manages S3 backups/restores.
   - **Route 53**: Provides a static DNS name (e.g., `jenkins.yourdomain.com`).
   - **CloudWatch**: Monitors CPU and instance health with SNS notifications.
   - **S3**: Stores Terraform state and Jenkins backups.

   ## Prerequisites
   - **AWS Account**: With IAM user credentials (EC2, S3, DynamoDB, Route 53, CloudWatch, SNS, IAM permissions).
   - **SSH Key Pair**: Created in EC2 for your region (e.g., `us-east-1`).
   - **Route 53 Domain**: A domain managed in AWS Route 53 (e.g., `yourdomain.com`).
   - **GitHub Repository**: Public or private, with Actions enabled.
   - **S3 Bucket and DynamoDB Table**:
     - Bucket for Terraform state (e.g., `my-terraform-state-bucket`).
     - DynamoDB table for state locking (e.g., `terraform-locks`, partition key: `LockID`).

   ## Setup Instructions
   1. **Clone or Create Repository**:
      - Create a GitHub repository and add the provided files.
      - Ensure `.gitignore` excludes `.terraform/`, `*.tfstate`, `*.pem`, `terraform.tfvars`.
   2. **Verify Route 53**:
      - In AWS Route 53, confirm the hosted zone for your domain (e.g., `yourdomain.com`) exists.
      - Ensure your registrar’s NS records match the hosted zone’s NS records (e.g., `ns-123.awsdns-45.com`).
   3. **Configure GitHub Secrets**:
      - Go to `Settings > Secrets and variables > Actions > Secrets` in your repo.
      - Add:
        - `AWS_ACCESS_KEY_ID`: IAM user access key.
        - `AWS_SECRET_ACCESS_KEY`: IAM user secret key.
        - `TF_VAR_domain_name`: Your domain (e.g., `yourdomain.com`).
        - `TF_VAR_state_bucket`: S3 bucket for Terraform state (e.g., `my-terraform-state-bucket`).
        - `TF_VAR_region`: AWS region (e.g., `us-east-1`).
        - `TF_VAR_allowed_cidr`: Your IP CIDR for SSH (e.g., `203.0.113.0/32`; find via `curl ifconfig.me`).
        - `TF_VAR_key_name`: EC2 key pair name (e.g., `jenkins-key`).
        - `TF_VAR_alert_email`: Email for CloudWatch notifications (e.g., `you@example.com`).
        - `SSH_PRIVATE_KEY`: Contents of your EC2 private key (e.g., `jenkins-key.pem`).
   4. **Deploy**:
      - Commit and push to the `main` branch.
      - GitHub Actions will:
        - Run Terraform to deploy infrastructure.
        - Copy and execute Ansible playbooks to configure Jenkins.
      - Monitor the workflow in the `Actions` tab.
   5. **Access Jenkins**:
      - Visit `http://jenkins.<your-domain>:8080` (e.g., `http://jenkins.yourdomain.com:8080`).
      - Get the initial admin password:
        ```bash
        ssh -i <key.pem> ec2-user@<ec2-ip> "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
        ```
        Find `<ec2-ip>` in the AWS EC2 console or Terraform output.
   6. **Verify Backups and Monitoring**:
      - Check the S3 bucket (`jenkins-backups-<random-suffix>`) for nightly backups.
      - Confirm CloudWatch alarms (`jenkins-cpu-usage`, `jenkins-instance-health`) in AWS.
      - Subscribe to SNS notifications via the email sent to `TF_VAR_alert_email`.
   7. **Restore from Backup**:
      - To restore Jenkins:
        ```bash
        ssh -i <key.pem> ec2-user@<ec2-ip> "sudo ansible-playbook /etc/ansible/restore.yml"
        ```
   8. **Cleanup**:
      - To avoid costs, run `terraform destroy` locally:
        ```bash
        export AWS_ACCESS_KEY_ID=<your-key>
        export AWS_SECRET_ACCESS_KEY=<your-secret>
        export TF_VAR_domain_name=yourdomain.com
        export TF_VAR_state_bucket=my-terraform-state-bucket
        export TF_VAR_region=us-east-1
        export TF_VAR_allowed_cidr=<your-cidr>
        export TF_VAR_key_name=jenkins-key
        export TF_VAR_alert_email=you@example.com
        terraform init -backend-config="bucket=my-terraform-state-bucket" -backend-config="region=us-east-1"
        terraform destroy
        ```

   ## Cost Estimate
   - EC2 Spot (t3.micro): ~$2.19/month.
   - S3 (state + backups): ~$0.14/month.
   - DynamoDB (state locking): ~$0.25/month.
   - Route 53 (hosted zone + queries): ~$0.50/month.
   - CloudWatch (alarms + metrics): ~$0.21/month.
   - SNS (notifications): ~$0.000005/month.
   - Data Transfer: ~$0.01/month.
   - **Total**: ~$3.30-$4/month.
   - **Note**: Domain registration (~$12/year) is separate if not already owned.

   ## Security
   - Secrets are stored in GitHub Secrets, not in the repo.
   - S3 backups are encrypted with AES256.
   - SSH access (port 22) is restricted to `TF_VAR_allowed_cidr`.
   - Jenkins (port 8080) is accessible via Route 53 DNS (consider HTTPS for production).

   ## Troubleshooting
   - **Workflow Fails**: Check GitHub Actions logs for Terraform or SSH errors.
   - **Route 53 Issues**: Verify NS records and hosted zone in AWS.
   - **Jenkins Unreachable**: Ensure security group allows port 8080 and instance is running. 
    - Check your IP is correct in `TF_VAR_allowed_cidr`