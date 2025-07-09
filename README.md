# Relvy Helm Charts

Deploy Relvy, the AI-powered incident investigation platform, on Kubernetes with minimal configuration.

## 📋 **Required Information for Installation**

Before starting the installation, gather the following information. The interactive installer (`./install.sh`) will prompt you for these values:

### **Database Configuration** (Required)
- **Database Endpoint**: RDS endpoint (e.g., `relvy-app-db.xxxxx.us-east-1.rds.amazonaws.com`) - *Obtained in Step 5*
- **Database Password**: Master password for PostgreSQL database - *Set during Step 5*
- **Database Name**: Must be `relvydb` - *Set during Step 5*
- **Database User**: Usually `postgres` - *Set during Step 5*

### **Domain & SSL Configuration** (Required)
- **Domain Name**: Your custom domain (e.g., `app.yourdomain.com`) - *Configured in Step 6*
- **SSL Certificate ARN**: AWS Certificate Manager ARN - *Obtained in Step 4*

### **Docker Registry Configuration** (Required)
- **Docker Hub Password**: Password for `relvyuser` account - *Provided by Relvy team*

### **Optional Integrations**
- **Slack Client ID & Secret**: For Slack integration - *Optional*

💡 **Pro Tip**: Save these values as you proceed through the setup steps. The installer will save your configuration to `.relvy-install-config` for future use.

## Quick Start

### Prerequisites

- Kubernetes cluster (1.20+)
- Helm 3.0+
- External PostgreSQL database
- Domain name with SSL certificate
- AWS Certificate Manager certificate

### Installation Options

#### Option 1: Interactive Installation (Recommended)
```bash
# Clone the repository
git clone <repository-url>
cd relvy-helm-charts

# Run the interactive installer
./install.sh
```

The installer will prompt you for configuration and save it to `.relvy-install-config` for future use. On subsequent runs, it will pre-populate fields with your saved values.

#### Option 2: Manual Installation
```bash
# Clone the repository
git clone <repository-url>
cd relvy-helm-charts

# Copy and configure values
cp examples/minimal-setup/values.yaml my-values.yaml
# Edit my-values.yaml with your configuration

# Create secrets
kubectl create secret generic relvy-db-secret --from-literal=password=your-database-password
kubectl create secret generic relvy-flask-secret --from-literal=key=your-secure-random-string

# Create Docker registry secret (required for private images)
kubectl create secret docker-registry relvy-registry-secret \
  --docker-server=relvy \
  --docker-username=relvyuser \
  --docker-password=your-password

# Install Relvy
helm install relvy ./charts/relvy -f my-values.yaml
```

## Complete Setup Guide

### Step 1: Install Required Tools

#### macOS
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install kubectl
brew install kubectl

# Install Helm
brew install helm

# Install eksctl (for AWS EKS)
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Install AWS CLI
brew install awscli
```

#### Linux (Ubuntu/Debian)
```bash
# Update package list
sudo apt update

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/

# Install eksctl (for AWS EKS)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

#### Linux (CentOS/RHEL/Fedora)
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/

# Install eksctl (for AWS EKS)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Step 2: Create Kubernetes Cluster

#### AWS EKS (Recommended - Public Subnets)
```bash
# Configure AWS credentials
aws configure

# Create cluster with public subnets (default configuration)
eksctl create cluster \
  --name relvy-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --vpc-public-subnets subnet-xxxxxxxxx,subnet-yyyyyyyyy \
  --vpc-private-subnets subnet-zzzzzzzzz,subnet-wwwwwwwww

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name relvy-cluster
```

**Note**: This configuration uses public subnets for worker nodes, which allows direct internet access for pulling Docker images and making API calls to external services (Slack, SSO providers, etc.).

#### AWS EKS with Private Subnets and NAT Gateway (For Organizations Requiring Enhanced Security)
If your organization requires private subnets for enhanced security, you'll need to set up a NAT Gateway:

```bash
# 1. Create public subnets for NAT Gateway
aws ec2 create-subnet \
  --vpc-id vpc-xxxxxxxxx \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-west-2a \
  --map-public-ip-on-launch

aws ec2 create-subnet \
  --vpc-id vpc-xxxxxxxxx \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-west-2b \
  --map-public-ip-on-launch

# 2. Create Internet Gateway (if not exists)
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id vpc-xxxxxxxxx --internet-gateway-id igw-xxxxxxxxx

# 3. Create route table for public subnets
aws ec2 create-route-table --vpc-id vpc-xxxxxxxxx
aws ec2 create-route --route-table-id rtb-xxxxxxxxx --destination-cidr-block 0.0.0.0/0 --gateway-id igw-xxxxxxxxx

# 4. Allocate Elastic IP for NAT Gateway
aws ec2 allocate-address --domain vpc

# 5. Create NAT Gateway
aws ec2 create-nat-gateway \
  --subnet-id subnet-xxxxxxxxx \
  --allocation-id eipalloc-xxxxxxxxx

# 6. Create route table for private subnets
aws ec2 create-route-table --vpc-id vpc-xxxxxxxxx
aws ec2 create-route --route-table-id rtb-yyyyyyyyy --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-xxxxxxxxx

# 7. Create cluster with private subnets
eksctl create cluster \
  --name relvy-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --vpc-private-subnets subnet-xxxxxxxxx,subnet-yyyyyyyyy

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name relvy-cluster
```

**Cost Note**: NAT Gateway costs approximately $45/month plus data processing fees. Public subnets are free.

#### Network Security Considerations

**Public Subnets (Default Configuration):**
- ✅ **Simpler architecture** with fewer failure points
- ✅ **Same security model** as production GKE clusters
- ✅ **Direct internet access** for Docker pulls and API calls
- ⚠️ **Security depends on proper configuration** of security groups
- ⚠️ **Nodes have public IPs** but are protected by security groups

**Private Subnets with NAT Gateway:**
- ✅ **Enhanced security** with no direct node exposure
- ✅ **Centralized internet access** through NAT Gateway
- ✅ **Better for compliance** requirements
- ❌ **Additional cost** (~$45/month)
- ❌ **More complex architecture** with additional failure points

**Security Best Practices (Both Configurations):**
1. **Security Groups**: Restrict inbound traffic to only what's needed
2. **Network Policies**: Use Kubernetes network policies for pod-to-pod communication
3. **IAM Roles**: Use least-privilege IAM roles for nodes and pods
4. **Monitoring**: Enable VPC Flow Logs and monitor network traffic
5. **Regular Audits**: Review security group configurations regularly

#### Google GKE
```bash
# Install gcloud CLI (if not already installed)
# macOS: brew install google-cloud-sdk
# Linux: Follow instructions at https://cloud.google.com/sdk/docs/install

# Authenticate with Google Cloud
gcloud auth login

# Set project
gcloud config set project your-project-id

# Create cluster
gcloud container clusters create relvy-cluster \
  --zone us-central1-a \
  --num-nodes 3 \
  --machine-type e2-medium \
  --enable-autoscaling \
  --min-nodes 1 \
  --max-nodes 5

# Get credentials
gcloud container clusters get-credentials relvy-cluster --zone us-central1-a
```

#### Local (Docker Desktop/Minikube)
```bash
# For Docker Desktop, ensure Kubernetes is enabled in settings

# For Minikube
# macOS: brew install minikube
# Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube

minikube start --cpus 4 --memory 8192
```

### Step 3: Install AWS Load Balancer Controller (for EKS)

#### Prerequisites
Before installing the AWS Load Balancer Controller, you need to gather cluster information and set up proper IAM permissions.

#### Step 3.1: Gather Cluster Information

First, get your cluster's VPC ID and region:

```bash
# Get cluster name (replace with your actual cluster name)
CLUSTER_NAME="relvy-cluster"
REGION="us-east-1"

# Get VPC ID for the cluster
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

# Get cluster region
CLUSTER_REGION=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.arn' --output text | cut -d: -f4)
echo "Cluster Region: $CLUSTER_REGION"

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
```

#### Step 3.2: Download and Create IAM Policy

```bash
# Download the IAM policy document
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json

# Create the IAM policy (skip if already exists)
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

#### Step 3.3: Create IAM Service Account

```bash
# Create IAM service account with proper permissions
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --region=$REGION \
  --namespace=default \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts
```

#### Step 3.4: Install AWS Load Balancer Controller

```bash
# Add the EKS Helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n default \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$CLUSTER_REGION \
  --set vpcId=$VPC_ID
```

#### Step 3.5: Verify Installation

```bash
# Check if the controller is running
kubectl get deployment aws-load-balancer-controller -n default

# Check pods status
kubectl get pods -n default -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs if there are issues
kubectl logs -n default -l app.kubernetes.io/name=aws-load-balancer-controller
```

The controller should show `2/2` ready replicas and both pods should be in `Running` status.

#### Troubleshooting AWS Load Balancer Controller

If you encounter issues during installation:

1. **Service Account Missing Error**:
   ```bash
   # Create service account manually if needed
   kubectl create serviceaccount aws-load-balancer-controller -n default
   ```

2. **VPC ID Detection Failed**:
   ```bash
   # Explicitly set VPC ID in controller deployment
   kubectl patch deployment aws-load-balancer-controller -n default -p '{"spec":{"template":{"spec":{"containers":[{"name":"aws-load-balancer-controller","args":["--cluster-name='$CLUSTER_NAME'","--ingress-class=alb","--aws-region='$CLUSTER_REGION'","--aws-vpc-id='$VPC_ID'"]}]}}}}'
   ```

3. **Permission Denied Errors**:
   ```bash
   # Verify IAM role annotation on service account
   kubectl describe serviceaccount aws-load-balancer-controller -n default

   # Should show annotation: eks.amazonaws.com/role-arn
   ```

4. **Controller Crashes or CrashLoopBackOff**:
   ```bash
   # Check detailed logs
   kubectl logs -n default -l app.kubernetes.io/name=aws-load-balancer-controller --previous

   # Common fixes:
   # - Ensure VPC ID is correct
   # - Verify IAM permissions
   # - Check if cluster region matches controller region
   ```

### Step 4: Request SSL Certificate (for Custom Domain)

If you're using a custom domain (not the default load balancer URL), you'll need to request an SSL certificate from AWS Certificate Manager.

#### Step 4.1: Request Certificate

```bash
# Request SSL certificate for your domain
aws acm request-certificate \
  --domain-name your-domain.com \
  --validation-method DNS \
  --region us-east-1
```

This will return a certificate ARN that you'll use later.

**📝 Save This Value**: Copy the certificate ARN - you'll need it for the installer and ingress configuration.

#### Step 4.2: Validate Certificate

AWS will provide DNS validation records that you need to add to your domain registrar (GoDaddy, Route53, etc.):

```bash
# Get validation details
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id \
  --region us-east-1
```

Add the CNAME record shown in the output to your DNS provider:
- **Type**: CNAME
- **Name**: `_validation-string.your-domain.com`
- **Value**: `_validation-value.acm-validations.aws.`

#### Step 4.3: Wait for Certificate Validation

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id \
  --region us-east-1 \
  --query 'Certificate.Status' \
  --output text
```

Wait until the status shows `ISSUED` before proceeding.

#### Step 4.4: Configure DNS for Your Domain

Add a CNAME record in your DNS provider pointing to your AWS Load Balancer:
- **Type**: CNAME
- **Name**: `your-subdomain` (e.g., `app` for `app.yourdomain.com`)
- **Value**: `k8s-default-yourapp-1234567890-us-east-1.elb.amazonaws.com`

You can get the load balancer DNS name with:
```bash
kubectl get ingress relvy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 5: Create Database

#### AWS RDS PostgreSQL

Create a PostgreSQL database with the exact specifications required by Relvy:

```bash
# Create RDS instance with Relvy specifications
aws rds create-db-instance \
  --db-instance-identifier relvy-app-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 17.4 \
  --master-username postgres \
  --master-user-password your-secure-password \
  --allocated-storage 50 \
  --storage-type gp3 \
  --max-allocated-storage 200 \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-name relvydb \
  --storage-encrypted \
  --deletion-protection \
  --backup-retention-period 7 \
  --publicly-accessible false

# Get the endpoint
aws rds describe-db-instances --db-instance-identifier relvy-app-db --query 'DBInstances[0].Endpoint.Address' --output text

# 📝 Save This Value: Copy the database endpoint - you'll need it for the installer
```

#### Important Database Requirements

**⚠️ Critical Requirement**: The initial database name must be set to `relvydb` for the Relvy application to work correctly.

**📝 Save These Values**:
- **Database Password**: You'll need this for the installer
- **Database Name**: Must be `relvydb`
- **Database User**: Usually `postgres`

| Specification | Value | Required |
|---------------|-------|----------|
| **Engine** | PostgreSQL | ✅ |
| **Version** | 17.4 or latest | ✅ |
| **Instance Class** | db.t3.medium (minimum) | ✅ |
| **Initial Database Name** | `relvydb` | ✅ |
| **Master Username** | `postgres` | ✅ |
| **Storage** | 50 GB minimum, autoscaling to 200 GB | ✅ |
| **Storage Type** | General Purpose SSD (gp3) | ✅ |
| **Public Access** | No (private only) | ✅ |

#### Configure Database Security

```bash
# Configure RDS Security Group to allow EKS cluster access
# Get EKS cluster security group ID
EKS_SG=$(aws eks describe-cluster --name relvy-cluster --region us-west-2 --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Get RDS security group ID
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier relvy-app-db --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

# Add EKS security group to RDS security group
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG \
  --region us-east-1

# Test database connectivity
aws rds describe-db-instances --db-instance-identifier relvy-app-db --query 'DBInstances[0].DBInstanceStatus' --output text
```

#### Google Cloud SQL
```bash
# Create Cloud SQL instance with Relvy specifications
gcloud sql instances create relvy-app-db \
  --database-version=POSTGRES_17 \
  --tier=db-custom-2-7680 \
  --region=us-central1 \
  --root-password=your-secure-password \
  --storage-size=50GB \
  --storage-type=SSD \
  --storage-auto-increase \
  --storage-auto-increase-limit=200 \
  --backup-start-time=02:00 \
  --enable-bin-log \
  --deletion-protection

# Create database with required name
gcloud sql databases create relvydb --instance=relvy-app-db

# Get the connection name
gcloud sql instances describe relvy-app-db --format="value(connectionName)"
```

## Architecture

Relvy deploys the following components in your Kubernetes cluster:

- **Web**: Flask application with Gunicorn for handling HTTP requests
- **Celery Worker**: Background task processing for AI analysis and integrations
- **Celery Beat**: Scheduled task scheduler for periodic maintenance
- **Redis**: Message broker and caching layer
- **Database Migration Job**: Runs database migrations during deployment

## Scaling

To scale Relvy components based on your load:

```bash
# Scale web replicas for increased HTTP traffic
helm upgrade relvy ./charts/relvy --set web.replicas=4

# Scale celery replicas for increased background processing
helm upgrade relvy ./charts/relvy --set celery.replicas=4

# Scale both simultaneously
helm upgrade relvy ./charts/relvy --set web.replicas=4,celery.replicas=4
```

### Step 6: Configure Domain and DNS

#### Step 6.1: Get Load Balancer DNS Name

First, you need to get the DNS name of your AWS Load Balancer:

```bash
# Get load balancer DNS name
kubectl get ingress relvy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

This will return something like: `k8s-default-relvying-a8f2b3930e-1505874984.us-east-1.elb.amazonaws.com`

**📝 Save This Value**: Copy the load balancer DNS name - you'll need it for your DNS configuration.

#### Step 6.2: Configure DNS Records

**For GoDaddy Users:**
1. Login to your GoDaddy account
2. Go to **My Products** → **Domain** → **Manage**
3. Click on the **DNS** tab
4. Add a **CNAME** record:
   - **Type**: CNAME
   - **Name**: `your-subdomain` (e.g., `app` for `app.yourdomain.com`)
   - **Points to**: `k8s-default-relvying-a8f2b3930e-1505874984.us-east-1.elb.amazonaws.com`
   - **TTL**: 600 (10 minutes)

**For Route53 Users:**
```bash
# Create Route53 hosted zone record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1D633PJN98FT9 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.yourdomain.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "k8s-default-relvying-a8f2b3930e-1505874984.us-east-1.elb.amazonaws.com"}]
      }
    }]
  }'
```

#### Step 6.3: Verify DNS Propagation

```bash
# Check DNS resolution
nslookup app.yourdomain.com

# Test connectivity
curl -I https://app.yourdomain.com/health
```

DNS propagation typically takes 5-30 minutes.

**📝 Save This Value**: Copy your domain name - you'll need it for the installer.

#### Step 6.4: Update Ingress Configuration

After your certificate is validated and DNS is configured, update your ingress to use the new domain:

```bash
# Update ingress hostname
kubectl patch ingress relvy-ingress -p '{"spec":{"rules":[{"host":"app.yourdomain.com","http":{"paths":[{"backend":{"service":{"name":"relvy-web","port":{"number":80}}},"path":"/","pathType":"Prefix"}]}}],"tls":[{"hosts":["app.yourdomain.com"],"secretName":"relvy-tls"}]}}'

# Update certificate ARN annotation
kubectl patch ingress relvy-ingress -p '{"metadata":{"annotations":{"alb.ingress.kubernetes.io/certificate-arn":"arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"}}}'
```

### Step 7: Deploy Relvy

#### Using the Interactive Installer
```bash
# Clone repository
git clone <repository-url>
cd relvy-helm-charts

# Run the installer
./install.sh
```

The installer will prompt you for:
- Database endpoint and credentials
- Domain name
- AWS Certificate Manager ARN
- Optional Slack integration

#### Manual Deployment
```bash
# Clone repository
git clone <repository-url>
cd relvy-helm-charts

# Configure values
cp examples/minimal-setup/values.yaml my-values.yaml
# Edit my-values.yaml with your configuration

# Create secrets
kubectl create secret generic relvy-db-secret \
  --from-literal=password=your-database-password

kubectl create secret generic relvy-flask-secret \
  --from-literal=key=your-secure-random-string

# Install Relvy
helm install relvy ./charts/relvy -f my-values.yaml
```

### Step 8: Verify Installation

```bash
# Check all pods are running
kubectl get pods -l app.kubernetes.io/name=relvy

# Check services
kubectl get services -l app.kubernetes.io/name=relvy

# Check ingress
kubectl get ingress -l app.kubernetes.io/name=relvy

# Access the application
curl -I https://relvy.yourdomain.com
```

## Configuration

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `global.imageRegistry` | Docker registry URL | `docker.io` |
| `database.external.endpoint` | Database endpoint | `relvy-db.xxxxx.us-east-1.rds.amazonaws.com` |
| `database.external.password` | Database password | `your-secure-password` |
| `config.serverHostname` | Your domain | `https://app.yourdomain.com` |
| `config.flaskSecretKey` | Random secret key | `your-secure-random-string` |
| `web.ingress.hosts[0].host` | Ingress hostname | `app.yourdomain.com` |
| `web.ingress.annotations.alb.ingress.kubernetes.io/certificate-arn` | AWS Certificate Manager ARN | `arn:aws:acm:us-east-1:123456789012:certificate/xxxxx` |

### Important Configuration Notes

1. **Domain Configuration**: Ensure your `config.serverHostname` and `web.ingress.hosts[0].host` match your actual domain
2. **Certificate Region**: SSL certificates must be in `us-east-1` region for ALB
3. **Database SSL**: Set `database.external.sslMode: require` for production
4. **Resource Limits**: Adjust `celery.resources` based on your workload requirements
5. **Redis Configuration**: `redis.enabled: true` is required for Celery functionality

### Example values.yaml

```yaml
global:
  imageRegistry: "docker.io"
  imagePullSecrets:
    - name: relvy-registry-secret

database:
  external:
    enabled: true
    endpoint: "relvy-app-db.xxxxx.us-east-1.rds.amazonaws.com"
    name: "relvydb"
    user: "postgres"
    password: "your-secure-password"
    sslMode: "require"

config:
  serverHostname: "https://app.yourdomain.com"
  flaskSecretKey: "your-secure-random-string"
  environment: "production"

web:
  ingress:
    enabled: true
    className: "alb"
    hosts:
      - host: "app.yourdomain.com"
        paths:
          - path: "/"
            pathType: "Prefix"
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"
      alb.ingress.kubernetes.io/scheme: "internet-facing"
      alb.ingress.kubernetes.io/target-type: "ip"

redis:
  enabled: true

celery:
  enabled: true
  resources:
    limits:
      cpu: "2000m"
      memory: "4Gi"
    requests:
      cpu: "1000m"
      memory: "2Gi"
```

### Docker Registry Configuration

Relvy uses Docker Hub for image hosting. You need to:

1. **Create a Docker registry secret**:
   ```bash
   kubectl create secret docker-registry relvy-registry-secret \
     --docker-server=docker.io \
     --docker-username=relvyuser \
     --docker-password=your-password
   ```

2. **The values.yaml is pre-configured** with:
   ```yaml
   global:
     imageRegistry: "docker.io"
     imagePullSecrets:
       - name: relvy-registry-secret
   ```

3. **Image repository is fixed** as `relvy/relvy-app-onprem:latest`

### Optional Integrations

#### Slack Integration
```yaml
config:
  slack:
    enabled: true
    clientId: "your-slack-client-id"
    clientSecret: "your-slack-client-secret"
```

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```bash
   # Check database connectivity
   kubectl exec -it deployment/relvy-web -- nc -zv your-db-endpoint 5432
   ```

2. **SSL Certificate Issues**
   ```bash
   # Check certificate status in AWS Certificate Manager
   aws acm describe-certificate --certificate-arn your-certificate-arn
   ```

3. **Ingress Not Working**
   ```bash
   # Check AWS Load Balancer Controller
   kubectl get pods | grep aws-load-balancer-controller
   kubectl describe ingress relvy-web
   ```

4. **AWS Load Balancer Controller Deployment Issues**
   ```bash
   # Check if service account exists
   kubectl get serviceaccount aws-load-balancer-controller -n default

   # Check if IAM role is properly annotated
   kubectl describe serviceaccount aws-load-balancer-controller -n default

   # Check deployment status
   kubectl get deployment aws-load-balancer-controller -n default

   # Check replica set events
   kubectl describe replicaset -n default -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

   **Common Issues**:
   - **Service Account Missing**: `serviceaccount "aws-load-balancer-controller" not found`
   - **VPC ID Detection Failed**: `failed to get VPC ID: failed to fetch VPC ID from instance metadata`
   - **Permission Denied**: IAM role not properly attached to service account

   **Solutions**:
   ```bash
   # Create service account if missing
   kubectl create serviceaccount aws-load-balancer-controller -n default

   # Add IAM role with proper permissions
   eksctl create iamserviceaccount \
     --cluster=your-cluster-name \
     --region=your-region \
     --namespace=default \
     --name=aws-load-balancer-controller \
     --role-name AmazonEKSLoadBalancerControllerRole \
     --attach-policy-arn=arn:aws:iam::your-account-id:policy/AWSLoadBalancerControllerIAMPolicy \
     --approve \
     --override-existing-serviceaccounts

   # Fix VPC ID detection by patching deployment
   VPC_ID=$(aws eks describe-cluster --name your-cluster-name --region your-region --query 'cluster.resourcesVpcConfig.vpcId' --output text)
   kubectl patch deployment aws-load-balancer-controller -n default -p '{"spec":{"template":{"spec":{"containers":[{"name":"aws-load-balancer-controller","args":["--cluster-name=your-cluster-name","--ingress-class=alb","--aws-region=your-region","--aws-vpc-id='$VPC_ID'"]}]}}}}'
   ```

5. **Image Pull Failures (Network Connectivity)**
   ```bash
   # Check if pods can reach internet
   kubectl run connectivity-test --image=busybox --rm -it --restart=Never -- sh -c "
   echo 'Testing internet connectivity...'
   ping -c 3 8.8.8.8
   echo 'Testing Docker Hub...'
   wget -qO- --timeout=10 https://registry-1.docker.io/v2/ || echo 'Docker Hub failed'
   "

   # Check if using private subnets without NAT Gateway
   aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(aws eks describe-cluster --name your-cluster-name --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

   # Check subnet configuration
   aws ec2 describe-subnets --subnet-ids $(aws eks describe-cluster --name your-cluster-name --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
   ```

   **Solution**: If you're using private subnets, you need either:
   - **Public subnets** (recommended for simplicity)
   - **NAT Gateway** (for enhanced security)

6. **Database Connection Timeout**
   ```bash
   # Check if RDS security group allows EKS cluster access
   EKS_SG=$(aws eks describe-cluster --name your-cluster-name --region your-region --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
   RDS_SG=$(aws rds describe-db-instances --db-instance-identifier your-db-name --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

   # Add EKS security group to RDS security group
   aws ec2 authorize-security-group-ingress \
     --group-id $RDS_SG \
     --protocol tcp \
     --port 5432 \
     --source-group $EKS_SG \
     --region your-region
   ```

   **Solution**: RDS security group must allow inbound connections from your EKS cluster's security group.

7. **AWS Load Balancer Controller Region Issue**
   ```bash
   # Fix controller region detection
   helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n default \
     --set clusterName=your-cluster-name \
     --set serviceAccount.create=true \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set awsRegion=your-region
   ```

   **Solution**: Explicitly set the AWS region for the controller.

8. **Celery Workers in CrashLoopBackOff**
   ```bash
   # Check pod events for liveness probe failures
   kubectl describe pod -l app.kubernetes.io/component=celery

   # Check for liveness probe timeout errors
   kubectl get events --sort-by=.metadata.creationTimestamp | grep -i "liveness probe failed"
   ```

   **Common Issues**:
   - **Liveness Probe Timeout**: `command timed out: "celery -A make_celery inspect ping" timed out after 1s`
   - **Insufficient Resources**: Celery workers running out of memory
   - **Redis Connection Issues**: Cannot connect to Redis service

   **Solutions**:
   ```bash
   # Fix liveness probe timeout
   kubectl patch deployment relvy-celery -p '{"spec":{"template":{"spec":{"containers":[{"name":"celery","livenessProbe":{"timeoutSeconds":10,"periodSeconds":60}}]}}}}'

   # Check Redis connectivity from Celery pod
   kubectl exec -it deployment/relvy-celery -- redis-cli -h relvy-redis ping

   # Increase resource limits if needed
   kubectl patch deployment relvy-celery -p '{"spec":{"template":{"spec":{"containers":[{"name":"celery","resources":{"limits":{"memory":"6Gi","cpu":"3000m"}}}]}}}}'
   ```

9. **Redis Service Not Found**
   ```bash
   # Check if Redis service exists
   kubectl get service relvy-redis

   # Check if Redis deployment is running
   kubectl get deployment relvy-redis

   # Check Redis pod logs
   kubectl logs -l app.kubernetes.io/component=redis
   ```

   **Common Issues**:
   - **Service Missing**: Redis service not created during Helm install
   - **DNS Resolution**: Pods can't resolve `relvy-redis` hostname
   - **Failed Helm Install**: Helm release failed, leaving incomplete resources

   **Solutions**:
   ```bash
   # If service is missing, create it manually
   kubectl create service clusterip relvy-redis --tcp=6379:6379

   # Or reinstall Helm chart completely
   helm uninstall relvy
   helm install relvy ./charts/relvy -f values.yaml

   # Test Redis connectivity
   kubectl run redis-test --image=redis:alpine --rm -it --restart=Never -- redis-cli -h relvy-redis ping
   ```

### Logs

```bash
# Web server logs
kubectl logs -f deployment/relvy-web -c web

# Celery worker logs
kubectl logs -f deployment/relvy-celery -c celery

# Celery beat logs
kubectl logs -f deployment/relvy-celery-beat -c celery-beat
```

### Health Checks

```bash
# Check all components
kubectl get pods -l app.kubernetes.io/name=relvy
kubectl get services -l app.kubernetes.io/name=relvy
kubectl get ingress -l app.kubernetes.io/name=relvy

# Test health endpoint
curl https://relvy.yourdomain.com/health
```

## Upgrading

```bash
# Update Helm repository
helm repo update

# Upgrade Relvy
helm upgrade relvy ./charts/relvy -f my-values.yaml
```

## Uninstalling

```bash
# Uninstall Relvy
helm uninstall relvy

# Delete secrets (optional)
kubectl delete secret relvy-db-secret relvy-flask-secret
```

## Support

- [Relvy Documentation](https://docs.relvy.ai)
- [GitHub Issues](https://github.com/relvy/relvy-helm-charts/issues)
- [Community Discord](https://discord.gg/relvy)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request