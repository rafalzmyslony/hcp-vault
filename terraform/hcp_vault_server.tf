data "aws_caller_identity" "current" {}
locals {
    aws_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_instance" "vault_server" {
    instance_type = "t2.micro"
    #depends_on = [aws_subnet.private, aws_instance.db_todo]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.vault.id
    ]
    subnet_id = aws_subnet.public_vault.id
    associate_public_ip_address = true
    tags = {
        Name = "vault server"
    }
    root_block_device  {
      volume_size = 8
      volume_type = "gp2"
    }
    user_data = <<EOF1
#!/bin/bash
apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv

#######################################################################################
# Install HCP Vault
#######################################################################################

apt -y update
apt -y install build-essential
wget https://go.dev/dl/go1.20.5.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.20.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/usr/local/go/bin
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
apt -y update
apt -y install vault
pip3 install hvac -y

#######################################################################################
# Include these environment variables in every terminal session (.bashrc)
#######################################################################################

cat >> /home/ubuntu/.bashrc <<-EOF2
export TMP_VAULT_ACCESS_KEY=${aws_iam_access_key.user_iam_key.id}
export TMP_VAULT_SECRET_KEY=${aws_iam_access_key.user_iam_key.secret}
export VAULT_ADDR='http://0.0.0.0:8200'
export VAULT_TOKEN=root
EOF2

#######################################################################################
# To automate Vault configuration, instead of manually typing these commands,
# we will create files which contains these commands, that then we will execute by using source
# e.g. source create_and_put_password_into_vault
#######################################################################################

cat >> /home/ubuntu/create_and_put_password_into_vault <<-EOF3
# 1. We enable kv engine store, then put initial password in this path - > kv/data/db/todo_app password

vault secrets enable -version=1 kv
vault kv put kv/data/db/todo_app password="${var.db_pass}"  # password to todo-app database (then log to db and change password)

# 2. Then we write policy for HCP Vault, which states: everyone who has this policy, can read this password (kv/db/todo_app)
vault policy write vault-policy-for-aws-ec2role - <<-EOF4
# Grant 'read' permission to paths prefixed by 'kv/data/db/todo_app''
path "kv/data/db/todo_app" {
  capabilities = [ "read" ]
}
EOF4
# 3. Now we enable aws authorization plugin, to allow login to Vault using AWS auth.
vault auth enable aws
# 4. We are giving IAM user credentials to HCP Vault, to allow Vault to verify, whether incoming aws auth requests are valid 
vault write auth/aws/config/client secret_key=\$TMP_VAULT_SECRET_KEY access_key=\$TMP_VAULT_ACCESS_KEY

# 5. We are creating role inside HCP Vault, assigning to him policy, and we are telling which AWS IAM Role can use this inner Vault role
vault write auth/aws/role/vault-role-for-aws-ec2role \\
    auth_type=iam \\
bound_iam_principal_arn=arn:aws:iam::${local.aws_account_id}:role/aws-ec2role-for-vault-authmethod \\
    policies=vault-policy-for-aws-ec2role

# 6. repeat adding password - dev vault sucks
vault secrets enable -version=1 kv
vault kv put kv/data/db/todo_app password="${var.db_pass}"  # password to todo-app database (then log to db and change password)

EOF3

cat >> /home/ubuntu/create_and_run_database_engine <<-EOF2
#######################################################################################
# Part for database engine and dynamic secret rotation 
#######################################################################################

vault secrets enable database
vault write database/config/${var.db_name} \
    plugin_name="postgresql-database-plugin" \
    allowed_roles="my-role" \
    connection_url="postgresql://{{username}}:{{password}}@${aws_instance.database_ec2.private_ip}:5432/${var.db_name}" \
    username="${var.vault_role_name_to_db}" \
    password="${var.vault_pass_to_db}" \
    password_authentication="scram-sha-256"

vault write database/roles/my-role \
    db_name="${var.db_name}" \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT ALL PRIVILEGES  ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
        GRANT USAGE, CREATE ON SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

vault policy write allow-aws-role-to-access-postgresql - <<-EOF4
path "database/creds/my-role" {
  capabilities = [ "read" ]
}
EOF4
# append another policy to this aws role in HCP Vault
vault write auth/aws/role/vault-role-for-aws-ec2role \\
    policies=vault-policy-for-aws-ec2role,allow-aws-role-to-access-postgresql

EOF2
#######################################################################################
# Run HCP Vault
#######################################################################################
sleep 15 && sed '/^.*VAULT_.*$/p' -n /home/ubuntu/.bashrc > temp_env; source temp_env; source /home/ubuntu/create_and_put_password_into_vault &
vault server -dev -dev-root-token-id="root" -dev-listen-address=0.0.0.0:8200

EOF1
}