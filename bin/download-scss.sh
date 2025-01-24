#!/bin/bash

# Recursive SCSS downloader with `_` prefixed file support and 200 OK checks

TMP_FILES_TO_CLEANUP=()
function cleanup {
  rm -rf "${TMP_FILES_TO_CLEANUP[@]}"
}
trap cleanup 0

function download_scss {
    local url="$1"
    local base_url="$2"
    local output_dir="$3"
    local visited_file="$4"

    # Check if this URL has already been visited
    if grep -q "^$url$" "$visited_file"; then
        echo "Skipping already visited: $url"
        return
    fi

    echo "Fetching: $url"
    echo "$url" >> "$visited_file"

    # Calculate the relative path from the base URL
    local relative_path=$(echo "$url" | sed -E "s|^$base_url||")
    local file_path="$output_dir/$relative_path"
    local file_dir=$(dirname "$file_path")

    # Ensure the directory structure exists
    mkdir -p "$file_dir"

    # Attempt to download the file and check for 200 OK response
    http_status=$(curl -s -w "%{http_code}" -o "$file_path" "$url")
    if [[ "$http_status" -ne 200 ]]; then
        # If the file is not found, try the `_` prefixed version
        rm -f "$file_path"
        local url_dir=$(dirname "$url")
        local url_file=$(basename "$url")
        local prefixed_url="$url_dir/_$url_file"
        local prefixed_relative_path=$(dirname "$relative_path")/_$(basename "$relative_path")
        local prefixed_file_path="$output_dir/$prefixed_relative_path"

        echo "File not found at $url (HTTP $http_status), trying $prefixed_url"
        http_status=$(curl -s -w "%{http_code}" -o "$prefixed_file_path" "$prefixed_url")
        if [[ "$http_status" -ne 200 ]]; then
            rm -f "$prefixed_file_path"
            echo "Failed to fetch both $url and $prefixed_url (HTTP $http_status)"
            exit 1
        fi
        file_path="$prefixed_file_path"
    fi

    echo "Saved: $file_path"

    # Parse @import and @use statements
    local imports=$(grep -oE '@(import|use) ["'\'']([^"'\'']+)["'\'']' "$file_path" | sed -E 's/@(import|use) ["'\'']([^"'\'']+)["'\'']/\2/')

    for import_path in $imports; do
        local import_url

        if [[ "$import_path" =~ ^http ]]; then
            import_url="$import_path"
        else
            # Handle relative imports
            local base_dir=$(dirname "$url")
            import_url="$base_dir/$import_path"
        fi

        # Ensure .scss extension if missing
        if [[ ! "$import_url" =~ \.scss$ ]]; then
            import_url="$import_url.scss"
        fi

        download_scss "$import_url" "$base_url" "$output_dir" "$visited_file"
    done
}

# Main script
if [[ -z "$1" ]]; then
    echo "Usage: $0 <URL_TO_SCSS_FILE> [OUTPUT_DIR]"
    exit 1
fi

URL="$1"
OUTPUT_DIR="${2:-./scss_files}"
BASE_URL=$(echo "$URL" | sed -E 's|^(https?://[^/]+)/.*$|\1|')
VISITED_FILE=$(mktemp --suffix=scss-visited-urls)

TMP_FILES_TO_CLEANUP+=( "$VISITED_FILE" )

# Clear visited file
>| "$VISITED_FILE"

download_scss "$URL" "$BASE_URL" "$OUTPUT_DIR" "$VISITED_FILE"
