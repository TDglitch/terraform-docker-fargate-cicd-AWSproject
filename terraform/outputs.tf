# =============================================================================
# outputs.tf — values you'll need after `terraform apply`
# =============================================================================

output "alb_dns_name" {
  description = "Public URL of the load balancer — open this in your browser"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Full ECR URL — copy this into your GitHub secret ECR_REPOSITORY"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name — matches GitHub secret ECS_CLUSTER"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name — matches GitHub secret ECS_SERVICE"
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for container stdout/stderr"
  value       = aws_cloudwatch_log_group.app.name
}

output "task_definition_family" {
  description = "Task definition family name — used by the deploy pipeline step"
  value       = aws_ecs_task_definition.app.family
}
