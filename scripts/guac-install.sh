#!/bin/bash

# ========== Logging Function ==========
log_message() {
    local type="$1"
    local message="$2"
    local term_width
    term_width=$(tput cols)
    local stars_count=$((term_width - ${#message} - 10))
    local stars
    stars=$(printf '*%.0s' $(seq 1 "$stars_count"))

    case "$type" in
        task)
            echo -e "\e[1;37m\nTASK [ $message ] $stars\e[0m"
            ;;
        ok)
            echo -e "\e[1;32mok: [localhost] => $message\e[0m"
            ;;
        changed)
            echo -e "\e[1;33mchanged: [localhost] => $message\e[0m"
            ;;
        info)
            echo -e "\e[1;36mINFO: $message\e[0m"
            ;;
        *)
            echo -e "\e[1;31mUnknown log type: $type\e[0m"
            ;;
    esac
}

# ========== Variables ==========
java_jdk_version=11
tomcat_version_integer=9
tomcat_version_dec=0.112
tomcat_version=$tomcat_version_integer.$tomcat_version_dec
tomcat_path=/opt/tomcat
tomcat_port=9080
guac_version=1.5.5
guac_path=/tmp/guacamole-install
guacamole_webadmin_username=guacadmin
guacamole_webadmin_password="guacadmin"
mysql_connector_version=9.1.0
db_name=guacamole_db
db_user=guacamole_user
db_password=guacamole_pass

# ========== Install Dependencies ==========
log_message "task" "Update APT and install dependencies"
apt update
apt install -y openjdk-11-jdk \
    build-essential libcairo2-dev libjpeg-turbo8-dev libpng-dev \
    libtool-bin uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev \
    libtelnet-dev libvncserver-dev libwebsockets-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev \
    wget curl mariadb-server
log_message "changed" "Dependencies installed"

# ========== Create Tomcat User ==========
log_message "task" "Create tomcat user"
if id "tomcat" &>/dev/null; then
    log_message "ok" "User 'tomcat' already exists"
else
    useradd -m -U -d $tomcat_path -s /bin/false tomcat
    log_message "changed" "User 'tomcat' created"
fi

# ========== Download and Install Tomcat ==========
log_message "task" "Download and install Tomcat $tomcat_version"
mkdir -p $guac_path
cd $guac_path

if [ ! -f "apache-tomcat-$tomcat_version.tar.gz" ]; then
    wget https://dlcdn.apache.org/tomcat/tomcat-$tomcat_version_integer/v$tomcat_version/bin/apache-tomcat-$tomcat_version.tar.gz
    log_message "changed" "Tomcat downloaded"
else
    log_message "ok" "Tomcat archive already exists"
fi

if [ ! -d "$tomcat_path/apache-tomcat-$tomcat_version" ]; then
    mkdir -p $tomcat_path
    tar xzf apache-tomcat-$tomcat_version.tar.gz -C $tomcat_path
    mkdir -p $tomcat_path/apache-tomcat-$tomcat_version/logs
    mkdir -p $tomcat_path/apache-tomcat-$tomcat_version/temp
    log_message "changed" "Tomcat extracted to $tomcat_path"
else
    log_message "ok" "Tomcat already extracted"
fi

# ========== Create Tomcat setenv.sh ==========
log_message "task" "Create Tomcat setenv.sh"
cat > $tomcat_path/apache-tomcat-$tomcat_version/bin/setenv.sh <<EOF
export JAVA_HOME="/usr/lib/jvm/java-$java_jdk_version-openjdk-amd64"
export JAVA_OPTS="-Djava.security.egd=file:///dev/urandom -Djava.awt.headless=true"
export CATALINA_BASE="$tomcat_path/apache-tomcat-$tomcat_version"
export CATALINA_HOME="$tomcat_path/apache-tomcat-$tomcat_version"
export CATALINA_PID="$tomcat_path/apache-tomcat-$tomcat_version/temp/tomcat.pid"
export CATALINA_OPTS="-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
EOF
log_message "changed" "setenv.sh created"

# ========== Configure Tomcat Port ==========
log_message "task" "Configure Tomcat to use port $tomcat_port"
sed -i "s/port=\"8080\"/port=\"$tomcat_port\"/g" $tomcat_path/apache-tomcat-$tomcat_version/conf/server.xml
log_message "changed" "Tomcat configured to listen on port $tomcat_port"

# ========== Set Tomcat Permissions ==========
log_message "task" "Set Tomcat permissions"
find "$tomcat_path/apache-tomcat-$tomcat_version/bin/" -type f -iname "*.sh" -exec chmod +x {} \;
chown -R tomcat:tomcat $tomcat_path
log_message "changed" "Tomcat permissions set"

# ========== Create Tomcat Init Script ==========
log_message "task" "Create Tomcat init.d script"
cat > /etc/init.d/tomcat <<'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          tomcat
# Required-Start:    $remote_fs $syslog $network mysql
# Required-Stop:     $remote_fs $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Tomcat at boot time
# Description:       Enable Tomcat servlet container
### END INIT INFO

TOMCAT_USER=tomcat
TOMCAT_HOME=/opt/tomcat/apache-tomcat-9.0.112

case $1 in
    start)
        echo "Starting Tomcat..."
        su - $TOMCAT_USER -s /bin/bash -c "$TOMCAT_HOME/bin/startup.sh"
        ;;
    stop)
        echo "Stopping Tomcat..."
        su - $TOMCAT_USER -s /bin/bash -c "$TOMCAT_HOME/bin/shutdown.sh"
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if pgrep -f "org.apache.catalina.startup.Bootstrap" > /dev/null; then
            echo "Tomcat is running"
            exit 0
        else
            echo "Tomcat is not running"
            exit 1
        fi
        ;;
    *)
        echo "Usage: /etc/init.d/tomcat {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOF

chmod +x /etc/init.d/tomcat
update-rc.d tomcat defaults
log_message "changed" "Tomcat init script created"

# ========== Download and Build Guacamole Server ==========
log_message "task" "Download Guacamole Server $guac_version"
cd $guac_path

if [ ! -f "guacamole-server-$guac_version.tar.gz" ]; then
    wget https://downloads.apache.org/guacamole/$guac_version/source/guacamole-server-$guac_version.tar.gz
    log_message "changed" "Guacamole Server downloaded"
else
    log_message "ok" "Guacamole Server archive already exists"
fi

if [ ! -d "$guac_path/guacamole-server-$guac_version" ]; then
    tar xzf guacamole-server-$guac_version.tar.gz
    log_message "changed" "Guacamole Server extracted"
else
    log_message "ok" "Guacamole Server already extracted"
fi

log_message "task" "Build and install Guacamole Server"
cd $guac_path/guacamole-server-$guac_version
./configure --with-init-dir=/etc/init.d
make
make install
ldconfig
log_message "changed" "Guacamole Server installed"

# ========== Create Guacamole Directories ==========
log_message "task" "Create Guacamole directories"
mkdir -p /etc/guacamole/extensions
mkdir -p /etc/guacamole/lib
log_message "changed" "Guacamole directories created"

# ========== Install MariaDB and Configure Database ==========
log_message "task" "Configure MariaDB for Guacamole"
service mariadb start
update-rc.d mariadb defaults

# Create database and user
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $db_name;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password';
GRANT SELECT,INSERT,UPDATE,DELETE ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
log_message "changed" "MariaDB database and user created"

# ========== Download MySQL Connector ==========
log_message "task" "Download MySQL Connector/J $mysql_connector_version"
cd $guac_path

if [ ! -f "mysql-connector-j-$mysql_connector_version.tar.gz" ]; then
    wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-$mysql_connector_version.tar.gz
    log_message "changed" "MySQL Connector downloaded"
else
    log_message "ok" "MySQL Connector already exists"
fi

if [ ! -d "$guac_path/mysql-connector-j-$mysql_connector_version" ]; then
    tar xzf mysql-connector-j-$mysql_connector_version.tar.gz
    log_message "changed" "MySQL Connector extracted"
else
    log_message "ok" "MySQL Connector already extracted"
fi

cp $guac_path/mysql-connector-j-$mysql_connector_version/mysql-connector-j-$mysql_connector_version.jar /etc/guacamole/lib/
log_message "changed" "MySQL Connector installed"

# ========== Download and Install Guacamole MySQL Extension ==========
log_message "task" "Download Guacamole MySQL authentication extension"
cd $guac_path

if [ ! -f "guacamole-auth-jdbc-$guac_version.tar.gz" ]; then
    wget https://downloads.apache.org/guacamole/$guac_version/binary/guacamole-auth-jdbc-$guac_version.tar.gz
    log_message "changed" "Guacamole MySQL extension downloaded"
else
    log_message "ok" "Guacamole MySQL extension already exists"
fi

if [ ! -d "$guac_path/guacamole-auth-jdbc-$guac_version" ]; then
    tar xzf guacamole-auth-jdbc-$guac_version.tar.gz
    log_message "changed" "Guacamole MySQL extension extracted"
else
    log_message "ok" "Guacamole MySQL extension already extracted"
fi

cp $guac_path/guacamole-auth-jdbc-$guac_version/mysql/guacamole-auth-jdbc-mysql-$guac_version.jar /etc/guacamole/extensions/
log_message "changed" "Guacamole MySQL extension installed"

# ========== Initialize Database Schema ==========
log_message "task" "Initialize Guacamole database schema"
cat $guac_path/guacamole-auth-jdbc-$guac_version/mysql/schema/*.sql | mysql -u root $db_name
log_message "changed" "Database schema initialized"

# ========== Create Admin User in Database ==========
log_message "task" "Create admin user in database"
guacamole_webadmin_password_hash=$(echo -n "$guacamole_webadmin_password" | openssl dgst -binary -sha256 | openssl enc -base64)
guacamole_webadmin_password_salt=$(openssl rand -base64 32)
guacamole_webadmin_password_hash_salt=$(echo -n "$guacamole_webadmin_password_hash$guacamole_webadmin_password_salt" | openssl dgst -binary -sha256 | openssl enc -base64)

mysql -u root $db_name <<MYSQL_ADMIN
INSERT INTO guacamole_entity (name, type) VALUES ('$guacamole_webadmin_username', 'USER');
SET @entity_id = LAST_INSERT_ID();
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
VALUES (@entity_id, 
        UNHEX(SHA2('$guacamole_webadmin_password', 256)),
        UNHEX(SHA2(CONCAT('$guacamole_webadmin_password', HEX(RANDOM_BYTES(32))), 256)),
        NOW());
INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT @entity_id, guacamole_user.user_id, 'ADMINISTER'
FROM guacamole_user WHERE guacamole_user.entity_id = @entity_id;
INSERT INTO guacamole_system_permission (entity_id, permission)
VALUES (@entity_id, 'ADMINISTER'),
       (@entity_id, 'CREATE_USER'),
       (@entity_id, 'CREATE_USER_GROUP'),
       (@entity_id, 'CREATE_CONNECTION'),
       (@entity_id, 'CREATE_CONNECTION_GROUP'),
       (@entity_id, 'CREATE_SHARING_PROFILE');
MYSQL_ADMIN
log_message "changed" "Admin user created in database"

# ========== Create guacamole.properties ==========
log_message "task" "Create guacamole.properties"
cat > /etc/guacamole/guacamole.properties <<EOF
# Guacamole server settings
guacd-hostname: 127.0.0.1
guacd-port: 4822

# MySQL properties
mysql-hostname: 127.0.0.1
mysql-port: 3306
mysql-database: $db_name
mysql-username: $db_user
mysql-password: $db_password
EOF
log_message "changed" "guacamole.properties created"
log_message "info" "Admin username: $guacamole_webadmin_username"
log_message "info" "Admin password: $guacamole_webadmin_password"

# ========== Create guacd.conf ==========
log_message "task" "Create guacd.conf"
touch /etc/guacamole/guacd.conf
log_message "changed" "guacd.conf created"

# ========== Create guacd User (RDP Fix) ==========
log_message "task" "Create guacd user for RDP support"
if id "guacd" &>/dev/null; then
    log_message "ok" "User 'guacd' already exists"
else
    useradd -r -c "Guacd Service User" -d /home/guacd -s /sbin/nologin guacd
    mkdir -p /home/guacd
    chown -R guacd:guacd /home/guacd
    log_message "changed" "User 'guacd' created"
fi

# ========== Start guacd Directly ==========
log_message "task" "Start guacd daemon"
# WSL1 doesn't handle init scripts well, so start guacd directly
/usr/local/sbin/guacd
sleep 2
if pgrep -x guacd > /dev/null; then
    log_message "changed" "guacd started successfully"
else
    log_message "error" "Failed to start guacd"
fi

# ========== Download Guacamole Client ==========
log_message "task" "Download Guacamole Client $guac_version"
cd $guac_path

if [ ! -f "guacamole-$guac_version.war" ]; then
    wget https://downloads.apache.org/guacamole/$guac_version/binary/guacamole-$guac_version.war -P /etc/guacamole/
    log_message "changed" "Guacamole Client downloaded"
else
    log_message "ok" "Guacamole Client already downloaded"
fi

# ========== Create Symlink for Guacamole in Tomcat ==========
log_message "task" "Create symlinks for Guacamole"
ln -sf /etc/guacamole $tomcat_path/apache-tomcat-$tomcat_version/.guacamole
ln -sf /etc/guacamole/guacamole-$guac_version.war $tomcat_path/apache-tomcat-$tomcat_version/webapps/guacamole.war
chown -R tomcat:tomcat $tomcat_path
log_message "changed" "Symlinks created"

# ========== Create Startup Script ==========
log_message "task" "Create startup script for WSL"
cat > /usr/local/bin/start-guacamole.sh <<'STARTSCRIPT'
#!/bin/bash
# Start MariaDB
service mariadb start
sleep 2

# Start guacd in background
/usr/local/sbin/guacd
sleep 2

# Start Tomcat
service tomcat start
sleep 2

echo "Guacamole services started"
STARTSCRIPT

chmod +x /usr/local/bin/start-guacamole.sh
log_message "changed" "Startup script created at /usr/local/bin/start-guacamole.sh"

# ========== Configure Auto-Start in .bashrc ==========
log_message "task" "Configure auto-start for guac user"
GUAC_USER=$(ls /home | head -1)
if [ -n "$GUAC_USER" ]; then
    cat >> /home/$GUAC_USER/.bashrc <<'BASHRC'

# Auto-start Guacamole services
if ! pgrep -x guacd > /dev/null; then
    sudo /usr/local/bin/start-guacamole.sh > /dev/null 2>&1
fi
BASHRC
    log_message "changed" "Auto-start configured in /home/$GUAC_USER/.bashrc"
    
    # Configure passwordless sudo for startup script
    echo "$GUAC_USER ALL=(ALL) NOPASSWD: /usr/local/bin/start-guacamole.sh" > /etc/sudoers.d/guacamole-startup
    chmod 440 /etc/sudoers.d/guacamole-startup
    log_message "changed" "Passwordless sudo configured for startup script"
fi

# ========== Enable and Start Services ==========
log_message "task" "Enable and start services"
service tomcat start
log_message "changed" "Services started"

# ========== Display Status ==========
log_message "task" "Check service status"
sleep 3
if pgrep -x guacd > /dev/null; then
    echo "guacd is running"
else
    echo "guacd is not running"
fi
service tomcat status

log_message "info" "========================================="
log_message "info" "Guacamole installation completed!"
log_message "info" "========================================="
log_message "info" "Access Guacamole at: http://localhost:$tomcat_port/guacamole/"
log_message "info" "Username: $guacamole_webadmin_username"
log_message "info" "Password: $guacamole_webadmin_password"
log_message "info" "========================================="
log_message "info" "Database: $db_name"
log_message "info" "DB User: $db_user"
log_message "info" "========================================="
log_message "info" "To add connections, log in and go to:"
log_message "info" "Settings → Connections → New Connection"
log_message "info" "========================================="
log_message "info" "Auto-start script: /usr/local/bin/start-guacamole.sh"
log_message "info" "Services will start automatically when WSL starts"
log_message "info" "========================================="
