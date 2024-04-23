resource "aws_instance" "todo_app_server" {
    instance_type = "t2.micro"
    depends_on = [aws_subnet.private, aws_instance.database_ec2]
    ami = "ami-04e601abe3e1a910f"
    key_name      = aws_key_pair.generated_key.key_name
    vpc_security_group_ids = [
        aws_security_group.todo_app.id
    ]
    subnet_id = aws_subnet.public_app.id
    associate_public_ip_address = true
    tags = {
        Name = "todo_app_server"
    }
    root_block_device  {
      volume_size = 15
      volume_type = "gp2"
    }

    user_data = <<EOF
#!/bin/bash

apt-get -y update
apt -y install net-tools
apt -y install python3-pip
apt -y install python3.10-venv
apt-get -y update
apt-get -y install libpq-dev libpq-dev python3-dev
apt-get -y install postgresql
apt-get -y install gcc

#######################################################################################
# install GO and HCP Vault
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

#######################################################################################
# Download todo app from my github.com repository

# Install python virtual environment and load environment variables into .bashrc 
#######################################################################################

mkdir /home/ubuntu/app
cd /home/ubuntu/
# I used my own repository as source of ToDo application, if you work my repo, then you must change repository to clone
git clone https://github.com/rafalzmyslony/hcp-vault.git
cp -r vault/app/* /home/ubuntu/app
rm -rf vault

python3 -m venv /home/ubuntu/app
chown -R ubuntu:ubuntu app/
echo "source ~/app/bin/activate " | sudo tee -a /home/ubuntu/.bashrc >/dev/null
/home/ubuntu/app/bin/pip install -r /home/ubuntu/app/requirements.txt
cat >> /home/ubuntu/.bashrc << EOL
export DB_HOST=${aws_instance.database_ec2.private_ip}
export DB_PORT=5432
export DB_NAME=${var.db_name}
export DB_USER=${var.db_role_name}
export DB_PASSWORD=${var.db_pass}
EOL

#######################################################################################
# create service in systemd for todo application
#######################################################################################

cat >> /etc/systemd/system/todo_app.service << EOL
[Unit]
Description=Todo app
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
EnvironmentFile=/home/ubuntu/app/todo_env
RuntimeDirectory=app
WorkingDirectory=/home/ubuntu/app
ExecStart=/home/ubuntu/app/bin/uwsgi /home/ubuntu/app/uwsgi.ini
KillMode=mixed
Restart=on-failure

[Install]
WantedBy=multi-user.target                               
EOL

#######################################################################################
# create file with environment variables that will be loaded into todo app service in systemd by using `EnvironmentFile=`
#######################################################################################
cat >> /home/ubuntu/app/todo_env << EOL
DB_HOST=${aws_instance.database_ec2.private_ip}
DB_PORT=5432
DB_NAME=${var.db_name}
DB_USER=${var.db_role_name}
DB_PASSWORD=${var.db_pass}
EOL

#######################################################################################
#  change ownership of todo_env (file with environment variables for todo app service)
#######################################################################################

chown ubuntu:ubuntu /home/ubuntu/app/todo_env
chmod 770 /home/ubuntu/app/todo_env

#######################################################################################
# put private key into file to allow Ansible playbook connect from this host to database
# (this host will be bastion host, because database server on doesn't have access from internet)
# THIS IS DONE BY PROVISION FILE RESOURCE IN TERRAFORM BELOW
#######################################################################################
echo "${tls_private_key.ssh_key.private_key_pem}" > /home/ubuntu/private.key
chmod 600 /home/ubuntu/private.key
chown ubuntu:ubuntu /home/ubuntu/private.key


#######################################################################################
# enable todo app service in systemd
#######################################################################################

cd /etc/systemd/system/
systemctl start todo_app.service
systemctl enable todo_app.service
todo_app.service restart  

EOF
    iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

}

