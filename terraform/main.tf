resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "local_file" "ssh_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/todo-private.key"
  file_permission = 0400
}
resource "aws_key_pair" "generated_key" {
  key_name   = "todoapp"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

#=============IAM section===================

resource "aws_iam_user" "user_iam" {
  name = "aws-iamuser-for-vault-authmethod"

  tags = {
    user = "vault"
  }
}
resource "aws_iam_access_key" "user_iam_key" {
  user = aws_iam_user.user_iam.name
}
resource "aws_iam_policy" "policy_vault" {
  name        = "aws-iampolicy-for-vault-authmethod"
  description = "My test policy"

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances",
        "iam:GetInstanceProfile",
        "iam:GetUser",
        "iam:ListRoles",
        "iam:GetRole"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]

}
EOT
}
resource "aws_iam_user_policy_attachment" "attachment" {
  user       = aws_iam_user.user_iam.name
  policy_arn = aws_iam_policy.policy_vault.arn
}

resource "aws_iam_role" "ec2_role" {
  name = "aws-ec2role-for-vault-authmethod"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  tags = {
    dest = "role_for_ec2_client_Vault"
  }
}

# profile, role can be assigned to many profiles, but one profile to one ec2
# this profile will be attach to ec2 in aws_instance
# in gui, we attach role to ec2, but internally it created profile with iam role
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}