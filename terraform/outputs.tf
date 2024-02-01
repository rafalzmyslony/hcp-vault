
output "iam_user_key" {
  value = aws_iam_access_key.user_iam_key.id
}
output "iam_user_secret" {
  value = aws_iam_access_key.user_iam_key.secret
  sensitive = true
}

output "public_ip_todo_app" {
  value = aws_instance.todo_app_server.public_ip
}
output "public_ip_vault" {
  value = aws_instance.vault_server.public_ip
}
output "private_ip_database" {
  value = aws_instance.database_ec2.private_ip
  
}
