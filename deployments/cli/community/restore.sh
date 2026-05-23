#!/bin/bash

function print_header() {
clear

cat <<"EOF"
--------------------------------------------
 ____  _                          ///////// 
|  _ \| | __ _ _ __   ___         ///////// 
| |_) | |/ _` | '_ \ / _ \   /////    ///// 
|  __/| | (_| | | | |  __/   /////    ///// 
|_|   |_|\__,_|_| |_|\___|        ////      
                                  ////      
--------------------------------------------
Project management tool from the future
--------------------------------------------
EOF
}

function restoreSingleVolume() {
    selectedVolume=$1
    backupFolder=$2
    restoreFile=$3

    ${CONTAINER_CMD} volume rm "$selectedVolume" > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to remove volume $selectedVolume"
        echo ""
        return 1
    fi

    ${CONTAINER_CMD} volume create "$selectedVolume" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create volume $selectedVolume"
        echo ""
        return 1
    fi

    ${CONTAINER_CMD} run --rm \
        -e TAR_NAME="$restoreFile" \
        -v "$selectedVolume":"/vol" \
        -v "$backupFolder":/backup \
        busybox sh -c 'mkdir -p /restore && tar -xzf "/backup/${TAR_NAME}.tar.gz" -C /restore && mv /restore/${TAR_NAME}/* /vol'
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to restore volume ${selectedVolume} from ${restoreFile}.tar.gz"
        echo ""
        return 1
    fi
    echo ".....Successfully restored volume $selectedVolume from ${restoreFile}.tar.gz"
    echo ""
}

function restoreData() {
    print_header
    local BACKUP_FOLDER=${1:-$PWD}

    local dockerServiceStatus
    dockerServiceStatus=$($COMPOSE_CMD ls --filter name=plane-app --format=json | jq -r .[0].Status)
    local dockerServicePrefix
    dockerServicePrefix="running"

    if [[ $dockerServiceStatus == $dockerServicePrefix* ]]; then
        echo "Plane App is running. Please STOP the Plane App before restoring data."
        exit 1
    fi

    local volume_suffix
    volume_suffix="_pgdata|_redisdata|_uploads|_rabbitmq_data"
    local volumes
    volumes=$(${CONTAINER_CMD} volume ls -f "name=plane-app" --format "{{.Name}}" | grep -E "$volume_suffix")
    # Check if there are any matching volumes
    if [ -z "$volumes" ]; then
        echo ".....No volumes found starting with 'plane-app'"
        exit 1
    fi
    

    for BACKUP_FILE in $BACKUP_FOLDER/*.tar.gz; do
        if [ -e "$BACKUP_FILE" ]; then
            
            local restoreFileName
            restoreFileName=$(basename "$BACKUP_FILE")
            restoreFileName="${restoreFileName%.tar.gz}"

            local restoreVolName
            restoreVolName="plane-app_${restoreFileName}"
            echo "Found $BACKUP_FILE"

            local docVol
            docVol=$(${CONTAINER_CMD} volume ls -f "name=$restoreVolName" --format "{{.Name}}" | grep -E "$volume_suffix")

            if [ -z "$docVol" ]; then
                echo "Skipping: No volume found with name $restoreVolName"
            else
                echo ".....Restoring $docVol"
                restoreSingleVolume "$docVol" "$BACKUP_FOLDER" "$restoreFileName"
            fi
        else
            echo "No .tar.gz files found in the current directory."
            echo ""
            echo "Please provide the path to the backup file."
            echo ""
            echo "Usage: ./restore.sh /path/to/backup"
            exit 1
        fi
    done

    echo ""
    echo "Restore completed successfully."
    echo ""
}

ORCHESTRATOR="podman"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --orchestrator)
            ORCHESTRATOR="$2"
            shift 2
            ;;
        --orchestrator=*)
            ORCHESTRATOR="${1#*=}"
            shift 1
            ;;
        *)
            break
            ;;
    esac
done

ORCHESTRATOR="$(echo "${ORCHESTRATOR}" | tr '[:upper:]' '[:lower:]')"
CONTAINER_CMD=""
COMPOSE_CMD=""
case "${ORCHESTRATOR}" in
    podman)
        CONTAINER_CMD="podman"
        COMPOSE_CMD="podman compose"
        ;;
    docker)
        CONTAINER_CMD="docker"
        if command -v docker-compose &> /dev/null; then
            COMPOSE_CMD="docker-compose"
        else
            COMPOSE_CMD="docker compose"
        fi
        ;;
    *)
        echo "Unsupported orchestrator '${ORCHESTRATOR}'. Use 'podman' or 'docker'."
        exit 1
        ;;
esac

if ! command -v "${CONTAINER_CMD}" &> /dev/null; then
    echo "${CONTAINER_CMD} is not installed or not in PATH."
    exit 1
fi

restoreData "$@"