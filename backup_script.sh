#!/bin/bash

# Advanced Multi-Server Database Backup Script

# Function to check dependencies
check_dependencies() {
    local dependencies=("mysqldump" "curl" "jq" "gzip")
    local missing_deps=()
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    return 0
}

# Enhanced Logging Function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_file="${BACKUP_DIR}/backup_$(date +"%Y%m%d").log"
    
    # Ensure backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    # Log levels: DEBUG, INFO, WARNING, ERROR, SUCCESS
    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
}

# Function to send Discord webhook notification
send_discord_notification() {
    local status="$1"
    local message="$2"
    # Check if Discord webhook URL is set
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log "WARNING" "Discord webhook URL not configured"
        return 1
    fi
    
    # Prepare payload
    local payload=$(jq -n \
        --arg status "$status" \
        --arg message "$message" \
        '{
            "content": null,
            "embeds": [{
                "title": "Database Backup '"$status"'",
                "description": "'"$message"'",
                "color": '"$([ "$status" = "Success" ] && echo "5763719" || echo "15548997")"',
                "timestamp": "'"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"'"
            }]
        }')
    
    # Send notification
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "$payload" \
         "$DISCORD_WEBHOOK_URL" > /dev/null
}

# Disk Space Check Function
check_disk_space() {
    local min_space_percent=10
    local backup_disk=$(df "$BACKUP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$backup_disk" -gt $((100 - min_space_percent)) ]; then
        log "ERROR" "Low disk space: Only $((100 - backup_disk))% free"
        send_discord_notification "Error" "Low disk space: Only $((100 - backup_disk))% free in backup directory"
        return 1
    fi
}

# Advanced Backup Function with Retry Mechanism
advanced_backup_database() {
    local DB_HOST="$1"
    local DB_USER="$2"
    local DB_PASS="$3"
    local DB_NAME="$4"
    local BACKUP_DIR="$5"
    local retry_count=0
    local BACKUP_MODE="${6:-full}"
    local MAX_RETRY_ATTEMPTS="${7:-3}"
    local RETRY_DELAY="${8:-30}"

    log "INFO" "Starting backup for database $DB_NAME on host $DB_HOST"

    while [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; do
        local BACKUP_FILE="${BACKUP_DIR}/backup_${DB_HOST}_${DB_NAME}_$(date +"%Y%m%d_%H%M%S")"
        
        # Backup Mode Selection
        case "$BACKUP_MODE" in
            "full")
                mysqldump_command="mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS --single-transaction --routines --triggers $DB_NAME"
                BACKUP_FILE+=".sql.gz"
                ;;
            "incremental")
                # Requires MySQL with binary logging enabled
                mysqldump_command="mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASS --single-transaction --master-data=2 $DB_NAME"
                BACKUP_FILE+=".sql"
                ;;
            *)
                log "ERROR" "Invalid backup mode: $BACKUP_MODE"
                return 1
                ;;
        esac

        # Execute backup with error handling
        if $mysqldump_command | gzip > "$BACKUP_FILE"; then
            log "SUCCESS" "Backup of $DB_NAME from $DB_HOST completed successfully"
            send_discord_notification "Success" "Backup of $DB_NAME from $DB_HOST completed successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "WARNING" "Backup attempt $retry_count failed for $DB_NAME on $DB_HOST"
            
            if [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; then
                log "INFO" "Retrying backup in $RETRY_DELAY seconds..."
                sleep $RETRY_DELAY
            else
                log "ERROR" "All backup attempts for $DB_NAME failed"
                send_discord_notification "Error" "Failed to backup database $DB_NAME on host $DB_HOST after $MAX_RETRY_ATTEMPTS attempts"
                return 1
            fi
        fi
    done
}

# Parallel Backup Function
parallel_backup() {
    local CONFIGS=("$@")
    local pids=()
    local MAX_PARALLEL_BACKUPS="${MAX_PARALLEL_BACKUPS:-3}"
    local BACKUP_MODE="${BACKUP_MODE:-full}"

    log "INFO" "Starting parallel database backups"

    for config in "${CONFIGS[@]}"; do
        # Skip empty configs
        [ -z "$config" ] && continue

        # Split config into components
        IFS=',' read -ra DB_DETAILS <<< "$config"
        
        # Validate configuration
        if [ ${#DB_DETAILS[@]} -lt 4 ]; then
            log "ERROR" "Invalid database configuration: $config"
            continue
        fi

        # Extract connection details
        DB_HOST="${DB_DETAILS[0]}"
        DB_USER="${DB_DETAILS[1]}"
        DB_PASS="${DB_DETAILS[2]}"
        
        # Backup databases in parallel
        for db in "${DB_DETAILS[@]:3}"; do
            # Wait if maximum parallel backups reached
            while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL_BACKUPS ]; do
                sleep 5
            done

            advanced_backup_database "$DB_HOST" "$DB_USER" "$DB_PASS" "$db" "$BACKUP_DIR" "$BACKUP_MODE" &
            pids+=($!)
        done
    done

    # Wait for all background processes to complete
    for pid in "${pids[@]}"; do
        wait $pid
    done

    log "INFO" "Parallel backup process completed"
}

# Cleanup function
cleanup_old_backups() {
    local BACKUP_DIR="$1"
    local MAX_BACKUPS="${2:-7}"
    local log_file="${BACKUP_DIR}/backup_$(date +"%Y%m%d").log"

    log "INFO" "Cleaning up old backups, keeping last $MAX_BACKUPS"
    
    # Remove old backup files
    find "$BACKUP_DIR" -maxdepth 1 -name "backup_*" -type f -print0 | sort -zn | head -zn -"$MAX_BACKUPS" | xargs -0 rm -f

    # Remove old log files older than 30 days
    find "$BACKUP_DIR" -maxdepth 1 -name "backup_*.log" -type f -mtime +30 -delete

    log "INFO" "Backup cleanup completed"
}

# Main backup script
main() {
    # Check dependencies first
    if ! check_dependencies; then
        send_discord_notification "Error" "Dependency check failed. Backup aborted."
        exit 1
    }

    # Path to .env file
    ENV_FILE="/home/pi/database_backups/.env"

    # Load environment variables
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
        send_discord_notification "Error" ".env file not found!"
        exit 1
    }

    # Backup directory with fallback
    BACKUP_DIR="${BACKUP_DIRECTORY:-/home/pi/database_backups/}"
    mkdir -p "$BACKUP_DIR"

    # Set secure permissions
    chmod 700 "$BACKUP_DIR"

    # Check disk space before proceeding
    if ! check_disk_space; then
        exit 1
    fi

    # Track overall backup status
    OVERALL_BACKUP_SUCCESS=true

    # Parse and backup databases
    IFS=';' read -ra CONFIGS <<< "$DATABASES_CONFIG"
    
    # Start parallel backup
    parallel_backup "${CONFIGS[@]}"

    # Clean up old backups
    cleanup_old_backups "$BACKUP_DIR" "$MAX_BACKUP_FILES"

    # Final notification
    if [ "$OVERALL_BACKUP_SUCCESS" = true ]; then
        send_discord_notification "Success" "Database backup process completed successfully for all configured databases."
    else
        send_discord_notification "Warning" "Database backup process completed with some failures. Check logs for details."
    fi
}

# Run main script
main