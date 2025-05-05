#!/bin/bash
# Log all output to /var/log/user-data.log for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Update system and install Docker
yum update -y || { echo "Failed to update system"; exit 1; }
yum install -y docker || { echo "Failed to install Docker"; exit 1; }
usermod -aG docker ec2-user
systemctl enable docker || { echo "Failed to enable Docker"; exit 1; }
systemctl start docker || { echo "Failed to start Docker"; exit 1; }

# Verify Docker installation
if ! command -v /usr/bin/docker &>/dev/null; then
  echo "Docker binary not found"
  exit 1
fi

# Wait for Docker to be fully operational
for i in {1..10}; do
  if /usr/bin/docker info &>/dev/null; then
    echo "Docker is operational"
    break
  fi
  echo "Waiting for Docker to start... Attempt $i"
  sleep 5
  if [ $i -eq 10 ]; then
    echo "Docker failed to start"
    exit 1
  fi
done

# Create and set ownership for Jenkins home directory
mkdir -p /var/jenkins_home || { echo "Failed to create /var/jenkins_home"; exit 1; }
chown 1000:1000 /var/jenkins_home || { echo "Failed to set ownership for /var/jenkins_home"; exit 1; }
chmod 700 /var/jenkins_home || { echo "Failed to set permissions for /var/jenkins_home"; exit 1; }

# Run Jenkins container from custom image
/usr/bin/docker run -d -p 8080:8080 -p 50000:50000 -v /var/jenkins_home:/var/jenkins_home --name jenkins harrisoncloudengineer/tinyjenkins:latest || { echo "Failed to start Jenkins container"; exit 1; }

# Install AWS CLI
yum install -y awscli || { echo "Failed to install AWS CLI"; exit 1; }

# Create backup script
cat << 'EOF' > /usr/local/bin/jenkins_backup.sh
#!/bin/bash
BACKUP_BUCKET="${backup_bucket}"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_FILE="/tmp/jenkins_backup_$${TIMESTAMP}.tar.gz"
tar -czf "$BACKUP_FILE" -C /var/jenkins_home .
aws s3 cp "$BACKUP_FILE" "s3://$BACKUP_BUCKET/backups/jenkins_backup_$${TIMESTAMP}.tar.gz"
rm -f "$BACKUP_FILE"
EOF
chmod +x /usr/local/bin/jenkins_backup.sh

# Schedule backup
echo "backup_bucket=${backup_bucket}" >> /etc/environment
echo "0 2 * * * root /usr/local/bin/jenkins_backup.sh" >> /etc/crontab