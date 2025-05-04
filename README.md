# tinyjenkins

## Jenkins on AWS with Terraform and GitHub Actions

This project deploys a Jenkins instance on an AWS EC2 spot instance using Terraform and GitHub Actions, with a pre-configured Docker image hosted on Docker Hub. It includes Auto-Scaling, S3 backups, Route 53 DNS, and CloudWatch monitoring, designed for secure, reusable CI/CD automation in a public repository.

## Architecture
- **EC2 Spot Instance**: Runs Jenkins in a Docker container (`harrisoncloudengineer/tinyjenkins:latest`) with pre-installed plugins (`git`, `workflow-aggregator`, `credentials`), managed by an Auto-Scaling Group (ASG).
- **Terraform**: Defines infrastructure (EC2, ASG, S3, Route 53, CloudWatch, SNS).
- **GitHub Actions**: Automates Terraform deployment and verifies Jenkins availability.
- **Route 53**: Provides a static DNS name (e.g., `jenkins.yourdomain.com`).
- **CloudWatch**: Monitors CPU and instance health with SNS notifications.
- **S3**: Stores Terraform state and nightly Jenkins backups (via a shell script).

## Prerequisites
- **AWS Account**: With IAM user credentials (permissions for EC2, S3, Route 53, CloudWatch, SNS, IAM).
- **SSH Key Pair**:
  - Create an EC2 key pair in your AWS region (e.g., `us-east-1`):
    1. Go to AWS EC2 Console > Key Pairs.
    2. Click "Create key pair".
    3. Name it (e.g., `jenkins-key`), select "RSA" and "PEM" format, and create.
    4. Download the private key file (e.g., `jenkins-key.pem`) and store it securely.
  - Verify the key pair exists in the region specified by `TF_VAR_region` (default: `us-east-1`).
- **Route 53 Domain**: A domain managed in AWS Route 53 (e.g., `yourdomain.com`).
- **GitHub Repository**: Public or private, with Actions enabled.

## Setup Instructions
1. **Clone Repository**:
   - Clone or fork this repository:
     ```bash
     git clone https://github.com/<your-username>/tinyjenkins.git
     ```
   - Ensure `.gitignore` excludes `.terraform/`, `*.tfstate`, `*.pem`, `terraform.tfvars`.

2. **Verify Docker Image**:
   - The pre-configured Jenkins image is hosted publicly at `harrisoncloudengineer/tinyjenkins:latest`. Users do not need to build it.
   - Optional (for maintainers): To update the image, build and push:
     ```bash
     cd <repository-root>
     docker build -t harrisoncloudengineer/tinyjenkins:latest .
     docker login
     docker push harrisoncloudengineer/tinyjenkins:latest
     ```

3. **Verify Route 53**:
   - In AWS Route 53, confirm the hosted zone for your domain (e.g., `yourdomain.com`) exists.
   - Ensure your registrar’s NS records match the hosted zone’s NS records (e.g., `ns-123.awsdns-45.com`).

4. **Configure GitHub Secrets**:
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

5. **Deploy**:
   - Commit and push to the `main` branch.
   - GitHub Actions will:
     - Run Terraform to deploy infrastructure.
     - Verify Jenkins availability via the EC2 public IP.
   - Monitor the workflow in the `Actions` tab.

6. **Access Jenkins**:
   - Visit `http://jenkins.<your-domain>:8080` (e.g., `http://jenkins.yourdomain.com:8080`). Note: DNS propagation may take up to 300 seconds or more.
   - Alternatively, use the EC2 public IP:
     ```bash
     aws ec2 describe-instances --filters "Name=tag:Name,Values=Jenkins-Spot" --query "Reservations[0].Instances[0].PublicIpAddress" --output text
     ```
     Access `http://<public-ip>:8080`.
   - Get the initial admin password:
     ```bash
     ssh -i <key.pem> ec2-user@<ec2-ip> "sudo cat /var/jenkins_home/secrets/initialAdminPassword"
     ```
     Find `<ec2-ip>` in the AWS EC2 Console (Instances > Jenkins-Spot > Public IPv4 address).
   - Complete the Jenkins setup wizard to configure the instance.

7. **Verify Backups and Monitoring**:
   - Check the S3 bucket (`jenkins-backups-<random-suffix>`) for nightly backups:
     ```bash
     aws s3 ls s3://jenkins-backups-<suffix>/backups/
     ```
   - Confirm CloudWatch alarms (`jenkins-cpu-usage`, `jenkins-instance-health`) in AWS.
   - Subscribe to SNS notifications via the email sent to `TF_VAR_alert_email`.

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
- **EC2 Spot (t3.micro)**: ~$2.19/month.
- **S3 (state + backups)**: ~$0.14/month.
- **Route 53 (hosted zone + queries)**: ~$0.50/month.
- **CloudWatch (alarms + metrics)**: ~$0.21/month.
- **SNS (notifications)**: ~$0.000005/month.
- **Data Transfer**: ~$0.01/month.
- **Total**: ~$3.05-$3.75/month.
- **Note**: Domain registration (~$12/year) is separate if not already owned.

## Security
- Secrets are stored in GitHub Secrets, not in the repository.
- S3 backups are encrypted with AES256.
- SSH access (port 22) is restricted to `TF_VAR_allowed_cidr`.
- Jenkins (port 8080) is accessible via Route 53 DNS (consider HTTPS for production).
- Sensitive outputs (e.g., Jenkins URL) are masked in GitHub Actions logs using `::add-mask::`.
- The Docker image is public; scan for vulnerabilities with:
  ```bash
  trivy image harrisoncloudengineer/tinyjenkins:latest
  ```

## Troubleshooting
- **Workflow Fails**:
  - Check GitHub Actions logs for Terraform errors or availability check failures.
  - Verify `TF_LOG=DEBUG` output for detailed error messages.
- **Jenkins Unreachable**:
  - Ensure the security group allows port 8080 and the instance is running.
  - Check `TF_VAR_allowed_cidr` matches your IP for SSH access.
  - Test with the public IP:
    ```bash
    curl -s --head http://<public-ip>:8080
    ```
    Expect `200 OK` or `403 Forbidden` (indicating Jenkins is running but needs setup).
- **DNS Propagation Delay**:
  - The DNS URL (`http://jenkins.<your-domain>:8080`) may take up to 300 seconds to propagate. Use the EC2 public IP for immediate access.
