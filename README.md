
# WSL Guacamole

![MIT License](https://img.shields.io/badge/license-MIT-green.svg)
![Last Commit](https://img.shields.io/github/last-commit/csphu/wsl-guacamole?style=flat)
![Issues](https://img.shields.io/github/issues/csphu/wsl-guacamole?style=flat)

Automated WSL1-based Apache Guacamole installation with MariaDB authentication and VPN support.

## Features

- **Apache Guacamole 1.5.5** - HTML5 remote desktop gateway
- **Apache Tomcat 9.0.112** - Servlet container
- **MariaDB Authentication** - Web-based connection management
- **WSL1 Network Stack** - Direct access to Windows loopback addresses (VPN compatible)
- **Auto-Start Services** - Automatic startup of all services when WSL starts

## Quick Start

1. **Build the WSL distro:**

   ```powershell
   .\Build.ps1
   ```

2. **Access Guacamole:**
   - URL: <http://localhost:8080/guacamole/>
   - Username: `guacadmin`
   - Password: `guacadmin`

3. **Add connections:**
   - Log in to Guacamole
   - Go to: Settings → Connections → New Connection
   - Configure your RDP/VNC/SSH connections

## Why WSL1 Works Well for VPNs

WSL1 uses the Windows network stack, allowing it to access all VPN connections, proxies, and custom loopback addresses configured on the Windows host. This makes it ideal for remote desktop gateways and similar tools that need to reach resources available only through a VPN or enterprise network.

## Architecture

- **WSL Version:** WSL1 (for Windows network stack compatibility)
- **Base Image:** Ubuntu 24.04.3 LTS
- **Java:** OpenJDK 11
- **Database:** MariaDB (guacamole_db)
- **Services:** MariaDB, guacd, Tomcat

## Service Management

Services auto-start when WSL starts. Manual control:

```bash
# Start all services
sudo /usr/local/bin/start-guacamole.sh

# Individual services
sudo service mariadb start
sudo service tomcat start
sudo /usr/local/sbin/guacd

# Check status
pgrep -x guacd
sudo service mariadb status
sudo service tomcat status
```

## Database Configuration

- **Database Name:** guacamole_db
- **Username:** guacamole_user
- **Password:** guacamole_pass
- **Admin User:** guacadmin / guacadmin

## First Login: Set Your Password

The default user is `guac`. After launching the distro for the first time, set your password by running:

```bash
passwd
```

You will then be able to use your chosen password for the `guac` user.

## Logs

- **Tomcat:** `/opt/tomcat/apache-tomcat-9.0.112/logs/catalina.out`
- **guacd:** `/var/log/guacd.log`
- **MariaDB:** `/var/log/mysql/error.log`

## Rebuilding

To rebuild from scratch:

```powershell
# Unregister existing distro
wsl --unregister Guacamole

# Build new distro
.\Build.ps1
```

## Troubleshooting

**Services not starting:**

```bash
# Check which services are running
ps aux | grep -E 'mariadb|guacd|tomcat'

# Restart services manually
sudo /usr/local/bin/start-guacamole.sh
```

**Can't connect to Guacamole:**

- Verify Tomcat is running: `sudo service tomcat status`
- Check Tomcat logs: `sudo tail -100 /opt/tomcat/apache-tomcat-9.0.112/logs/catalina.out`

**RDP connections failing:**

- Verify guacd is running: `pgrep -x guacd`
- Check guacd logs: `sudo tail -50 /var/log/guacd.log`

## Project Structure

```text
wsl-guacamole/
├── Build.ps1                          # Main build script
├── ubuntu-24.04.3-wsl-amd64.wsl      # Ubuntu base image (downloaded)
├── scripts/
│   ├── root.sh                        # Initial WSL configuration (user, sudoers, wsl.conf)
│   └── guac-install.sh               # Guacamole installation script
└── README.md                          # This file
```

## Requirements

- Windows 10/11 with WSL support
- PowerShell
- Internet connection for downloading packages

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Apache Guacamole is licensed under the Apache License 2.0.
