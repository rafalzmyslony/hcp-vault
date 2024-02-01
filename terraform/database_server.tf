resource "aws_instance" "database_ec2" {
    instance_type = "t2.micro"
    depends_on = [aws_nat_gateway.db_nat_gateway]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.database.id
    ]
    associate_public_ip_address = false
    subnet_id = aws_subnet.private.id
    tags = {
        Name = "database"
    }
    root_block_device  {
      volume_size = 8
      volume_type = "gp2"
    }
    user_data = <<EOF
#!/bin/bash
cat > /home/ubuntu/ip_address.txt << EOL
IP address of second EC2 instance 
EOL

apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv
apt-get -y update
apt-get -y install libpq-dev libpq-dev python3-dev
pip install psycopg2
apt install python3-psycopg2

#######################################################################################
# Install Postgresql 15
#######################################################################################

apt -y update
apt -y install build-essential
apt -y install wget sudo curl gnupg -y
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt -y update
apt -y install postgresql-15
apt-get update
apt-get install -y postgresql

#######################################################################################
# Configure Postgresql
#######################################################################################
useradd -m -s /sbin/nologin ${var.db_role_name}
sudo -u postgres createdb ${var.db_name}
sudo -u postgres psql -c "CREATE ROLE \"${var.db_role_name}\" LOGIN PASSWORD '${var.db_pass}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"${var.db_name}\" TO ${var.db_role_name};"
sudo -u postgres psql -c "ALTER DATABASE \"${var.db_name}\" OWNER TO \"${var.db_role_name}\";"

sudo -u postgres psql -c "CREATE ROLE \"${var.vault_role_name_to_db}\" LOGIN PASSWORD '${var.vault_pass_to_db}';"
sudo -u postgres psql -c "ALTER USER \"${var.vault_role_name_to_db}\" WITH SUPERUSER;"

systemctl restart postgresql

EOF
}