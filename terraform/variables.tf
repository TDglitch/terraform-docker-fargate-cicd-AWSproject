# =============================================================================
# variables.tf — all configurable inputs
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Used as a prefix for every resource name"
  type        = string
  default     = "fargate-cicd-demo"
}

variable "container_name" {
  description = "Must match the container name in the task definition AND the GitHub secret CONTAINER_NAME"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port the Flask app listens on inside the container"
  type        = number
  default     = 5000
}

variable "task_cpu" {
  description = "CPU units for the Fargate task (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Number of running task replicas"
  type        = number
  default     = 1
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Project     = "fargate-cicd-demo"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
