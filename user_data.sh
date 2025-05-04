#!/bin/bash
# Update system and install Docker
yum update -y
yum install -y docker
usermod -aG docker ec2-user
systemctl enable docker
systemctl start docker

# Wait for Docker to be fully operational
for i in {1..10}; do
  if /usr/bin/docker info &>/dev/null; then
    break
  fi
  echo "Waiting for Docker to start... Attempt $i"
  sleep 5
  if [ $i -eq 10 ]; then
    echo "Docker failed to start"
    exit 1
  fi
done

# Run Jenkins container
/usr/bin/docker run -d -p 8080:8080 -p 50000:50000 -v /var/jenkins_home:/var/jenkins_home --name jenkins jenkins/jenkins:lts

# Install AWS CLI and Ansible
yum install -y python3-pip
pip3 install awscli ansible

# Create Ansible directory
mkdir -p /etc/ansible
echo "[local]" > /etc/ansible/hosts
echo "localhost ansible_connection=local" >> /etc/ansible/hosts

# Schedule backup
echo "BACKUP_BUCKET=${backup_bucket}" >> /etc/environment
echo "0 2 * * * root /usr/local/bin/ansible-playbook /etc/ansible/backup.yml" >> /etc/crontab