resource "aws_secretsmanager_secret" "db" {
  name = var.secret_name
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "val" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ connection_string = var.db_details })
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}