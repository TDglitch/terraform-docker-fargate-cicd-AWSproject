# Containerized CI/CD Pipeline — AWS ECS Fargate

A containerized Python Flask application deployed end-to-end to AWS ECS Fargate using GitHub Actions and Terraform. The pipeline covers linting, unit testing, security scanning, Docker image build and push to Amazon ECR, and automated deployment — with zero manual release steps after a merge to `main`.

---

## Project Goal

Practice building and deploying a containerized application using real industry tools:
- Write and containerize a simple Python application
- Provision cloud infrastructure with Terraform
- Automate the full release lifecycle with a GitHub Actions CI/CD pipeline
- Deploy and run containers on AWS ECS Fargate without managing any servers

---

## Tech Stack

| Layer | Tool |
|---|---|
| Application | Python 3.12 / Flask |
| Containerization | Docker |
| Image Registry | Amazon ECR |
| Orchestration | Amazon ECS |
| Compute | AWS Fargate (serverless) |
| Infrastructure as Code | Terraform |
| CI/CD | GitHub Actions |
| Linting | flake8 |
| Testing | pytest |
| Security Scanning | Trivy |

---

## Repository Structure

```
.
├── app/
│   └── main.py                  # Flask application (health + root endpoints)
├── .github/
│   └── workflows/
│       └── pipeline.yml         # GitHub Actions CI/CD pipeline
├── Dockerfile                   # Container image definition
├── requirements.txt             # Python dependencies
├── main.tf                      # Terraform infrastructure
├── docs/
│   ├── ARCHITECTURE.md          # Infrastructure and component breakdown
│   └── PIPELINE.md              # Pipeline stages, errors encountered, and fixes
└── README.md
```

---

## Quick Start

### Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- [Terraform](https://developer.hashicorp.com/terraform/install) installed
- AWS account with IAM credentials configured (`aws configure`)
- GitHub repository with required secrets (see `docs/ARCHITECTURE.md`)

### Run Locally

```bash
# Build the Docker image
docker build -t fargate-demo .

# Run the container
docker run -p 5000:5000 fargate-demo

# Test the health endpoint (in a separate terminal)
curl http://localhost:5000/health
```

> **Mac note:** Port 5000 is sometimes occupied by AirPlay. Use `-p 5001:5000` and curl `:5001` instead.

### Provision Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

To tear everything down:

```bash
terraform destroy
```

---

## How It Works

1. A developer pushes code or opens a pull request against `main`
2. GitHub Actions triggers the pipeline — lint, test, and security scan run on every push and PR
3. On a merge to `main`, the pipeline builds a Docker image tagged with the commit SHA, pushes it to ECR, and deploys it to ECS Fargate
4. ECS performs a rolling update — the old task stays live until the new one passes its health check

For a full breakdown of the infrastructure, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
For the pipeline stages and the errors encountered during development, see [`docs/PIPELINE.md`](docs/PIPELINE.md).

---

## Skills Demonstrated

- Containerizing a Python application with Docker
- Provisioning AWS infrastructure with Terraform (VPC, ALB, ECR, ECS, IAM, CloudWatch)
- Building a multi-stage CI/CD pipeline (lint → test → security scan → build → deploy)
- Deploying to AWS ECS Fargate with no server management
- Debugging GitHub Actions pipeline failures and applying production-grade fixes
- Following AWS best practices: immutable image tags, IAM secrets, stable action versions
