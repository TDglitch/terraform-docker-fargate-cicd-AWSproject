# Architecture

This document covers the infrastructure components, how they connect, and the reasoning behind key design decisions.

---

## High-Level Flow

```
Developer
    │
    │  git push / pull request
    ▼
GitHub Actions
    ├── Lint (flake8)
    ├── Unit Tests (pytest)
    ├── Security Scan (Trivy)
    └── Build, Push & Deploy  ← main branch only
            │
            ├── Docker build
            ├── Push image → Amazon ECR
            ├── Render new ECS Task Definition
            └── Deploy → ECS Fargate Service
                            │
                            └── Pulls image from ECR
                                Runs container on Fargate
                                Fronted by Application Load Balancer
```

---

## AWS Infrastructure

All resources are provisioned by Terraform (`main.tf`).

### Networking

| Resource | Purpose |
|---|---|
| VPC | Isolated network for all project resources |
| Public Subnet A + B | Two availability zones for redundancy |
| Internet Gateway | Allows traffic in/out of the VPC |
| Security Group (ALB) | Allows inbound HTTP (port 80) from the internet |
| Security Group (App) | Allows inbound traffic only from the ALB security group |

Fargate tasks run in public subnets with `assign_public_ip = true`. This lets the task reach ECR to pull the image without requiring a NAT Gateway, which keeps costs low for a practice project.

### Load Balancer

| Resource | Purpose |
|---|---|
| Application Load Balancer | Receives public traffic, routes to ECS tasks |
| Target Group | Registers healthy ECS tasks as targets |
| Listener (port 80) | Forwards HTTP requests to the target group |

The ALB performs health checks against the `/health` endpoint. A task must pass the health check before the ALB routes traffic to it, and must continue passing it to stay in rotation.

### Container Registry

| Resource | Purpose |
|---|---|
| Amazon ECR Repository | Stores Docker images tagged by commit SHA |

Images are tagged with the full Git commit SHA (`github.sha`). This makes every deployed image traceable to the exact commit that produced it.

### ECS + Fargate

| Resource | Purpose |
|---|---|
| ECS Cluster | Logical grouping for the service and tasks |
| Task Definition | Declares the container image, CPU/memory, ports, env vars, and log config |
| ECS Service | Keeps the desired number of tasks running; manages rolling deploys |

The ECS service uses a rolling update strategy:
- `deployment_minimum_healthy_percent = 50` — at least half the tasks stay healthy during a deploy
- `deployment_maximum_percent = 200` — up to double the tasks can run briefly during the transition

The Terraform `lifecycle` block on the ECS service includes `ignore_changes = [task_definition]`. This means Terraform won't try to roll back the task definition after GitHub Actions deploys a new image — GitHub Actions owns image updates, Terraform owns infrastructure changes.

### IAM

| Resource | Purpose |
|---|---|
| ECS Task Execution Role | Allows ECS to pull images from ECR and write logs to CloudWatch |

### Logging

| Resource | Purpose |
|---|---|
| CloudWatch Log Group | Receives container stdout/stderr via the `awslogs` log driver |

---

## Application

A minimal Python Flask app with two endpoints:

| Endpoint | Response |
|---|---|
| `GET /` | `{"status": "running"}` |
| `GET /health` | `{"status": "healthy"}` — used by ALB health checks |

The health endpoint is what keeps tasks in the ALB target group. If it stops responding with a 200, the ALB removes the task from rotation and ECS replaces it.

---

## Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
CMD ["python", "-m", "app.main"]
```

`python:3.12-slim` keeps the image small. Dependencies are installed in a separate layer from the app code so that code-only changes don't trigger a full `pip install` on rebuild.

---

## GitHub Secrets Required

These must be set in the repository under **Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | Target region (e.g. `us-east-1`) |
| `ECR_REPOSITORY` | ECR repository name |
| `ECS_SERVICE` | ECS service name |
| `ECS_CLUSTER` | ECS cluster name |
| `CONTAINER_NAME` | Container name as defined in the task definition |

---

## Why Fargate (and Not EC2 or Ansible)

Fargate is serverless compute for containers — there are no EC2 instances to provision, patch, or SSH into. AWS manages all underlying infrastructure.

This eliminates the need for configuration management tools like Ansible. Ansible configures servers; in this stack there are no servers. The Docker image contains everything the application needs, and ECS/Fargate handles running it.

The tradeoff is cost — Fargate is more expensive than EC2 at scale. For a practice project the operational simplicity is worth it.

---

## Why ECS (and Not Kubernetes)

ECS is simpler to set up and tightly integrated with AWS services (IAM, ALB, ECR, CloudWatch). Kubernetes offers more control and portability but requires significantly more configuration. ECS is the right choice when the goal is deploying containers on AWS without the overhead of managing a cluster control plane.
