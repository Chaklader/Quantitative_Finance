#!/bin/bash

# Enhanced MIT 18.02SC PDF Downloader with Multiple Strategies
# This script implements several fallback mechanisms to handle MIT OCW's download restrictions

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOWNLOAD_DIR="$SCRIPT_DIR/MIT_Calculus_PDFs"
readonly LOG_FILE="$DOWNLOAD_DIR/download.log"
readonly USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Create directory structure
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Enhanced logging with timestamps
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Function to extract direct PDF URL from page HTML
extract_pdf_url() {
    local page_url="$1"
    local temp_file=$(mktemp)
    
    # Download the resource page and extract the actual PDF URL
    if curl --silent --fail \
            --user-agent "$USER_AGENT" \
            --location \
            --max-redirs 10 \
            --connect-timeout 30 \
            --output "$temp_file" \
            "$page_url"; then
        
        # Look for PDF download links in the HTML
        # MIT OCW typically embeds the actual PDF URL in the page source
        local pdf_url=$(grep -oE 'https://[^"]*\.pdf' "$temp_file" | head -n1)
        
        if [[ -z "$pdf_url" ]]; then
            # Alternative pattern - look for file download URLs
            pdf_url=$(grep -oE 'href="[^"]*\.pdf[^"]*"' "$temp_file" | sed 's/href="//;s/"//' | head -n1)
            
            # If it's a relative URL, make it absolute
            if [[ "$pdf_url" =~ ^/ ]]; then
                pdf_url="https://ocw.mit.edu$pdf_url"
            fi
        fi
        
        rm -f "$temp_file"
        echo "$pdf_url"
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Enhanced download function with multiple strategies
download_pdf_advanced() {
    local session_name="$1"
    local resource_url="$2"
    local output_filename="$3"
    
    log "Processing: $session_name"
    log "Resource URL: $resource_url"
    
    # Strategy 1: Extract direct PDF URL from the resource page
    log "Strategy 1: Extracting direct PDF URL from resource page"
    local direct_pdf_url=$(extract_pdf_url "$resource_url")
    
    if [[ -n "$direct_pdf_url" ]]; then
        log "Found direct PDF URL: $direct_pdf_url"
        
        if curl --fail --silent --show-error \
                --location \
                --user-agent "$USER_AGENT" \
                --connect-timeout 30 \
                --max-time 300 \
                --output "$output_filename" \
                "$direct_pdf_url"; then
            
            # Verify it's a valid PDF
            if file "$output_filename" | grep -q "PDF"; then
                local file_size=$(stat -f%z "$output_filename" 2>/dev/null || stat -c%s "$output_filename" 2>/dev/null)
                log "✓ Successfully downloaded: $output_filename (${file_size} bytes)"
                return 0
            else
                log "⚠ Downloaded file is not a valid PDF"
                rm -f "$output_filename"
            fi
        fi
    fi
    
    # Strategy 2: Try the original download URL with session cookies
    log "Strategy 2: Attempting download with session management"
    local cookie_jar=$(mktemp)
    
    # First, visit the main page to establish a session
    curl --silent --fail \
         --user-agent "$USER_AGENT" \
         --cookie-jar "$cookie_jar" \
         --location \
         "$resource_url" > /dev/null
    
    # Then try the download with the established session
    local download_url="${resource_url}/download"
    if curl --fail --silent --show-error \
            --location \
            --user-agent "$USER_AGENT" \
            --cookie "$cookie_jar" \
            --referer "$resource_url" \
            --connect-timeout 30 \
            --max-time 300 \
            --max-redirs 5 \
            --output "$output_filename" \
            "$download_url"; then
        
        if file "$output_filename" | grep -q "PDF"; then
            local file_size=$(stat -f%z "$output_filename" 2>/dev/null || stat -c%s "$output_filename" 2>/dev/null)
            log "✓ Successfully downloaded via session: $output_filename (${file_size} bytes)"
            rm -f "$cookie_jar"
            return 0
        else
            rm -f "$output_filename"
        fi
    fi
    
    rm -f "$cookie_jar"
    
    # Strategy 3: Manual URL construction based on MIT OCW patterns
    log "Strategy 3: Attempting manual URL construction"
    local resource_id=$(basename "$resource_url")
    local manual_pdf_url="https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/${resource_id}/${resource_id}.pdf"
    
    if curl --fail --silent --show-error \
            --location \
            --user-agent "$USER_AGENT" \
            --connect-timeout 30 \
            --max-time 300 \
            --output "$output_filename" \
            "$manual_pdf_url"; then
        
        if file "$output_filename" | grep -q "PDF"; then
            local file_size=$(stat -f%z "$output_filename" 2>/dev/null || stat -c%s "$output_filename" 2>/dev/null)
            log "✓ Successfully downloaded via manual URL: $output_filename (${file_size} bytes)"
            return 0
        else
            rm -f "$output_filename"
        fi
    fi
    
    log "✗ All download strategies failed for: $session_name"
    return 1
}

# Updated session data with resource page URLs instead of download URLs
declare -a MIT_SESSIONS=(
    "Session 1: Vectors|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_0|S_1.pdf"
    "Session 6: Volumes and Determinants|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_mnotes_d2|S_6.pdf"
    "Session 13: Linear Systems and Planes|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_7|S_13.pdf"
    "Session 14: Solutions to Square Systems|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_mnotes_m3|S_14.pdf"
    "Session 18: Point Cusp on Cycloid|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_10|S_18.pdf"
    "Session 20: Velocity and Arc Length|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_12|S_20.pdf"
    "Session 21: Kepler's Second Law|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_mnotes_k|S_21.pdf"
    "Session 24: Functions Two Variables A|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_13|S_24a.pdf"
    "Session 24: Functions Two Variables B|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_notes_14|S_24b.pdf"
    "Session 26: Partial Derivatives|https://ocw.mit.edu/courses/18-02sc-multivariable-calculus-fall-2010/resources/mit18_02sc_mnotes_ta1|S_26.pdf"
)

# Main execution with comprehensive error handling
main() {
    log "=== Enhanced MIT 18.02SC PDF Downloader ==="
    log "Download directory: $DOWNLOAD_DIR"
    log "Total sessions: ${#MIT_SESSIONS[@]}"
    
    # Check required tools
    for tool in curl file; do
        if ! command -v "$tool" &> /dev/null; then
            log "Error: Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    local success_count=0
    local failure_count=0
    
    for session_data in "${MIT_SESSIONS[@]}"; do
        IFS='|' read -r name url filename <<< "$session_data"
        
        if download_pdf_advanced "$name" "$url" "$filename"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
        
        # Respectful delay
        sleep 3
    done
    
    log "=== Final Summary ==="
    log "✓ Successful downloads: $success_count"
    log "✗ Failed downloads: $failure_count"
    log "📁 Files saved in: $DOWNLOAD_DIR"
    
    if [[ $failure_count -gt 0 ]]; then
        log ""
        log "For failed downloads, you may need to:"
        log "1. Visit the URLs manually in a browser"
        log "2. Use browser developer tools to find direct PDF links"
        log "3. Check if MIT OCW has updated their URL structure"
    fi
}

# Execute with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi