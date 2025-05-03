#!/bin/bash
# Update and install dependencies
yum update -y
amazon-linux-extras install docker -y
systemctl enable docker
systemctl start docker
docker run -d -p 8080:8080 -p 50000:50000 -v /var/jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts

# Install AWS CLI and Ansible
yum install -y python3-pip
pip3 install awscli ansible

# Ensure SSM agent is installed and running
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

# Create Ansible directory
mkdir -p /etc/ansible
echo "[local]" > /etc/ansible/hosts
echo "localhost ansible_connection=local" >> /etc/ansible/hosts

# Schedule backup with validation
echo "BACKUP_BUCKET='${backup_bucket}'" >> /var/log/user-data.log
if [ -z "${backup_bucket}" ]; then
  echo "Warning: BACKUP_BUCKET not set, skipping backup scheduling" >> /var/log/user-data.log
else
  echo "BACKUP_BUCKET=${backup_bucket}" >> /etc/environment
  echo "0 2 * * * root /usr/local/bin/ansible-playbook /etc/ansible/backup.yml" >> /etc/crontab
fi

# Log user-data execution
echo "user-data script completed at $(date)" >> /var/log/user-data.log