# All the outputs
output "vote_url" {
  description = "Address of the vote page."
  value       = "http://${aws_lb.main.dns_name}"
}

output "result_url" {
  description = "Address of the result page."
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "redis_endpoint" {
  description = "Address of the Redis node."
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "db_endpoint" {
  description = "Address of the Postgres instance."
  value       = aws_db_instance.main.address
}

