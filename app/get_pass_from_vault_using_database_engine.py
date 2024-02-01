import boto3
import hvac
import os
import time
'''
Script prints password from HCP Vault kept in this path: kv/data/db/todo_app from field password (kv/data/db/todo_app/password

'''
_todo_env_location = 'todo_env'
_VAULT_ADDRESS = os.getenv('VAULT_ADDR')
MAX_RETRIES = 5
RETRY_DELAY = 1  # seconds

def connect_to_vault() -> hvac.Client:
    # Get the client object with retries
    client = None
    # get credentials from EC2 metadata (We want to in this Todo App login to HCP Vault using IAM Role as our method to authenticate in Vault)
    session = boto3.Session()
    credentials = session.get_credentials()
    try:
        client = hvac.Client(url=_VAULT_ADDRESS)
        client.auth.aws.iam_login(credentials.access_key, credentials.secret_key, credentials.token, role='vault-role-for-aws-ec2role')
        return client
    except:
        return None
    
def get_pass_vault() -> bool:
    retry_count = 0
    "If we get password from HCP Vault, then return True and password is save into file located in _todo_env_location"
    while retry_count < MAX_RETRIES:
        # This while gives 5 tries to login to Vault
        client = connect_to_vault()
        if client:
            #it breaks while loop
            break

        retry_count += 1
        print(f"Retrying in {RETRY_DELAY} seconds...")
        time.sleep(RETRY_DELAY)

    # If the client is still None after retries, raise an error or handle it accordingly
    if not client:
        #raise Exception("Failed to connect to Vault after multiple retries.")
        return False

    role_name = 'my-role'
    mount_point = 'database'

    # Generate dynamic database credentials
    response = client.secrets.database.generate_credentials(
        name=role_name,
        mount_point=mount_point
    )
    password = response.get('data').get('password')
    username = response.get('data').get('username')

    # Extract the role and password from the response

    # replace password and username in todo_env file on current from HCP vault
    with open(_todo_env_location, "r") as f1:
        lines = f1.readlines()

    for i, line in enumerate(lines):
        if 'DB_PASSWORD' in line:
            lines[i] = 'DB_PASSWORD='+format(password)+'\n'
            with open(_todo_env_location, "w") as f:
                f.writelines(lines)
            f.close()
    for i, line in enumerate(lines):
        if 'DB_USER' in line:
            lines[i] = 'DB_USER='+format(username)+'\n'
            with open(_todo_env_location, "w") as f:
                f.writelines(lines)
            f.close()
    f1.close()
    return True
