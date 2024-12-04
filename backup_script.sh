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
        exit 1
    fi
}

# Enhanced Logging Function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_file="${BACKUP_DIR}/backup_$(date +"%Y%m%d").log"
    
    mkdir -p "$BACKUP_DIR"
    echo "[$timestamp] [$level] $message" | tee -a "$log_file"
}

# Function to send Discord webhook notification
send_discord_notification() {
    local status="$1"
    local message="$2"
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log "WARNING" "Discord webhook URL not configured"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local color=$( [ "$status" = "Success" ] && echo 5763719 || echo 15548997 )

    local payload=$(jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg color "$color" \
        --arg timestamp "$timestamp" \
        '{
            "content": null,
            "embeds": [
                {
                    "title": "Database Backup \($status)",
                    "description": "\($message)",
                    "color": ($color | tonumber),
                    "timestamp": $timestamp
                }
            ]
        }')

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
        local BACKUP_FILE="${BACKUP_DIR}/backup_${DB_HOST}_${DB_NAME}_$(date +"%Y%m%d_%H%M%S").sql.gz"
        
        mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --single-transaction --routines --triggers "$DB_NAME" | gzip > "$BACKUP_FILE"

        if [ $? -eq 0 ]; then
            log "SUCCESS" "Backup of $DB_NAME from $DB_HOST completed successfully"
            send_discord_notification "Success" "Backup of $DB_NAME from $DB_HOST completed successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "WARNING" "Backup attempt $retry_count failed for $DB_NAME on $DB_HOST"

            if [ $retry_count -lt $MAX_RETRY_ATTEMPTS ]; then
                log "INFO" "Retrying backup in $RETRY_DELAY seconds..."
                sleep "$RETRY_DELAY"
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
    local CONFIGS="$DATABASES_CONFIG"
    local pids=()
    local MAX_PARALLEL_BACKUPS="${MAX_PARALLEL_BACKUPS:-3}"

    log "INFO" "Starting parallel database backups"

    # Lê as configurações separadas por ";"
    IFS=';' read -ra HOST_CONFIGS <<< "$CONFIGS"

    for host_config in "${HOST_CONFIGS[@]}"; do
        [ -z "$host_config" ] && continue

        # Divide por vírgulas dentro da configuração
        IFS=',' read -ra DB_DETAILS <<< "$host_config"
        if [ ${#DB_DETAILS[@]} -lt 4 ]; then
            log "ERROR" "Invalid database configuration: $host_config"
            continue
        fi

        DB_HOST="${DB_DETAILS[0]}"
        DB_USER="${DB_DETAILS[1]}"
        DB_PASS="${DB_DETAILS[2]}"
        DB_NAMES=("${DB_DETAILS[@]:3}")

        for db in "${DB_NAMES[@]}"; do
            while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL_BACKUPS ]; do
                sleep 5
            done

            advanced_backup_database "$DB_HOST" "$DB_USER" "$DB_PASS" "$db" "$BACKUP_DIR" &
            pids+=($!)
        done
    done

    for pid in "${pids[@]}"; do
        wait $pid
    done

    log "INFO" "Parallel backup process completed"
}

# Cleanup function
cleanup_old_backups() {
    local BACKUP_DIR="$1"
    local MAX_BACKUPS="${2:-7}"

    log "INFO" "Cleaning up old backups, keeping last $MAX_BACKUPS"
    find "$BACKUP_DIR" -type f -name "backup_*" -print0 | sort -zn | head -zn -"$MAX_BACKUPS" | xargs -0 rm -f
    find "$BACKUP_DIR" -type f -name "*.log" -mtime +30 -delete
    log "INFO" "Backup cleanup completed"
}

# Main backup script
main() {
    if ! check_dependencies; then
        send_discord_notification "Error" "Dependency check failed. Backup aborted."
        exit 1
    fi

    ENV_FILE="$(pwd)/.env"
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
        send_discord_notification "Error" ".env file not found!"
        exit 1
    fi

    BACKUP_DIR="${BACKUP_DIRECTORY:-$(pwd)/database_backups/}"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    if ! check_disk_space; then
        exit 1
    fi

    IFS=';' read -ra CONFIGS <<< "$DATABASES_CONFIG"
    parallel_backup "${CONFIGS[@]}"
    cleanup_old_backups "$BACKUP_DIR" "$MAX_BACKUP_FILES"

    send_discord_notification "Success" "Database backup process completed successfully for all configured databases."
}

main
