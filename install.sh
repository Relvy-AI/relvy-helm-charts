#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file
CONFIG_FILE=".relvy-install-config"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate domain
validate_domain() {
    local domain=$1
    # Updated regex to be more permissive - allows subdomains and common TLDs
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to generate random string
generate_random_string() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to load saved configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_status "Loading saved configuration..."
        source "$CONFIG_FILE"
    else
        print_status "No saved configuration found, proceeding with fresh setup."
    fi
    return 0
}

# Function to save configuration
save_config() {
    print_status "Saving configuration for future use..."
    cat > "$CONFIG_FILE" << EOF
# Relvy Installation Configuration
# Generated on $(date)
# This file contains your configuration for future installations

# Database Configuration
DB_ENDPOINT="$DB_ENDPOINT"
DB_PORT="$DB_PORT"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"

# Domain Configuration
DOMAIN="$DOMAIN"
CERT_ARN="$CERT_ARN"

# Docker Registry Configuration
DOCKER_REGISTRY="$DOCKER_REGISTRY"
DOCKER_USERNAME="$DOCKER_USERNAME"

# Slack Configuration
SLACK_ENABLED="$SLACK_ENABLED"
SLACK_CLIENT_ID="$SLACK_CLIENT_ID"
EOF
    print_success "Configuration saved to $CONFIG_FILE"
}

# Function to prompt with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " input
        if [[ -z "$input" ]]; then
            input="$default"
        fi
    else
        read -p "$prompt: " input
    fi

    eval "$var_name=\"$input\""
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists kubectl; then
    print_error "kubectl is not installed. Please install kubectl first."
    echo
    print_status "Installation instructions:"
    echo "  macOS: brew install kubectl"
    echo "  Linux: curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
    exit 1
fi

if ! command_exists helm; then
    print_error "Helm is not installed. Please install Helm first."
    echo
    print_status "Installation instructions:"
    echo "  macOS: brew install helm"
    echo "  Linux: curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz && sudo mv linux-amd64/helm /usr/local/bin/"
    exit 1
fi

# Check if we can connect to Kubernetes cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "Cannot connect to Kubernetes cluster. Please ensure your cluster is running and accessible."
    exit 1
fi

print_success "Prerequisites check passed"

# Welcome message
echo
echo "=========================================="
echo "    Relvy Kubernetes Installation"
echo "=========================================="
echo
print_status "This script will help you deploy Relvy on your Kubernetes cluster."
echo

# Check if Relvy is already installed
if helm list | grep -q "relvy"; then
    print_warning "Relvy is already installed. Do you want to upgrade it? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled."
        exit 0
    fi
    UPGRADE_MODE=true
else
    UPGRADE_MODE=false
fi

# Load saved configuration
load_config

# Collect configuration
echo
print_status "Please provide the following configuration:"
echo

# Database configuration
print_status "Database Configuration:"
prompt_with_default "Database endpoint (e.g., relvy-app-db.xxxxx.us-east-1.rds.amazonaws.com)" "$DB_ENDPOINT" "DB_ENDPOINT"
read -s -p "Database password: " DB_PASSWORD
echo
prompt_with_default "Database name" "${DB_NAME:-relvydb}" "DB_NAME"
DB_NAME=${DB_NAME:-relvydb}
prompt_with_default "Database user" "${DB_USER:-postgres}" "DB_USER"
DB_USER=${DB_USER:-postgres}
prompt_with_default "Database port" "${DB_PORT:-5432}" "DB_PORT"
DB_PORT=${DB_PORT:-5432}

# Domain configuration
echo
print_status "Domain Configuration:"
while true; do
    prompt_with_default "Your domain (e.g., relvy.yourdomain.com)" "$DOMAIN" "DOMAIN"
    if validate_domain "$DOMAIN"; then
        break
    else
        print_error "Invalid domain format. Please enter a valid domain."
    fi
done

# AWS Certificate Manager ARN
echo
print_status "AWS Certificate Manager Configuration:"
prompt_with_default "AWS Certificate Manager ARN (e.g., arn:aws:acm:us-east-1:123456789012:certificate/xxxxx)" "$CERT_ARN" "CERT_ARN"

# Optional integrations
echo
print_status "Optional Integrations:"
prompt_with_default "Enable Slack integration? (y/N)" "$SLACK_ENABLED" "SLACK_ENABLED"
if [[ "$SLACK_ENABLED" =~ ^[Yy]$ ]]; then
    prompt_with_default "Slack Client ID" "$SLACK_CLIENT_ID" "SLACK_CLIENT_ID"
    read -s -p "Slack Client Secret: " SLACK_CLIENT_SECRET
    echo
    SLACK_ENABLED=true
else
    SLACK_ENABLED=false
    SLACK_CLIENT_ID=""
    SLACK_CLIENT_SECRET=""
fi

# Docker Registry Configuration
echo
print_status "Docker Registry Configuration:"
print_status "Using registry: Docker Hub (docker.io)"
print_status "Using username: relvyuser"
read -s -p "Docker Hub password: " DOCKER_PASSWORD
echo

# Set fixed values for Docker Hub
DOCKER_REGISTRY="docker.io"
DOCKER_USERNAME="relvyuser"

# Validate password
if [[ -z "$DOCKER_PASSWORD" ]]; then
    print_error "Docker Hub password is required."
    exit 1
fi

# Debug: Check if password was captured (show length only)
PASSWORD_LENGTH=${#DOCKER_PASSWORD}
print_status "Password captured: ${PASSWORD_LENGTH} characters"
if [[ $PASSWORD_LENGTH -eq 0 ]]; then
    print_error "Password is empty!"
    exit 1
fi

# Generate random secrets
FLASK_SECRET_KEY=$(generate_random_string)

# Create values.yaml
print_status "Creating values.yaml..."

cat > values.yaml << EOF
# Relvy Configuration
# Generated by install.sh on $(date)

# Global configuration
global:
  environment: production
  imageRegistry: ${DOCKER_REGISTRY}
  imageTag: latest
  imagePullPolicy: Always
  imagePullSecrets:
    - name: relvy-registry-secret

# Web application configuration
web:
  enabled: true
  replicas: 2
  image:
    repository: relvy/relvy-app-onprem
    tag: latest
    pullPolicy: Always

  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

  service:
    type: ClusterIP
    port: 80
    targetPort: 8000

  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/ssl-redirect: '443'
      alb.ingress.kubernetes.io/healthcheck-path: /health
      alb.ingress.kubernetes.io/healthcheck-port: traffic-port
      alb.ingress.kubernetes.io/success-codes: '200'
    hosts:
      - host: ${DOMAIN}
        paths:
          - path: /
            pathType: Prefix
    tls:
      - secretName: relvy-tls
        hosts:
          - ${DOMAIN}

# Celery worker configuration
celery:
  enabled: true
  replicas: 2
  image:
    repository: relvy/relvy-app-onprem
    tag: latest
    pullPolicy: Always

  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

# Celery beat scheduler configuration
celeryBeat:
  enabled: true
  replicas: 1
  image:
    repository: relvy/relvy-app-onprem
    tag: latest
    pullPolicy: Always

  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

# Redis configuration
redis:
  enabled: true
  image:
    repository: redis
    tag: 7-alpine
    pullPolicy: IfNotPresent

  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

  service:
    type: ClusterIP
    port: 6379
    targetPort: 6379

# Database Configuration
database:
  external:
    enabled: true
    endpoint: "${DB_ENDPOINT}"
    port: ${DB_PORT}
    name: "${DB_NAME}"
    user: "${DB_USER}"
    password: "${DB_PASSWORD}"
    sslMode: "require"

# Secrets configuration
secrets:
  database: relvy-db-secret
  slack: relvy-slack-secret
  flask: relvy-flask-secret

# Application Configuration
config:
  serverHostname: "https://${DOMAIN}"
  environment: "production"

  # LLM Configuration
  llmClient: "openai"
  llmModel: "gpt-4"
  heavyLlmClient: "openai"
  heavyLlmModel: "gpt-4"
  reasoningLlmClient: "openai"
  reasoningLlmModel: "gpt-4"

  flaskSecretKey: "${FLASK_SECRET_KEY}"

  # Slack Integration
  slack:
    enabled: ${SLACK_ENABLED}
    clientId: "${SLACK_CLIENT_ID}"
    clientSecret: "${SLACK_CLIENT_SECRET}"

# Persistence configuration
persistence:
  enabled: true
  storageClass: ""
  size: 10Gi
EOF

print_success "values.yaml created"

# Create secrets
print_status "Creating Kubernetes secrets..."

# Delete existing secrets if they exist
kubectl delete secret relvy-db-secret relvy-flask-secret relvy-registry-secret 2>/dev/null || true

# Create secrets
kubectl create secret generic relvy-db-secret \
  --from-literal=password="${DB_PASSWORD}"

kubectl create secret generic relvy-flask-secret \
  --from-literal=key="${FLASK_SECRET_KEY}"

# Create Docker registry secret
kubectl create secret docker-registry relvy-registry-secret \
  --docker-server="${DOCKER_REGISTRY}" \
  --docker-username="${DOCKER_USERNAME}" \
  --docker-password="${DOCKER_PASSWORD}"

# Validate the secret was created correctly
print_status "Validating Docker registry secret..."
if kubectl get secret relvy-registry-secret >/dev/null 2>&1; then
    print_success "Docker registry secret created successfully"

    # Simple check: verify the secret has the .dockerconfigjson field
    if kubectl get secret relvy-registry-secret -o jsonpath='{.data.\.dockerconfigjson}' >/dev/null 2>&1; then
        print_success "Docker config field found in secret"

        # Simple verification: check if the config contains docker.io
        DOCKER_CONFIG_B64=$(kubectl get secret relvy-registry-secret -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null || echo "")
        if [[ -n "$DOCKER_CONFIG_B64" ]]; then
            print_success "Docker config data is present"

            # Decode and check for docker.io
            DOCKER_CONFIG=$(echo "$DOCKER_CONFIG_B64" | base64 -d 2>/dev/null || echo "")
            if echo "$DOCKER_CONFIG" | grep -q "docker.io"; then
                print_success "Docker Hub registry verified in config"
            else
                print_error "Docker Hub registry not found in config!"
                exit 1
            fi
        else
            print_error "Docker config data is empty!"
            exit 1
        fi
    else
        print_error "Docker config field not found in secret!"
        print_status "Secret contents:"
        kubectl get secret relvy-registry-secret -o yaml
        exit 1
    fi
else
    print_error "Failed to create Docker registry secret"
    exit 1
fi

# Create optional secrets
if [[ "$SLACK_ENABLED" == "true" ]]; then
    kubectl delete secret relvy-slack-secret 2>/dev/null || true
    kubectl create secret generic relvy-slack-secret \
      --from-literal=SLACK_CLIENT_ID="${SLACK_CLIENT_ID}" \
      --from-literal=SLACK_CLIENT_SECRET="${SLACK_CLIENT_SECRET}"
fi

print_success "Secrets created"

# Check if AWS Load Balancer Controller is installed
print_status "Checking AWS Load Balancer Controller installation..."
if ! helm list | grep -q "aws-load-balancer-controller"; then
    print_warning "AWS Load Balancer Controller is not installed. Installing..."

    # Add eks repository
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update

    # Install AWS Load Balancer Controller in default namespace
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n default \
      --set clusterName=$(kubectl config current-context | cut -d'/' -f2) \
      --set serviceAccount.create=true \
      --set serviceAccount.name=aws-load-balancer-controller

    print_success "AWS Load Balancer Controller installed"
else
    print_success "AWS Load Balancer Controller is already installed"

    # Check if the controller pods are running
    if ! kubectl get pods -n default 2>/dev/null | grep -q "aws-load-balancer-controller"; then
        print_warning "AWS Load Balancer Controller is installed but pods are not running. Checking status..."
        helm status aws-load-balancer-controller
        print_warning "You may need to check the controller configuration or IAM permissions."
    fi
fi

# Save configuration for future use
save_config

# Deploy Relvy
print_status "Deploying Relvy..."

if [[ "$UPGRADE_MODE" == "true" ]]; then
    helm upgrade relvy ./charts/relvy -f values.yaml
    print_success "Relvy upgraded successfully"
else
    helm install relvy ./charts/relvy -f values.yaml
    print_success "Relvy installed successfully"
fi

# Wait for deployment
print_status "Waiting for Relvy to be ready..."
kubectl wait --for=condition=available deployment/relvy-web --timeout=600s
kubectl wait --for=condition=available deployment/relvy-celery --timeout=600s
kubectl wait --for=condition=available deployment/relvy-celery-beat --timeout=600s

print_success "All deployments are ready"


# Get load balancer DNS name
print_status "Getting load balancer DNS name..."
LB_DNS=""
for i in {1..30}; do
    LB_DNS=$(kubectl get ingress relvy-web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$LB_DNS" ]]; then
        break
    fi
    print_status "Waiting for load balancer DNS... (attempt $i/30)"
    sleep 10
done

if [[ -n "$LB_DNS" ]]; then
    print_success "Load balancer DNS: $LB_DNS"
    echo
    print_warning "IMPORTANT: Please create the following DNS records:"
    echo "  ${DOMAIN} → ${LB_DNS}"
    if [[ "$SLACK_ENABLED" == "true" ]]; then
        echo "  api.${DOMAIN} → ${LB_DNS}"
    fi
    echo
else
    print_warning "Could not get load balancer DNS. Please check your AWS Load Balancer Controller."
fi

# Final status
echo
echo "=========================================="
echo "    Installation Complete!"
echo "=========================================="
echo
print_success "Relvy has been deployed successfully!"
echo
print_status "Next steps:"
echo "1. Create DNS records pointing to your load balancer DNS"
echo "2. Wait for SSL certificate to be validated (may take a few minutes)"
echo "3. Access Relvy at: https://${DOMAIN}"
echo "4. Check status with: kubectl get pods -l app.kubernetes.io/name=relvy"
echo
print_status "Configuration files:"
echo "- values.yaml: Your Relvy configuration"
echo "- $CONFIG_FILE: Your saved configuration (for future installations)"
echo "- Install script: install.sh"
echo
print_status "Useful commands:"
echo "- View logs: kubectl logs -f deployment/relvy-web -c web"
echo "- Check status: kubectl get pods -l app.kubernetes.io/name=relvy"
echo "- Upgrade: helm upgrade relvy ./charts/relvy -f values.yaml"
echo "- Uninstall: helm uninstall relvy"
echo "- Reinstall with saved config: ./install.sh (will use saved values)"
echo

if [[ "$SLACK_ENABLED" == "true" ]]; then
    echo
    print_warning "Slack Integration Setup Required:"
    echo "1. Create a Slack app at https://api.slack.com/apps"
    echo "2. Configure webhook URLs:"
    echo "   - Slash commands: https://api.${DOMAIN}/api/slack/slash"
    echo "   - Event subscriptions: https://api.${DOMAIN}/api/slack/webhook"
    echo "   - Interactivity: https://api.${DOMAIN}/api/slack/interaction_webhook"
    echo "   - OAuth redirect: https://api.${DOMAIN}/slack/redirect"
    echo "3. Install the app to your workspace"
    echo
fi

print_success "Installation completed successfully!"