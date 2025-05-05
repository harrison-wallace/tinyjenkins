#!/bin/bash
# Log all output to /var/log/user-data.log for debugging purposes
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

# Configure HTTPS with Nginx if enabled
if [ "${enable_https}" = "true" ]; then
  # Install Nginx
  amazon-linux-extras install nginx1 -y || { echo "Failed to install Nginx"; exit 1; }
  nginx -v || { echo "Nginx not installed correctly"; exit 1; }

  # Retrieve ACM certificate
  mkdir -p /etc/nginx/certs || { echo "Failed to create /etc/nginx/certs"; exit 1; }
  aws acm export-certificate --certificate-arn ${cert_arn} --passphrase $(openssl rand -base64 12) --region ${region} > /tmp/cert.json || { echo "Failed to export ACM certificate"; exit 1; }
  jq -r '.Certificate' /tmp/cert.json > /etc/nginx/certs/cert.pem
  jq -r '.PrivateKey' /tmp/cert.json > /etc/nginx/certs/key.pem
  rm -f /tmp/cert.json

  # Configure Nginx
  cat << 'EOF' > /etc/nginx/conf.d/jenkins.conf
server {
    listen 443 ssl;
    server_name jenkins.${domain_name};

    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
server {
    listen 80;
    server_name jenkins.${domain_name};
    return 301 https://$host$request_uri;
}
EOF

  # Start Nginx
  systemctl enable nginx || { echo "Failed to enable Nginx"; exit 1; }
  systemctl start nginx || { echo "Failed to start Nginx"; exit 1; }
fi

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