from flask import Flask, render_template, request, Markup
import psycopg2
import os
from get_pass_from_vault import get_pass_vault
app = Flask(__name__)
import subprocess
import time
import syslog
import threading
import sys

def restart_service_to_reload_env_vars(time_in_seconds: int):
    syslog.syslog(syslog.LOG_INFO, f"For {time_in_seconds} second this app will restarted")
    time.sleep(time_in_seconds)
    restart_command = "sudo systemctl restart todo_app.service"
    subprocess.run(restart_command, shell=True, check=True)
    sys.exit()

def create_db_connection():
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            port=os.environ.get('DB_PORT'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD')
        )
        return conn

    except psycopg2.OperationalError as e:
        print(f"Error: {e}")
        return None
    

if get_pass_vault() == True:
    '''
    True when function from get_pass_from_vault.py will connect to Vault and get sercret
    '''
    conn = create_db_connection()
    if conn is not None:
        cur = conn.cursor()
        cur.execute('''
            CREATE TABLE IF NOT EXISTS todos (
                id SERIAL PRIMARY KEY,
                task TEXT NOT NULL,
                completed BOOLEAN DEFAULT FALSE
            )
        ''')
        conn.commit()

        @app.route('/', methods=['GET', 'POST'])
        def index():
            if request.method == 'POST':
                task = request.form['task']
                cur.execute('INSERT INTO todos (task) VALUES (%s)', (task,))
                conn.commit()
            
            cur.execute('SELECT * FROM todos')
            todos = cur.fetchall()
            
            return render_template('index.html', todos=todos)
    
    else:
        @app.route('/', methods=['GET'])
        def index():
            message =Markup("<h4> Manual secret rotation </h4> \
            Could not connect to database <br> \
            Make sure that password stored in HCP Vault is the same as in this Postgresql Role <br>\
            (<b> When you are updating password using 'change_pass_in_postgresql.yml' playbook, \
            then you have to also manually add this to Vault </b> <br> \
            <h5> <b> For couple of seconds this app will be restarted to refresh database connection </b></h5>)")
            background_thread = threading.Thread(target=restart_service_to_reload_env_vars,args=(1,))
            background_thread.start()
            return render_template('error.html', message=message)


else:
    @app.route('/', methods=['GET'])
    def index():
        message ="<h3> Read this if you have manual secret rotation </h3> \
        Failed to get password from HCP Vault. Make sure that you already run ansible playbooks <br> \
        'allow_to_access_database.yml' (because postgresql must allow for incoming connections) <br> \
        and 'add_vault_public_ip_to_todo_env.yml' (because ToDo app needs to know IP address of HCP Vault) <br>\
        <h3> Read this if you have manual secret rotation </h3> \
        Make sure that in HCP Vault server you run this command to create and run database engine (for dynamic \
        postgresql role and password creation):\
        sed '/^.*VAULT_.*$/p' -n /home/ubuntu/.bashrc > temp_env; source temp_env; source /home/ubuntu/create_and_run_database_engine \
        "
        return render_template('error.html', message=Markup(message))
    
if __name__ == '__main__':
    app.run(debug=True)
