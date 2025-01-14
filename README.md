# SafeKeep-DB 🔒💾 Database Backup Automation

## 🌟 Overview
SafeKeep-DB is a robust, flexible MySQL database backup solution designed for multi-server environments. Featuring parallel backups, intelligent error handling, Discord notifications, and comprehensive logging.

## ✨ Key Features
- 🌐 Multi-Server Support
  - Backup databases across different servers
  - Unique credentials per server/database
- 🚀 Parallel Backup Processing
  - Configurable simultaneous backup limits
- 🔄 Advanced Error Handling
  - Automatic retry mechanisms
  - Configurable retry attempts and delays
- 📣 Real-time Discord Notifications
- 💾 Flexible Backup Modes
  - Full backup
  - Incremental backup
- 🔐 Security Enhancements
  - Secure environment variable management
  - Disk space validation
- 📊 Comprehensive Logging
  - Detailed backup logs
  - Automatic log rotation

## 🛠 Prerequisites
- Linux/Unix Environment
- MySQL Client
- Required Utilities:
  - `mysqldump`
  - `curl`
  - `jq`
  - `gzip`

```bash
sudo apt-get update
sudo apt-get install curl jq gzip mariadb-client
```

or

```bash
# Install MySQL Client
sudo apt-get install curl jq gzip mysql-client mariadb-client
```

## 🚀 Quick Installation
```bash
# Clone the repository
git clone https://github.com/seu-usuario/SafeKeep-DB.git
cd SafeKeep-DB

# Set executable permissions
chmod +x backup_script.sh

# Create and edit .env file
cp .env.example .env
nano .env
```

## 🔧 Configuration Guide

### `.env` Configuration
```bash
# Database Server Configurations
# Format: HOST;USER;PASSWORD;DBNAME1,DBNAME2
DATABASES_CONFIG=localhost;mainuser;mainpass;maindb1,maindb2;
                192.168.1.100;seconduser;secondpass;seconddb1,seconddb2

# Backup Settings
MAX_PARALLEL_BACKUPS=3       # Max simultaneous backups
MAX_BACKUP_FILES=7            # Backup files to retain
BACKUP_MODE=full              # Backup mode (full/incremental)
MAX_RETRY_ATTEMPTS=3          # Retry attempts for failed backups
RETRY_DELAY=30                # Delay between retry attempts (seconds)

# Backup Directory
BACKUP_DIRECTORY=/path/to/backups/

# Discord Webhook for Notifications
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/your/webhook
```

## 📅 Execution Methods

### Manual Execution
```bash
./backup_script.sh
```

### Automated Scheduling (Crontab)
```bash
# Open crontab
crontab -e

# Examples:
# Daily at midnight
0 0 * * * /path/to/SafeKeep-DB/backup_script.sh

# Every 6 hours
0 */6 * * * /path/to/SafeKeep-DB/backup_script.sh
```

## 🔍 Monitoring
- Check backup logs in `BACKUP_DIRECTORY`
- Monitor Discord notifications
- Review system logs for detailed insights

## 🛡️ Security Recommendations
- Restrict `.env` file permissions: `chmod 600 .env`
- Use strong, unique database passwords
- Regularly update backup scripts
- Monitor Discord notification channels

## 🤝 Contribute
1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## 📄 License
MIT License

## 📧 Support
Open an issue on GitHub for bugs or feature requests.
