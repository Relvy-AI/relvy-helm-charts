#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
CONNECT_LANGFUSE=false
RELVY_VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --connect_langfuse)
            CONNECT_LANGFUSE=true
            shift
            ;;
        --version)
            RELVY_VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--connect_langfuse] [--version VERSION]"
            echo "  --connect_langfuse: Update existing Relvy installation with Langfuse integration"
            echo "  --version VERSION: Install specific Relvy version (e.g., 0.1.4)"
            exit 1
            ;;
    esac
done

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

#

# If connect_langfuse is provided, handle it as a simple upgrade operation
if [[ "$CONNECT_LANGFUSE" == "true" ]]; then
    print_status "Langfuse connection mode - updating Relvy with Langfuse configuration..."

    # Check if Relvy is installed
    if ! helm list | grep -q "relvy"; then
        print_error "Relvy is not installed. Please install Relvy first before connecting Langfuse."
        exit 1
    fi

    # Load existing values.yaml if it exists
    if [[ -f "my-values.yaml" ]]; then
        print_status "Loading existing values.yaml..."
    else
        print_error "my-values.yaml not found. Please run the full installation first."
        exit 1
    fi

    # Prompt for Langfuse credentials
    echo
    print_status "Langfuse Configuration:"
    prompt_with_default "Langfuse Public Key" "$LANGFUSE_PUBLIC_KEY" "LANGFUSE_PUBLIC_KEY"
    read -s -p "Langfuse Secret Key: " LANGFUSE_SECRET_KEY
    echo
    prompt_with_default "Langfuse Host (optional, leave empty for default)" "$LANGFUSE_HOST" "LANGFUSE_HOST"
    LANGFUSE_HOST=${LANGFUSE_HOST:-""}

    # Update values.yaml with Langfuse configuration
    print_status "Creating langfuse secret..."

    kubectl delete secret relvy-langfuse-secret 2>/dev/null || true
    kubectl create secret generic relvy-langfuse-secret \
      --from-literal=public_key="${LANGFUSE_PUBLIC_KEY}" \
      --from-literal=secret_key="${LANGFUSE_SECRET_KEY}"


    # Restart Relvy
    print_status "Restarting Relvy to apply Langfuse configuration..."

    # Restart the web and celery deployments
    kubectl rollout restart deployment/relvy-web
    kubectl rollout restart deployment/relvy-celery
    kubectl rollout restart deployment/relvy-celery-beat

    # Wait for deployments to be ready
    print_status "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available deployment/relvy-web --timeout=300s
    kubectl wait --for=condition=available deployment/relvy-celery --timeout=300s

    print_success "Relvy upgraded with Langfuse configuration"
    echo
    exit 0
fi

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
print_status "Creating my-values.yaml..."

cat > my-values.yaml << EOF
# Relvy Configuration
# Generated by install.sh on $(date)

# Global configuration

# Web application configuration
web:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
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

# Celery beat scheduler configuration

# Redis configuration

# Database Configuration
database:
  endpoint: "${DB_ENDPOINT}"
  port: ${DB_PORT}
  name: "${DB_NAME}"

# Secrets configuration

# Application Configuration
config:
  serverHostname: "https://${DOMAIN}"

# Persistence configuration
EOF

print_success "my-values.yaml created"

# Create secrets
print_status "Creating Kubernetes secrets..."

# Delete existing secrets if they exist
kubectl delete secret relvy-db-secret relvy-flask-secret relvy-registry-secret 2>/dev/null || true

# Create secrets
kubectl create secret generic relvy-db-secret \
  --from-literal=password="${DB_PASSWORD}" \
  --from-literal=username="${DB_USER}"

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

# Add Relvy Helm repository
print_status "Adding Relvy Helm repository..."
helm repo add relvy https://relvy-ai.github.io/relvy-helm-charts
helm repo update

# Verify chart is available
if ! helm search repo relvy/relvy | grep -q "relvy/relvy"; then
    print_error "Relvy chart not found in repository. Please check the repository URL."
    exit 1
fi

print_success "Relvy Helm repository added successfully"

# Deploy Relvy
print_status "Deploying Relvy..."

# Build helm command with optional version
HELM_CMD=""
if [[ -n "$RELVY_VERSION" ]]; then
    HELM_CMD="--version $RELVY_VERSION"
    print_status "Installing Relvy version: $RELVY_VERSION"
fi

if [[ "$UPGRADE_MODE" == "true" ]]; then
    helm upgrade relvy relvy/relvy -f my-values.yaml $HELM_CMD
    print_success "Relvy upgraded successfully"
else
    helm install relvy relvy/relvy -f my-values.yaml $HELM_CMD
    print_success "Relvy installed successfully"
fi

create_langfuse_values() {
# Create langfuse_values.yaml
print_status "Creating langfuse_values.yaml..."

cat > langfuse_values.yaml << EOF
langfuse:
  salt:
    value: $(openssl rand -hex 16)
  nextauth:
    secret:
      value: $(openssl rand -hex 32)
postgresql:
  auth:
    username: langfuse
    password: $(openssl rand -hex 16)
  primary:
    persistence:
      enabled: false
clickhouse:
  auth:
    password: $(openssl rand -hex 16)
  persistence:
    enabled: false
  replicaCount: 1
redis:
  auth:
    password: $(openssl rand -hex 16)
  primary:
    persistence:
      enabled: false
s3:
  auth:
    rootPassword: "miniosecret"
  persistence:
    enabled: false
EOF

print_success "langfuse_values.yaml created"

}

# Deploy langfuse
if helm list -n langfuse | grep -q "langfuse"; then
  echo "Langfuse is already installed. Skipping deployment."
else
  print_status "Deploying Langfuse..."
  helm repo add langfuse https://langfuse.github.io/langfuse-k8s
  helm repo update

  create_langfuse_values

  # Install Langfuse
  helm install langfuse langfuse/langfuse --namespace langfuse -f langfuse_values.yaml --create-namespace

  print_success "Langfuse deployed successfully"
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
    LB_DNS=$(kubectl get ingress relvy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
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
echo "- my-values.yaml: Your Relvy configuration"
echo "- Install script: install.sh"
echo
print_status "Useful commands:"
echo "- View logs: kubectl logs -f deployment/relvy-web -c web"
echo "- Check status: kubectl get pods -l app.kubernetes.io/name=relvy"
echo "- Upgrade: helm upgrade relvy relvy/relvy -f my-values.yaml"
echo "- Uninstall: helm uninstall relvy"
echo "- Reinstall with saved config: ./install.sh (will use saved values)"
echo

echo
print_warning "Slack Integration Setup Required:"
echo "1. Create a Slack app at https://api.slack.com/apps"
echo "2. Configure webhook URLs:"
echo "   - Slash commands: https://${DOMAIN}/api/slack/slash"
echo "   - Event subscriptions: https://${DOMAIN}/api/slack/webhook"
echo "   - Interactivity: https://${DOMAIN}/api/slack/interaction_webhook"
echo "3. Install the app to your workspace"
echo

print_success "Installation completed successfully!"
