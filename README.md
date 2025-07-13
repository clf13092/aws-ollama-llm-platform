# AWS Ollama LLM Platform

[🇯🇵 日本語版README](./README.ja.md) | [🇺🇸 English README](./README.md)

🚀 **Dynamic Ollama LLM deployment on AWS with secure authentication and one-click CloudFormation setup**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![AWS](https://img.shields.io/badge/AWS-Ready-orange.svg)](https://aws.amazon.com/)
[![Ollama](https://img.shields.io/badge/Ollama-Compatible-green.svg)](https://ollama.com/)
[![Security](https://img.shields.io/badge/Security-AWS%20Cognito-red.svg)](https://aws.amazon.com/cognito/)

## 🎯 Overview

This project provides a complete AWS-based solution for deploying and managing Ollama Large Language Models (LLMs) dynamically. Users can select any model and instance type through a secure web-based management interface with full authentication, automatic endpoint generation, and comprehensive monitoring.

**Key Features:**
- 🔒 **Secure Authentication**: AWS Cognito with user management
- 🔄 **Dynamic LLM deployment** via ECS (Fargate/EC2)
- 🖥️ **Web-based management dashboard** (React.js)
- ⚡ **Auto-scaling** based on demand
- 💰 **Cost optimization** with automatic idle shutdown
- 🛡️ **Secure VPC configuration** with private subnets
- 📊 **Comprehensive monitoring** and logging
- 🎯 **One-click CloudFormation deployment**

## 🏗️ Architecture

```mermaid
graph TB
    User[Users] --> CF[CloudFront]
    User --> ALB[Application Load Balancer]
    
    CF --> S3[S3 Static Website<br/>Management UI]
    
    S3 --> Cognito[AWS Cognito<br/>Authentication]
    S3 --> APIGW[API Gateway<br/>Cognito Authorizer]
    
    Cognito --> APIGW
    APIGW --> Lambda[Lambda Functions<br/>API Backend]
    
    Lambda --> DDB[DynamoDB<br/>Metadata Management]
    Lambda --> ECS[ECS Cluster]
    
    ECS --> TaskDef[Task Definition<br/>CPU/GPU Support]
    TaskDef --> OllamaTask1[Ollama Task 1<br/>llama2:7b]
    TaskDef --> OllamaTask2[Ollama Task 2<br/>codellama:13b]
    TaskDef --> OllamaTaskN[Ollama Task N<br/>Other Models]
    
    OllamaTask1 --> ALB
    OllamaTask2 --> ALB
    OllamaTaskN --> ALB
    
    Lambda --> CW[CloudWatch<br/>Logs & Metrics]
    
    subgraph VPC[VPC]
        subgraph PublicSubnet[Public Subnet]
            ALB
        end
        
        subgraph PrivateSubnet[Private Subnet]
            ECS
            OllamaTask1
            OllamaTask2
            OllamaTaskN
        end
    end
    
    subgraph AuthLayer[Authentication & Security Layer]
        Cognito
        UserPool[User Pool<br/>User Management]
        IdentityPool[Identity Pool<br/>AWS Permissions]
        
        Cognito --> UserPool
        Cognito --> IdentityPool
    end
```

## 🚀 Quick Start

### Prerequisites
- AWS Account with appropriate permissions
- AWS CLI configured
- Domain name (optional, for custom endpoints)
- Email address for admin account

### 1. Deploy Infrastructure

```bash
# Clone the repository
git clone https://github.com/clf13092/aws-ollama-llm-platform.git
cd aws-ollama-llm-platform

# Create parameters file
cat > parameters.json << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "production"
  },
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "ollama.yourdomain.com"
  },
  {
    "ParameterKey": "AdminEmail",
    "ParameterValue": "admin@yourdomain.com"
  },
  {
    "ParameterKey": "EnableMFA",
    "ParameterValue": "false"
  }
]
EOF

# Deploy the stack
aws cloudformation create-stack \
  --stack-name aws-ollama-platform \
  --template-body file://cloudformation/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Create initial admin user (after stack deployment completes)
aws cognito-idp admin-create-user \
  --user-pool-id <USER_POOL_ID> \
  --username admin \
  --user-attributes Name=email,Value=admin@yourdomain.com \
  --temporary-password TempPass123! \
  --message-action SUPPRESS
```

### 2. Access Management Interface

After deployment completes (~15-20 minutes):

1. **Get the CloudFront URL** from the stack outputs
2. **Open the management interface** in your browser
3. **Login with admin credentials**:
   - Username: `admin`
   - Temporary Password: `TempPass123!`
4. **Set permanent password** when prompted
5. **Access the dashboard** to manage your LLM models

### 3. Deploy Your First Model

1. **Login to the dashboard**
2. **Navigate to "Models"** section
3. **Select a model** (e.g., Llama2 7B, CodeLlama 13B)
4. **Choose instance type** (CPU/GPU based on requirements)
5. **Click "Deploy Model"**
6. **Get your API endpoint URL** from the instances list

## 🔒 Authentication & Security

### AWS Cognito Configuration
- **User Pool**: Centralized user management with email verification
- **Password Policy**: 8+ characters, mixed case, numbers, symbols
- **Account Security**: Automatic lockout after 5 failed attempts
- **MFA Support**: Optional SMS/TOTP authentication
- **Session Management**: JWT tokens with configurable expiration

### Access Control
- **Role-based permissions**:
  - **Admin**: Full system access and user management
  - **User**: Personal model management only
  - **ReadOnly**: View-only access to models and logs
- **API Protection**: All management APIs require valid JWT tokens
- **Resource Isolation**: Users can only access their own deployed models

### Security Features
- **HTTPS Everywhere**: All communication encrypted in transit
- **VPC Isolation**: Compute resources in private subnets
- **Network Security**: Security groups with least-privilege access
- **IAM Policies**: Principle of least privilege for all AWS resources

## 📊 Component Details

### Frontend (Management UI)
- **Technology**: React.js + TypeScript + Material-UI + AWS Amplify Auth
- **Hosting**: S3 Static Website + CloudFront CDN
- **Features**:
  - **Secure Login/Signup** with email verification
  - **Dashboard** with running models overview (authenticated users only)
  - **Model deployment interface** with real-time status
  - **Endpoint management** and testing capabilities
  - **Real-time monitoring** and log viewing
  - **User profile management** with password change and MFA setup

### Backend API
- **Technology**: AWS Lambda + Python (FastAPI) + boto3
- **Authentication**: API Gateway Cognito Authorizer + JWT validation
- **Database**: DynamoDB with user-scoped data access
- **Endpoints**:

```bash
# Public endpoints (no authentication required)
POST   /api/auth/login          # User login
POST   /api/auth/signup         # User registration
POST   /api/auth/reset-password # Password reset

# Protected endpoints (JWT token required)
GET    /api/models              # List available models
POST   /api/models/start        # Deploy new model (user-scoped)
DELETE /api/models/{id}/stop    # Stop running model (owner only)
GET    /api/instances           # List user's running instances
GET    /api/instances/{id}      # Get instance details & endpoint
GET    /api/instances/{id}/logs # Retrieve instance logs
GET    /api/user/profile        # Get user profile
PUT    /api/user/profile        # Update user profile
GET    /api/health              # System health check
```

### Container Platform
- **ECS Cluster**: Mixed Fargate (CPU) + EC2 (GPU) deployment
- **Auto Scaling**: Request-based scaling with cost optimization
- **Service Discovery**: AWS Cloud Map for internal service communication
- **Load Balancing**: Application Load Balancer with health checks
- **User Isolation**: Each user's models deployed in separate namespaces

## 🔧 Supported Models

| Model | Size | CPU Support | GPU Support | Memory Required | Deployment Time |
|-------|------|-------------|-------------|-----------------|-----------------|
| Llama2 | 7B | ✅ | ✅ | 4GB | ~3 minutes |
| Llama2 | 13B | ✅ | ✅ | 8GB | ~5 minutes |
| CodeLlama | 7B | ✅ | ✅ | 4GB | ~3 minutes |
| CodeLlama | 13B | ✅ | ✅ | 8GB | ~5 minutes |
| Mistral | 7B | ✅ | ✅ | 4GB | ~3 minutes |
| Mistral | 7B Instruct | ✅ | ✅ | 4GB | ~3 minutes |

## 💡 Usage Examples

### Authentication Flow
```bash
# 1. User registration
curl -X POST https://api.ollama.yourdomain.com/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePass123!",
    "confirmPassword": "SecurePass123!"
  }'

# 2. Login and get JWT token
response=$(curl -X POST https://api.ollama.yourdomain.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "SecurePass123!"
  }')

# Extract JWT token
jwt_token=$(echo $response | jq -r '.access_token')
```

### Authenticated API Usage
```bash
# List available models (requires authentication)
curl https://api.ollama.yourdomain.com/api/models \
  -H "Authorization: Bearer $jwt_token"

# Deploy Llama2 model
curl -X POST https://api.ollama.yourdomain.com/api/models/start \
  -H "Authorization: Bearer $jwt_token" \
  -H "Content-Type: application/json" \
  -d '{
    "model_id": "llama2-7b",
    "instance_type": "ml.m5.large"
  }'

# List your running instances
curl https://api.ollama.yourdomain.com/api/instances \
  -H "Authorization: Bearer $jwt_token"

# Chat with your deployed model
curl https://ollama-inst-001.yourdomain.com/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama2",
    "prompt": "Hello, how are you?",
    "stream": false
  }'
```

### Authenticated Model Workflow

```mermaid
sequenceDiagram
    participant U as User
    participant UI as Management UI
    participant Cognito as AWS Cognito
    participant API as API Gateway
    participant L as Lambda
    participant ECS as ECS
    participant DDB as DynamoDB
    
    U->>UI: Access website
    UI->>UI: Check authentication status
    alt Not authenticated
        UI->>U: Show login page
        U->>UI: Enter email/password
        UI->>Cognito: Authentication request
        Cognito->>UI: Return JWT token
        UI->>UI: Store token securely
    end
    
    U->>UI: Request model deployment
    UI->>API: POST /api/models/start (with JWT)
    API->>Cognito: Validate JWT token
    Cognito->>API: Return user info
    API->>L: Deployment request (with user ID)
    L->>DDB: Get model configuration
    L->>ECS: Create ECS service
    ECS->>ECS: Start Ollama task
    L->>DDB: Save instance metadata (user-scoped)
    L->>API: Return endpoint URL
    API->>UI: Deployment complete
    UI->>U: Display endpoint and status
```

## 🛡️ Security Best Practices

### Infrastructure Security
- **VPC Isolation**: All compute resources in private subnets
- **Security Groups**: Network-level access control with minimal required ports
- **IAM Policies**: Principle of least privilege for all AWS resources
- **Encryption**: All data encrypted in transit and at rest

### Application Security
- **JWT Tokens**: Secure authentication with configurable expiration
- **Input Validation**: All API inputs validated and sanitized
- **Rate Limiting**: API endpoints protected against abuse
- **Audit Logging**: All user actions logged for security monitoring

### Operational Security
- **Automated Updates**: Regular security patches for container images
- **Monitoring**: Real-time security event monitoring
- **Backup**: Automated backups of user data and configurations
- **Incident Response**: Automated alerting for security events

## 💰 Cost Optimization

- **Automatic Shutdown**: Idle instances stopped after configurable timeout
- **Spot Instances**: Optional for development workloads (up to 90% savings)
- **Right-sizing**: Automatic CPU/GPU selection based on model requirements
- **Pay-per-use**: Only pay when models are actively running
- **Resource Monitoring**: Real-time cost tracking and alerts

## 📈 Monitoring & Observability

### CloudWatch Metrics
- **System Metrics**: ECS CPU/Memory utilization, ALB response times
- **Application Metrics**: API Gateway request counts, Lambda execution duration
- **Business Metrics**: Active users, model deployment success rates
- **Cost Metrics**: Real-time cost tracking per user and model

### Logging & Alerting
- **Centralized Logging**: All logs aggregated in CloudWatch Logs
- **Security Monitoring**: Authentication failures, unusual access patterns
- **Performance Alerts**: High latency, error rates, resource exhaustion
- **Cost Alerts**: Spending thresholds and budget notifications

## 🛠️ Development & Deployment

### Project Structure
```
├── cloudformation/           # Infrastructure as Code
│   ├── main.yaml            # Master template
│   ├── network/             # VPC, subnets, gateways
│   ├── compute/             # ECS cluster, task definitions
│   ├── api/                 # Lambda functions, API Gateway
│   ├── auth/                # Cognito User Pool & Identity Pool
│   ├── storage/             # DynamoDB tables
│   ├── frontend/            # S3, CloudFront
│   └── security/            # IAM roles and policies
├── src/
│   ├── frontend/            # React management UI with auth
│   ├── api/                 # Lambda function code
│   └── containers/          # Custom Ollama Docker images
├── docs/                    # Documentation
└── scripts/                 # Deployment and utility scripts
```

### Local Development
```bash
# Install dependencies
npm install

# Configure AWS credentials for Cognito
export AWS_REGION=us-east-1
export COGNITO_USER_POOL_ID=<your-user-pool-id>
export COGNITO_CLIENT_ID=<your-client-id>

# Run frontend locally with authentication
cd src/frontend
npm start

# Deploy Lambda functions
cd src/api
sam deploy
```

## 🔮 Roadmap

### Security Enhancements
- [ ] **SSO Integration**: SAML/OIDC support for enterprise authentication
- [ ] **API Key Management**: Long-term API keys for automated access
- [ ] **Audit Dashboard**: Comprehensive security and access monitoring

### Platform Features
- [ ] **Multi-region deployment**: Global distribution for low latency
- [ ] **Fine-tuning capabilities**: Custom model training and deployment
- [ ] **Model versioning**: A/B testing and rollback capabilities
- [ ] **Batch inference**: High-throughput batch processing
- [ ] **Team Management**: Organization and team-based access control

### Integrations
- [ ] **Webhook support**: External system integration and notifications
- [ ] **Slack/Teams bots**: ChatOps integration for model management
- [ ] **CI/CD integration**: Automated model deployment pipelines

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Security Disclosure
If you discover a security vulnerability, please email security@yourdomain.com instead of opening a public issue.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- 📖 [Documentation](./docs/)
- 🐛 [Issue Tracker](https://github.com/clf13092/aws-ollama-llm-platform/issues)
- 💬 [Discussions](https://github.com/clf13092/aws-ollama-llm-platform/discussions)
- 🔒 [Security Issues](mailto:security@yourdomain.com)

## 🙏 Acknowledgments

- [Ollama](https://ollama.com/) for the amazing LLM runtime
- [AWS](https://aws.amazon.com/) for the comprehensive cloud infrastructure
- [AWS Cognito](https://aws.amazon.com/cognito/) for secure user authentication
- The open-source community for inspiration and support

---

**⭐ If this project helps you, please consider giving it a star!**

**🔒 Security Notice**: This platform includes production-ready authentication and authorization. Please review the security configuration before deploying to production environments.