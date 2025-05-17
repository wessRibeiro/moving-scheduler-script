#!/bin/bash

set -e

# SETTINGS
SOURCE_PROJECT=""
DESTINATION_PROJECT=""
SOURCE_LOCATION=""
DESTINATION_LOCATION=""
SCHEDULERS_FILE="schedulers.json"

# LOG COLORS
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error_exit() { echo -e "${RED}Erro: $1. Finished.${NC}"; exit 1; }

scheduler_job_exists() {
  local project_id="$1"
  local region="$2"
  local job_name="$3"

  gcloud scheduler jobs describe "$job_name" \
    --project="$project_id" \
    --location="$region" &> /dev/null
}

# Initializing file JSON
if [[ ! -s "$SCHEDULERS_FILE" ]]; then
  echo "[]" > "$SCHEDULERS_FILE"
fi

log "🔍 Listing jobs from project source ${SOURCE_PROJECT}..."
readarray -t jobs < <(
  gcloud scheduler jobs list \
    --project="$SOURCE_PROJECT" \
    --location="$SOURCE_LOCATION" \
    --format="value(name)"
)

if [ ${#jobs[@]} -eq 0 ]; then
  error_exit "No jobs found in project $SOURCE_PROJECT in location $SOURCE_LOCATION"
fi

log "📋 Jobs found:"
for job in "${jobs[@]}"; do
  echo "- $job"
done
echo -e "\n"

for full_job_name in "${jobs[@]}"; do
  JOB_NAME=$(basename "$full_job_name")
  echo -e "${BLUE}wish copy job '${JOB_NAME}' to project '${DESTINATION_PROJECT}'? (s/n)${NC}"
  read -r answer
  if [[ "$answer" =~ ^[sS]$ ]]; then
    if scheduler_job_exists "$DESTINATION_PROJECT" "$DESTINATION_LOCATION" "$JOB_NAME"; then
      warn "⚠️  Job '$JOB_NAME' has alredy exists in project target. Next..."
    else
        log "📤 Coping job '$JOB_NAME'..."

        job_json=$(gcloud scheduler jobs describe "$JOB_NAME" \
            --project="$SOURCE_PROJECT" \
            --location="$SOURCE_LOCATION" \
            --format=json) || error_exit "Error to describe job $JOB_NAME"

        # Vality JSON
        echo "$job_json" | jq empty || error_exit "JSON error job $JOB_NAME"

        # Apend to schedulers.json
        tmp_file=$(mktemp)
        jq --argjson newJob "$job_json" '. + [$newJob]' "$SCHEDULERS_FILE" > "$tmp_file" && mv "$tmp_file" "$SCHEDULERS_FILE"

        warn "⚠️  Review data before applying"
        read -p "Press ENTER to continue after reviewing."

        # Recreating job in project target
        JOB_TYPE=$(echo "$job_json" | jq -r 'if has("httpTarget") then "http" else "unknown" end')
        SCHEDULE=$(echo "$job_json" | jq -r '.schedule')
        TIMEZONE=$(echo "$job_json" | jq -r '.timeZone')
        DESCRIPTION=$(echo "$job_json" | jq -r '.description // empty')
        JOB_STATE=$(echo "$job_json" | jq -r '.state // "UNKNOWN"') 
        URI=$(echo "$job_json" | jq -r '.httpTarget.uri')
        METHOD=$(echo "$job_json" | jq -r '.httpTarget.httpMethod')
        # Gera um único argumento --headers com todos os pares chave:valor
        HEADERS=$(echo "$job_json" | jq -r '.httpTarget.headers // {}')


        # Extract and decodify the body (that's base64 from JSON array)
        BODY_BASE64=$(echo "$job_json" | jq -r '.httpTarget.body // empty')
        
        # Retry config
        RETRY_FLAGS=""
        MAX_ATTEMPTS=$(echo "$job_json" | jq -r '.retryConfig.retryCount // empty')
        [[ -n "$MAX_ATTEMPTS" && "$MAX_ATTEMPTS" != "null" ]] && RETRY_FLAGS+=" --max-retry-attempts=$MAX_ATTEMPTS"

        MAX_RETRY_DURATION=$(echo "$job_json" | jq -r '.retryConfig.maxRetryDuration // empty')
        [[ -n "$MAX_RETRY_DURATION" && "$MAX_RETRY_DURATION" != "null" ]] && RETRY_FLAGS+=" --max-retry-duration=$MAX_RETRY_DURATION"

        MIN_BACKOFF=$(echo "$job_json" | jq -r '.retryConfig.minBackoffDuration // empty')
        [[ -n "$MIN_BACKOFF" && "$MIN_BACKOFF" != "null" ]] && RETRY_FLAGS+=" --min-backoff=$MIN_BACKOFF"

        MAX_BACKOFF=$(echo "$job_json" | jq -r '.retryConfig.maxBackoffDuration // empty')
        [[ -n "$MAX_BACKOFF" && "$MAX_BACKOFF" != "null" ]] && RETRY_FLAGS+=" --max-backoff=$MAX_BACKOFF"

        MAX_DOUBLINGS=$(echo "$job_json" | jq -r '.retryConfig.maxDoublings // empty')
        [[ -n "$MAX_DOUBLINGS" && "$MAX_DOUBLINGS" != "null" ]] && RETRY_FLAGS+=" --max-doublings=$MAX_DOUBLINGS" 

        # Creating job HTTP (can adapt to Pub/Sub or others)
        log "🛠️  Creating job '$JOB_NAME' in project destination..."

        create_cmd="gcloud scheduler jobs create http \"$JOB_NAME\" \
            --project=\"$DESTINATION_PROJECT\" \
            --location=\"$DESTINATION_LOCATION\" \
            --schedule=\"$SCHEDULE\" \
            --time-zone=\"$TIMEZONE\" \
            --uri=\"$URI\" \
            --http-method=\"$METHOD\""

        #body
        if [[ -n "$BODY_BASE64" && "$BODY_BASE64" != "null" ]]; then
            BODY_JSON=$(echo "$BODY_BASE64" | base64 --decode 2>/dev/null | jq -c .)
            create_cmd+=" --message-body='$BODY_JSON'"
        fi

        # Headers
        if [[ "$HEADERS" != "{}" ]]; then
            HEADER_STRING="--headers='"
            while IFS="=" read -r key value; do
                HEADER_STRING+=" ${key}=${value},"
            done < <(echo "$HEADERS" | jq -r 'to_entries[] | "\(.key)=\(.value)"')

            create_cmd+=" $HEADER_STRING'"
        fi

        # Description
        if [[ -n "$DESCRIPTION" ]]; then
            create_cmd+=" --description=\"$DESCRIPTION\""
        fi

        # retry
        if [[ -n "$RETRY_FLAGS" ]]; then
            create_cmd+=" $RETRY_FLAGS "
        fi

        # Run
        echo "$create_cmd" || error_exit "Error to create job $JOB_NAME"
        eval "$create_cmd" || error_exit "Error to create job $JOB_NAME"
        
        log "✅ Job '$JOB_NAME' created."
  
        # pause job if it is paused from origin
        if [[ "$JOB_STATE" == "PAUSED" ]]; then
            log "⏸️  Pausing job '$JOB_NAME' in project destination..."
            gcloud scheduler jobs pause "$JOB_NAME" \
                --project="$DESTINATION_PROJECT" \
                --location="$DESTINATION_LOCATION" || warn "⚠️ Error to pause job '$JOB_NAME'"
        fi

        log "⏸️  Pausing job '$JOB_NAME' in project source..."
        gcloud scheduler jobs pause "$JOB_NAME" \
            --project="$SOURCE_PROJECT" \
            --location="$SOURCE_LOCATION" || warn "⚠️  Error to pause job '$JOB_NAME'"
    
    fi
  else
    log "⏭️  next job '$JOB_NAME'"
  fi
done
