#!/bin/bash

# BroodSense Upload System
# ========================
#
# This script manages the automated upload of scan images from the BroodSense controller to the cloud platform.
# It uploads all missing files while preventing duplicates. The script is triggered after each scan but exits
# if another upload process is already running.
#
# Features:
# - Upload all unuploaded scan images (most recent first)
# - Prevents duplicate uploads by checking with the BroodSense API
# - Lock file mechanism to avoid concurrent uploads and handle stale locks
# - WiFi and internet connectivity checks
#
# Requirements:
# - USB device with valid config.env and scans directory
# - WiFi connection with internet access
# - curl, jq, and wireless-tools installed
# - BroodSense API credentials (LIVE_KEY) configured
#
# Usage:
# - Called automatically after a successful scan from scan.sh
# - Can be run manually to retry uploads
#

SCRIPT_DIR="$(dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/constants.sh"
source "$SCRIPT_DIR/logger.sh"
source "$SCRIPT_DIR/check_internet_and_sync_time.sh"

# Lock file logic: prevent concurrent runs, remove stale lock
if [ -f "$LOCKFILE_UPLOAD" ]; then
  lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCKFILE_UPLOAD") ))
  max_age=${LOCKFILE_UPLOAD_MAX_AGE:-3600}
  if [ "$lock_age" -gt "$max_age" ]; then
    broodsense_log warning "Lock file is stale (age ${lock_age}s > ${max_age}s), removing: $LOCKFILE_UPLOAD"
    rm -f "$LOCKFILE_UPLOAD"
  else
    broodsense_log warning "Another upload script is already running (lock file: $LOCKFILE_UPLOAD, age ${lock_age}s). Exiting."
    exit 1
  fi
fi

# Create lock file with current PID
echo $$ > "$LOCKFILE_UPLOAD"

# Ensure lock file is removed on exit (normal or error)
trap 'rm -f "$LOCKFILE_UPLOAD"' EXIT

# Load LIVE_KEY from user config
if [[ ! -f "$USB_CONFIG" ]]; then
    broodsense_log error "Config file not found: $USB_CONFIG"
    exit 1
fi
source "$USB_CONFIG"

# Exit if LIVE_KEY is not set
if [[ -z "$LIVE_KEY" ]]; then
    broodsense_log error "LIVE_KEY is not set, cannot upload scans to cloud."
    exit 1
fi

# Ensure WiFi is connected and internet is reachable.
# In always-on (cronjob) mode the connection may have dropped since startup;
# ensure_wifi_and_internet() will attempt a reconnect when WIFI_SSID is configured.
if ! ensure_wifi_and_internet; then
  broodsense_log warning "No internet connectivity. Cannot upload scans to cloud."
  exit 0
fi

# Helper: Convert filename (YYYY-MM-DDTHH-MM-SSZ.jpg) to UTC timestamp
filename_to_ts() {
  local fname="$1"
  local base="${fname%.*}"
  local base_noz="${base%Z}"
  # Replace T with space
  local date_str="${base_noz//T/ }"
  # Replace hyphens in time part with colons
  date_str="${date_str:0:13}:${date_str:14:2}:${date_str:17:2}"
  date -u -d "$date_str" +%s 2>/dev/null
}

# Step 0: Get already uploaded timestamps from API
broodsense_log info "Fetching already uploaded timestamps from BroodSense API..."
RAW_TS_RESPONSE=$(curl -s -L -w "\n%{http_code}" --max-time 30 "$BROODSENSE_API_EXISTING_SCANS?liveKey=${LIVE_KEY}")
RAW_TS_BODY=$(echo "$RAW_TS_RESPONSE" | head -n -1)
RAW_TS_CODE=$(echo "$RAW_TS_RESPONSE" | tail -n 1)

if [[ "$RAW_TS_CODE" == "000" ]]; then
    broodsense_log error "API unreachable (curl failed - DNS failure or SSL error)."
    exit 1
elif [[ "$RAW_TS_CODE" -eq 404 ]]; then
    broodsense_log error "No frame document found for liveKey '$LIVE_KEY'. Create it manually on the server first."
    exit 1
elif [[ "$RAW_TS_CODE" -ne 200 ]]; then
    broodsense_log error "API returned HTTP $RAW_TS_CODE: $RAW_TS_BODY"
    exit 1
elif ! echo "$RAW_TS_BODY" | jq -e 'has("allTs")' >/dev/null 2>&1; then
    broodsense_log error "Invalid API response (missing 'allTs' key): $RAW_TS_BODY"
    exit 1
fi

declare -A uploaded_map
mapfile -t _uploaded_ts < <(echo "$RAW_TS_BODY" | jq -r '.allTs[]')
for ts in "${_uploaded_ts[@]}"; do
  uploaded_map[$ts]=1
done
broodsense_log info "Already uploaded on server: ${#_uploaded_ts[@]} scan(s)."

# Step 1: Find all files in SCAN_DIR matching the pattern (newest first)
if [[ -z "$SCAN_DIR" || ! -d "$SCAN_DIR" ]]; then
    broodsense_log error "Scan directory not found or not set: '${SCAN_DIR}'. Is the USB device mounted?"
    exit 1
fi
broodsense_log info "Scanning for files to upload in $SCAN_DIR ..."
FILES_TO_UPLOAD=()
shopt -s nullglob
mapfile -t _all_files < <(find "$SCAN_DIR" -maxdepth 1 -name "*.${FORMAT}" -printf "%T@ %p\n" | sort -rn | awk '{print $2}')
for f in "${_all_files[@]}"; do
  fname=$(basename "$f")
  ts=$(filename_to_ts "${fname}")
  if [[ -z "$ts" ]]; then
    broodsense_log warning "Skipping file with unrecognized name: $fname (Expected format: YYYY-MM-DDTHH-MM-SSZ.${FORMAT})"
    continue
  fi
  if [[ -z "${uploaded_map[$ts]}" ]]; then
    FILES_TO_UPLOAD+=("$f")
  else
    broodsense_log debug "Already uploaded: $fname (timestamp: $ts) (skipping)"
  fi
done
shopt -u nullglob

broodsense_log info "Files to upload: ${#FILES_TO_UPLOAD[@]}"
for f in "${FILES_TO_UPLOAD[@]}"; do
  broodsense_log debug "  $(basename "$f")"
done

# Step 2: Loop through files and upload each (most recent first)
for IMAGE_FILE in "${FILES_TO_UPLOAD[@]}"; do

  # Touch lock file to update its timestamp so it doesn't get considered stale
  touch "$LOCKFILE_UPLOAD"

  FILENAME=$(basename "$IMAGE_FILE")

  UPLOAD_URL_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$BROODSENSE_API_UPLOAD" \
    -H "Content-Type: application/json" \
    -d "{\"liveKey\": \"${LIVE_KEY}\",\"filename\": \"${FILENAME}\"}" \
    --max-time 30
  )

  UPLOAD_URL_BODY=$(echo "$UPLOAD_URL_RESPONSE" | head -n -1)
  UPLOAD_URL_CODE=$(echo "$UPLOAD_URL_RESPONSE" | tail -n 1)

  broodsense_log debug "GetUploadUrl Status: $UPLOAD_URL_CODE"

  if [ "$UPLOAD_URL_CODE" -ne 200 ]; then
    broodsense_log error "Failed to get upload URL for $FILENAME. Skipping."
    continue
  fi

  # Extract upload URL and raw ID from response
  UPLOAD_URL=$(echo "$UPLOAD_URL_BODY" | jq -r '.uploadUrl')
  RAW_ID=$(echo "$UPLOAD_URL_BODY" | jq -r '.rawId')

  if [ "$UPLOAD_URL" = "null" ] || [ -z "$UPLOAD_URL" ] || [ "$RAW_ID" = "null" ] || [ -z "$RAW_ID" ]; then
    broodsense_log error "Failed to extract upload URL or raw ID from response for $FILENAME. Skipping."
    continue
  fi

  broodsense_log debug "Upload URL obtained. Scan ID: $RAW_ID"

  # Start resumable upload session
  INITIATE_RESPONSE=$(curl -s -i -X POST "$UPLOAD_URL" \
    -H "Content-Length: 0" \
    -H "Content-Type: image/jpeg" \
    -H "X-Upload-Content-Type: image/jpeg" \
    -H "x-goog-resumable: start"
  )

  SESSION_URL=$(echo "$INITIATE_RESPONSE" | grep -i "^Location:" | awk '{print $2}' | tr -d '\r\n')

  if [ -z "$SESSION_URL" ]; then
      broodsense_log error "Failed to get session URL for resumable upload for $FILENAME."
      broodsense_log debug "Response headers: $INITIATE_RESPONSE"
      continue
  fi

  # Upload the actual file data
  UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PUT "$SESSION_URL" \
    -H "Content-Type: image/jpeg" \
    --data-binary "@${IMAGE_FILE}" \
    --max-time $TIMEOUT_UPLOAD
  )

  UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | head -n -1)
  UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -n 1)

  broodsense_log debug "Upload Status: $UPLOAD_CODE"
  if [ "$UPLOAD_CODE" -ne 200 ] && [ "$UPLOAD_CODE" -ne 201 ] && [ "$UPLOAD_CODE" -ne 308 ]; then
    broodsense_log error "Upload failed for $FILENAME. Response: $UPLOAD_BODY"
    continue
  fi

  broodsense_log info "Upload successful for $FILENAME!"
done
