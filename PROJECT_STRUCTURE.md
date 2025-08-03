# Project Structure

This document describes the organization of the AWS Ollama LLM Platform project.

## 📁 Directory Structure

```
aws-ollama-llm-platform/
├── 📄 README.md                    # Main project documentation
├── 📄 README.ja.md                 # Japanese documentation
├── 📄 PROJECT_STRUCTURE.md         # This file
├── 📄 parameters-template.json     # CloudFormation parameters template
│
├── 📂 cloudformation/              # Infrastructure as Code
│   ├── 📄 main.yaml                # Master CloudFormation template
│   ├── 📂 api/                     # API Gateway and Lambda
│   │   ├── 📄 api-gateway.yaml     # API Gateway with inline Lambda
│   │   └── 📄 api-gateway-updated.yaml # API Gateway with file-based Lambda
│   ├── 📂 auth/                    # Authentication
│   │   └── 📄 cognito.yaml         # Cognito User Pool and Identity Pool
│   ├── 📂 compute/                 # Container orchestration
│   │   └── 📄 ecs-cluster.yaml     # ECS Cluster, ALB, Task Definitions
│   ├── 📂 frontend/                # Static website hosting
│   │   └── 📄 s3-cloudfront.yaml   # S3 bucket and CloudFront distribution
│   ├── 📂 network/                 # Networking
│   │   └── 📄 vpc.yaml             # VPC, subnets, security groups
│   ├── 📂 security/                # IAM roles and policies
│   │   └── 📄 iam.yaml             # IAM roles for Lambda, ECS, etc.
│   └── 📂 storage/                 # Data storage
│       ├── 📄 dynamodb.yaml        # DynamoDB tables
│       └── 📄 ecr.yaml             # ECR repositories
│
├── 📂 docker/                      # Container definitions
│   ├── 📂 base/                    # Base Ollama container
│   │   ├── 📄 Dockerfile           # Base Ollama image
│   │   ├── 📄 entrypoint.sh        # Container startup script
│   │   └── 📄 healthcheck.sh       # Health check script
│   └── 📂 models/                  # Model-specific containers
│       ├── 📂 llama2-7b/           # Llama2 7B pre-built image
│       ├── 📂 llama2-13b/          # Llama2 13B pre-built image
│       ├── 📂 codellama-7b/        # CodeLlama 7B pre-built image
│       ├── 📂 codellama-13b/       # CodeLlama 13B pre-built image
│       └── 📂 mistral-7b/          # Mistral 7B pre-built image
│
├── 📂 frontend/                    # React management interface
│   ├── 📄 package.json             # Node.js dependencies
│   ├── 📄 vite.config.ts           # Vite configuration
│   ├── 📄 tsconfig.json            # TypeScript configuration
│   ├── 📂 public/                  # Static assets
│   └── 📂 src/                     # React source code
│       ├── 📄 App.tsx              # Main application component
│       ├── 📄 main.tsx             # Application entry point
│       ├── 📂 components/          # React components
│       │   ├── 📄 DashboardApp.tsx # Main dashboard
│       │   └── 📂 auth/            # Authentication components
│       │       ├── 📄 LoginForm.tsx
│       │       ├── 📄 SignUpForm.tsx
│       │       └── 📄 ConfirmSignUpForm.tsx
│       ├── 📂 contexts/            # React contexts
│       │   └── 📄 AuthContext.tsx  # Authentication context
│       ├── 📂 hooks/               # Custom React hooks
│       │   └── 📄 useModels.ts     # Model management hook
│       └── 📂 services/            # API services
│           └── 📄 authService.ts   # Cognito authentication service
│
├── 📂 lambda-functions/            # Serverless functions
│   ├── 📂 instances/               # Instance management API
│   │   ├── 📄 lambda_function.py   # Main Lambda function
│   │   └── 📄 requirements.txt     # Python dependencies
│   ├── 📂 models/                  # Model management API (placeholder)
│   └── 📂 auth/                    # Authentication API (placeholder)
│
├── 📂 scripts/                     # Deployment and utility scripts
│   ├── 📄 deploy.sh                # Main deployment script
│   ├── 📄 package-lambda.sh        # Lambda function packaging
│   ├── 📄 build-and-push-images.sh # Docker image build and push
│   ├── 📄 generate-config.sh       # Frontend configuration generator
│   └── 📄 populate-models.py       # DynamoDB model data population
│
└── 📂 docs/                        # Additional documentation
    └── 📄 instance-type-strategy.md # Instance type selection strategy
```

## 🔧 Key Components

### Infrastructure (CloudFormation)
- **Modular Design**: Each AWS service has its own template
- **Nested Stacks**: Main template orchestrates all components
- **Parameter Driven**: Configurable for different environments

### Container Platform (Docker)
- **Base Image**: Common Ollama runtime environment
- **Model-Specific Images**: Pre-built images for faster startup
- **Health Checks**: Automated container health monitoring

### Frontend (React + TypeScript)
- **Modern Stack**: Vite + React + TypeScript + Material-UI
- **Authentication**: Custom Cognito integration (no Amplify)
- **Responsive Design**: Works on desktop and mobile

### Backend (Lambda Functions)
- **Serverless**: AWS Lambda with Python runtime
- **File-Based**: Separate files for better maintainability
- **ECS Integration**: Direct ECS task management

### Deployment (Scripts)
- **One-Command Deploy**: Single script deploys everything
- **Docker Integration**: Automatic image build and push
- **Configuration Management**: Dynamic config generation

## 🚀 Getting Started

1. **Prerequisites**: AWS CLI, Docker, Node.js
2. **Deploy**: Run `sh scripts/deploy.sh`
3. **Access**: Use CloudFront URL from deployment output
4. **Manage**: Create admin user and start deploying models

## 📝 Development Workflow

1. **Infrastructure Changes**: Modify CloudFormation templates
2. **Backend Changes**: Update Lambda functions in `lambda-functions/`
3. **Frontend Changes**: Develop in `frontend/` directory
4. **Container Changes**: Update Dockerfiles in `docker/`
5. **Deploy**: Run `sh scripts/deploy.sh` to deploy all changes

## 🔒 Security Considerations

- **VPC Isolation**: All compute resources in private subnets
- **IAM Least Privilege**: Minimal required permissions
- **Encryption**: Data encrypted in transit and at rest
- **Authentication**: Cognito-based user management
- **Network Security**: Security groups with minimal access

## 💰 Cost Optimization

- **Serverless First**: Lambda and Fargate for cost efficiency
- **Right-Sizing**: Appropriate instance types per model
- **Auto-Shutdown**: Idle instances automatically stopped
- **Spot Instances**: Optional for development workloads
