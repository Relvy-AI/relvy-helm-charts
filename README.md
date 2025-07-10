# Relvy Helm Charts

Deploy Relvy, the AI-powered incident investigation platform, on Kubernetes with minimal configuration.

## Table of Contents

- [📋 Required Information for Installation](#-required-information-for-installation)
- [Complete Setup Guide](#complete-setup-guide)
  - [Prerequisites](#prerequisites)
  - [Step 1: Install Required Tools](#step-1-install-required-tools)
  - [Step 2: Create Kubernetes Cluster](#step-2-create-kubernetes-cluster)
  - [Step 3: Install AWS Load Balancer Controller](#step-3-install-aws-load-balancer-controller-for-eks)
  - [Step 4: Request SSL Certificate](#step-4-request-ssl-certificate-for-custom-domain)
  - [Step 5: Create Database](#step-5-create-database)
  - [Step 6: Deploy Relvy](#step-6-deploy-relvy)
  - [Step 7: Configure Domain and DNS](#step-7-configure-domain-and-dns)
  - [Step 8: Verify Installation](#step-8-verify-installation)
- [Architecture](#architecture)
- [Scaling](#scaling)
- [Troubleshooting](#troubleshooting)
- [Upgrading](#upgrading)
- [Uninstalling](#uninstalling)
- [Support](#support)

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

## Complete Setup Guide

### Prerequisites

- Kubernetes cluster (1.20+)
- Helm 3.0+
- External PostgreSQL database
- Domain name with SSL certificate
- AWS Certificate Manager certificate


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

# Set your AWS region
aws configure set region us-east-1

# Create cluster with public subnets (default configuration)
eksctl create cluster \
  --name relvy-cluster \
  --nodegroup-name standard-workers \
  --node-type t3.xlarge \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --vpc-public-subnets subnet-xxxxxxxxx,subnet-yyyyyyyyy

# Update kubeconfig
aws eks update-kubeconfig --name relvy-cluster
```

**Note**: This configuration uses public subnets for worker nodes, which allows direct internet access for pulling Docker images and making API calls to external services (Slack, SSO providers, etc.).

#### AWS EKS with Private Subnets and NAT Gateway (For Organizations Requiring Enhanced Security)
If your organization requires private subnets for enhanced security, you'll need to set up a NAT Gateway:

```bash
# 1. Create public subnets for NAT Gateway
aws ec2 create-subnet \
  --vpc-id vpc-xxxxxxxxx \
  --cidr-block 10.0.1.0/24 \
  --availability-zone <availability-zone> \
  --map-public-ip-on-launch

aws ec2 create-subnet \
  --vpc-id vpc-xxxxxxxxx \
  --cidr-block 10.0.2.0/24 \
  --availability-zone <availability-zone> \
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
  --nodegroup-name standard-workers \
  --node-type t3.xlarge \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed \
  --vpc-private-subnets subnet-xxxxxxxxx,subnet-yyyyyyyyy

# Update kubeconfig
aws eks update-kubeconfig --name relvy-cluster
```

**Cost Note**: NAT Gateway costs approximately $45/month plus data processing fees. Public subnets are free.

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
CLUSTER_NAME="relvy-cluster"

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
echo "VPC ID: $VPC_ID"

CLUSTER_REGION=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.arn' --output text | cut -d: -f4)
echo "Cluster Region: $CLUSTER_REGION"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
```

#### Step 3.2: Download and Create IAM Policy (Skip if you already have the policy)

```bash
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

#### Step 3.3: Create IAM Service Account

```bash
eksctl utils associate-iam-oidc-provider --cluster=$CLUSTER_NAME --approve
```

```bash
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=default \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts
```

#### Step 3.4: Install AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

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
aws acm request-certificate \
  --domain-name your-domain.com \
  --validation-method DNS
```

This will return a certificate ARN that you'll use later.

**📝 Save This Value**: Copy the certificate ARN - you'll need it for the installer and ingress configuration.

```bash
CERTIFICATE_ARN=<your-certificate-arn>
```

#### Step 4.2: Validate Certificate

AWS will provide DNS validation records that you need to add to your domain registrar (GoDaddy, Route53, etc.):

```bash
aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN
```

Add the CNAME record shown in the output to your DNS provider:
- **Type**: CNAME
- **Name**: `_validation-string.your-domain.com`
- **Value**: `_validation-value.acm-validations.aws.`

#### Step 4.3: Wait for Certificate Validation

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query 'Certificate.Status' \
  --output text
```

Wait until the status shows `ISSUED` before proceeding.

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
  --allocated-storage 100 \
  --storage-type gp3 \
  --max-allocated-storage 200 \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-name relvydb \
  --storage-encrypted \
  --deletion-protection \
  --backup-retention-period 7 \
  --no-publicly-accessible

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
| **Storage** | 100 GB minimum, autoscaling to 200 GB | ✅ |
| **Storage Type** | General Purpose SSD (gp3) | ✅ |
| **Public Access** | No (private only) | ✅ |

#### Configure Database Security

```bash
# Configure RDS Security Group to allow EKS cluster access
# Get EKS cluster security group ID
EKS_SG=$(aws eks describe-cluster --name relvy-cluster --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Get RDS security group ID
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier relvy-app-db --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

# Add EKS security group to RDS security group
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG

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
  --storage-size=100GB \
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
### Step 6: Deploy Relvy

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

### Step 7: Configure Domain and DNS

#### Step 7.1: Get Load Balancer DNS Name

First, you need to get the DNS name of your AWS Load Balancer:

```bash
kubectl get ingress relvy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

This will return something like: `k8s-default-relvying-a8f2b3930e-1505874984.us-east-1.elb.amazonaws.com`

**📝 Save This Value**: Copy the load balancer DNS name - you'll need it for your DNS configuration.

#### Step 7.2: Configure DNS Records

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

#### Step 7.3: Verify DNS Propagation

```bash
# Check DNS resolution
nslookup app.yourdomain.com

# Test connectivity
curl -I https://app.yourdomain.com/health
```

DNS propagation typically takes 5-30 minutes.

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

## Troubleshooting

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
