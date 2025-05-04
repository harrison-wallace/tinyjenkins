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

# Run Jenkins container from custom image
/usr/bin/docker run -d -p 8080:8080 -p 50000:50000 -v /var/jenkins_home:/var/jenkins_home --name jenkins harrisoncloudengineer/tinyjenkins:latest

# Install AWS CLI
yum install -y awscli

# Create backup script
cat << 'EOF' > /usr/local/bin/jenkins_backup.sh
#!/bin/bash
BACKUP_BUCKET="${backup_bucket}"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_FILE="/tmp/jenkins_backup_${TIMESTAMP}.tar.gz"
tar -czf "$BACKUP_FILE" -C /var/jenkins_home .
aws s3 cp "$BACKUP_FILE" "s3://$BACKUP_BUCKET/backups/jenkins_backup_${TIMESTAMP}.tar.gz"
rm -f "$BACKUP_FILE"
EOF
chmod +x /usr/local/bin/jenkins_backup.sh

# Schedule backup
echo "backup_bucket=${backup_bucket}" >> /etc/environment
echo "0 2 * * * root /usr/local/bin/jenkins_backup.sh" >> /etc/crontab