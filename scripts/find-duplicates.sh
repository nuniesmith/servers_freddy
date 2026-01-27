#!/bin/bash
#
# Duplicate File Finder for FREDDY
# Scans PhotoPrism, Nextcloud, and backup directories for duplicate files
# Uses file size + MD5 checksums for accurate duplicate detection
#
# Usage: ./find-duplicates.sh [scan|report|cleanup]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Scan directories
PHOTOPRISM_DIR="/mnt/photoprism"
NEXTCLOUD_DATA="/mnt/nextcloud/data"
BACKUP_DIR="/mnt/backup/freddy"

# Output files
REPORT_DIR="$PROJECT_DIR/duplicate-reports"
SCAN_FILE="$REPORT_DIR/file-hashes.txt"
DUPLICATES_FILE="$REPORT_DIR/duplicates-$(date +%Y%m%d_%H%M%S).txt"
SUMMARY_FILE="$REPORT_DIR/summary-$(date +%Y%m%d_%H%M%S).txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_dependencies() {
    if ! command -v md5sum &> /dev/null; then
        error "md5sum not found. Please install coreutils."
        exit 1
    fi
}

# ============================================================================
# Scan for duplicates
# ============================================================================

scan_files() {
    log "Starting duplicate file scan..."
    
    mkdir -p "$REPORT_DIR"
    
    # Clear previous scan file
    > "$SCAN_FILE"
    
    local total_scanned=0
    local start_time=$(date +%s)
    
    # Scan PhotoPrism
    if [[ -d "$PHOTOPRISM_DIR" ]]; then
        info "Scanning PhotoPrism directory: $PHOTOPRISM_DIR"
        while IFS= read -r -d '' file; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            if [[ $size -gt 0 ]]; then
                local hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
                echo "$hash|$size|$file|photoprism" >> "$SCAN_FILE"
                ((total_scanned++))
                if ((total_scanned % 100 == 0)); then
                    echo -ne "\rScanned: $total_scanned files"
                fi
            fi
        done < <(find "$PHOTOPRISM_DIR" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
            -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" -o \
            -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o \
            -iname "*.mkv" -o -iname "*.heic" -o -iname "*.raw" \
        \) -print0 2>/dev/null)
        echo ""
    else
        warn "PhotoPrism directory not found: $PHOTOPRISM_DIR"
    fi
    
    # Scan Nextcloud
    if [[ -d "$NEXTCLOUD_DATA" ]]; then
        info "Scanning Nextcloud data directory: $NEXTCLOUD_DATA"
        while IFS= read -r -d '' file; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            if [[ $size -gt 0 ]]; then
                local hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
                echo "$hash|$size|$file|nextcloud" >> "$SCAN_FILE"
                ((total_scanned++))
                if ((total_scanned % 100 == 0)); then
                    echo -ne "\rScanned: $total_scanned files"
                fi
            fi
        done < <(find "$NEXTCLOUD_DATA" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
            -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" -o \
            -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o \
            -iname "*.mkv" -o -iname "*.heic" -o -iname "*.raw" -o \
            -iname "*.pdf" -o -iname "*.doc" -o -iname "*.docx" -o \
            -iname "*.xls" -o -iname "*.xlsx" -o -iname "*.zip" -o \
            -iname "*.tar" -o -iname "*.gz" \
        \) -print0 2>/dev/null)
        echo ""
    else
        warn "Nextcloud directory not found: $NEXTCLOUD_DATA"
    fi
    
    # Scan backups (exclude database dumps and tar archives)
    if [[ -d "$BACKUP_DIR" ]]; then
        info "Scanning backup directory: $BACKUP_DIR"
        while IFS= read -r -d '' file; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            if [[ $size -gt 0 ]]; then
                local hash=$(md5sum "$file" 2>/dev/null | awk '{print $1}')
                echo "$hash|$size|$file|backup" >> "$SCAN_FILE"
                ((total_scanned++))
                if ((total_scanned % 100 == 0)); then
                    echo -ne "\rScanned: $total_scanned files"
                fi
            fi
        done < <(find "$BACKUP_DIR" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
            -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" -o \
            -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o \
            -iname "*.mkv" -o -iname "*.heic" -o -iname "*.raw" \
        \) ! -name "*.tar.gz" ! -name "*.sql.gz" -print0 2>/dev/null)
        echo ""
    else
        warn "Backup directory not found: $BACKUP_DIR"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "✓ Scan complete: $total_scanned files scanned in ${duration}s"
    info "Results saved to: $SCAN_FILE"
}

# ============================================================================
# Generate duplicate report
# ============================================================================

generate_report() {
    log "Generating duplicate report..."
    
    if [[ ! -f "$SCAN_FILE" ]]; then
        error "Scan file not found. Run: ./find-duplicates.sh scan"
        exit 1
    fi
    
    # Find duplicates by hash
    sort "$SCAN_FILE" | awk -F'|' '
    {
        hash = $1
        size = $2
        path = $3
        source = $4
        
        if (hash in seen) {
            duplicates[hash] = duplicates[hash] "\n  " path " (" source ")"
            dup_count[hash]++
            total_size[hash] += size
        } else {
            seen[hash] = path " (" source ")"
            duplicates[hash] = ""
            dup_count[hash] = 1
            total_size[hash] = size
        }
    }
    END {
        total_duplicates = 0
        total_waste = 0
        
        for (hash in dup_count) {
            if (dup_count[hash] > 1) {
                total_duplicates++
                wasted = total_size[hash] * (dup_count[hash] - 1)
                total_waste += wasted
                
                print "==================================="
                print "Hash: " hash
                print "Size: " total_size[hash] / (1024 * 1024) " MB"
                print "Copies: " dup_count[hash]
                print "Wasted: " wasted / (1024 * 1024) " MB"
                print "Files:"
                print "  " seen[hash]
                print duplicates[hash]
                print ""
            }
        }
        
        print "==================================="
        print "SUMMARY"
        print "==================================="
        print "Total duplicate groups: " total_duplicates
        print "Total wasted space: " total_waste / (1024 * 1024 * 1024) " GB"
    }' > "$DUPLICATES_FILE"
    
    # Extract summary
    tail -5 "$DUPLICATES_FILE" > "$SUMMARY_FILE"
    
    log "✓ Report generated"
    echo ""
    info "Full report: $DUPLICATES_FILE"
    info "Summary:"
    cat "$SUMMARY_FILE"
}

# ============================================================================
# Interactive cleanup
# ============================================================================

cleanup_duplicates() {
    log "Starting interactive duplicate cleanup..."
    
    if [[ ! -f "$DUPLICATES_FILE" ]]; then
        error "Duplicate report not found. Run: ./find-duplicates.sh report"
        exit 1
    fi
    
    warn "⚠️  Interactive cleanup mode"
    echo ""
    info "This will go through each duplicate group and let you choose which files to delete."
    info "Priority rules:"
    echo "  1. Keep original files (PhotoPrism originals)"
    echo "  2. Delete duplicates in backup directories"
    echo "  3. Delete duplicates in Nextcloud if already in PhotoPrism"
    echo ""
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cancelled"
        exit 0
    fi
    
    local deleted_count=0
    local space_freed=0
    
    # Parse duplicates file and prompt for each group
    local current_hash=""
    local files_in_group=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^Hash:\ (.+)$ ]]; then
            # New duplicate group
            if [[ ${#files_in_group[@]} -gt 0 ]]; then
                process_duplicate_group "${files_in_group[@]}"
                files_in_group=()
            fi
            current_hash="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^\ \ (.+)\ \((.+)\)$ ]]; then
            # File in group
            files_in_group+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]}")
        fi
    done < "$DUPLICATES_FILE"
    
    # Process last group
    if [[ ${#files_in_group[@]} -gt 0 ]]; then
        process_duplicate_group "${files_in_group[@]}"
    fi
    
    log "✓ Cleanup complete"
    info "Files deleted: $deleted_count"
    info "Space freed: $((space_freed / 1024 / 1024)) MB"
}

process_duplicate_group() {
    local files=("$@")
    
    echo ""
    echo "==================================="
    info "Duplicate group found (${#files[@]} copies):"
    
    local i=1
    for file_info in "${files[@]}"; do
        IFS=':' read -r path source <<< "$file_info"
        echo "  [$i] $path ($source)"
        ((i++))
    done
    
    echo ""
    echo "Options:"
    echo "  [1-${#files[@]}] Delete specific file"
    echo "  [a] Auto-delete (keep PhotoPrism originals, delete backups/nextcloud)"
    echo "  [s] Skip this group"
    echo "  [q] Quit cleanup"
    
    read -p "Choice: " -r choice
    
    case $choice in
        [1-9]|[1-9][0-9])
            if [[ $choice -le ${#files[@]} ]]; then
                local file_info="${files[$((choice-1))]}"
                IFS=':' read -r path source <<< "$file_info"
                if [[ -f "$path" ]]; then
                    local size=$(stat -c%s "$path")
                    rm -f "$path"
                    log "✓ Deleted: $path"
                    ((deleted_count++))
                    ((space_freed+=size))
                else
                    warn "File not found: $path"
                fi
            else
                warn "Invalid choice"
            fi
            ;;
        a|A)
            auto_delete_duplicates "${files[@]}"
            ;;
        s|S)
            info "Skipped"
            ;;
        q|Q)
            info "Quit cleanup"
            exit 0
            ;;
        *)
            warn "Invalid choice"
            ;;
    esac
}

auto_delete_duplicates() {
    local files=("$@")
    
    # Keep PhotoPrism originals, delete others
    local has_photoprism=false
    local files_to_delete=()
    
    for file_info in "${files[@]}"; do
        IFS=':' read -r path source <<< "$file_info"
        
        if [[ "$source" == "photoprism" && "$path" =~ /originals/ ]]; then
            has_photoprism=true
        else
            files_to_delete+=("$path")
        fi
    done
    
    # If no PhotoPrism original, keep first file
    if [[ $has_photoprism == false ]]; then
        files_to_delete=("${files_to_delete[@]:1}")
    fi
    
    # Delete files
    for path in "${files_to_delete[@]}"; do
        if [[ -f "$path" ]]; then
            local size=$(stat -c%s "$path")
            rm -f "$path"
            log "✓ Auto-deleted: $path"
            ((deleted_count++))
            ((space_freed+=size))
        fi
    done
}

# ============================================================================
# Dry run mode
# ============================================================================

dry_run_cleanup() {
    log "Starting dry run (no files will be deleted)..."
    
    if [[ ! -f "$DUPLICATES_FILE" ]]; then
        error "Duplicate report not found. Run: ./find-duplicates.sh report"
        exit 1
    fi
    
    local would_delete=0
    local would_free=0
    
    # Parse duplicates and simulate auto-delete
    local current_hash=""
    local files_in_group=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^Hash:\ (.+)$ ]]; then
            if [[ ${#files_in_group[@]} -gt 0 ]]; then
                simulate_delete_group "${files_in_group[@]}"
                files_in_group=()
            fi
        elif [[ $line =~ ^\ \ (.+)\ \((.+)\)$ ]]; then
            files_in_group+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]}")
        fi
    done < "$DUPLICATES_FILE"
    
    if [[ ${#files_in_group[@]} -gt 0 ]]; then
        simulate_delete_group "${files_in_group[@]}"
    fi
    
    log "✓ Dry run complete"
    info "Would delete: $would_delete files"
    info "Would free: $((would_free / 1024 / 1024)) MB"
}

simulate_delete_group() {
    local files=("$@")
    
    local has_photoprism=false
    
    for file_info in "${files[@]}"; do
        IFS=':' read -r path source <<< "$file_info"
        
        if [[ "$source" == "photoprism" && "$path" =~ /originals/ ]]; then
            has_photoprism=true
            info "Would keep: $path (PhotoPrism original)"
        else
            if [[ $has_photoprism == true || ${#files[@]} -gt 1 ]]; then
                local size=$(stat -c%s "$path" 2>/dev/null || echo 0)
                warn "Would delete: $path"
                ((would_delete++))
                ((would_free+=size))
            fi
        fi
    done
}

usage() {
    cat << EOF
Duplicate File Finder for FREDDY

Usage: $0 [command]

Commands:
    scan        Scan directories for duplicate files
    report      Generate duplicate report from scan results
    cleanup     Interactive cleanup (delete duplicates)
    dry-run     Show what would be deleted without actually deleting
    help        Show this help message

Workflow:
    1. Run scan to generate file hashes
    2. Run report to identify duplicates
    3. Run dry-run to preview deletions
    4. Run cleanup for interactive deletion

Examples:
    # Full workflow
    $0 scan
    $0 report
    $0 dry-run
    $0 cleanup
    
    # Quick scan and report
    $0 scan && $0 report

Notes:
    - Scans PhotoPrism, Nextcloud, and backup directories
    - Uses MD5 checksums for accurate duplicate detection
    - Prioritizes keeping PhotoPrism originals
    - Interactive cleanup mode for safety
    - Reports saved to: $REPORT_DIR

EOF
}

# ============================================================================
# Main
# ============================================================================

check_dependencies

case "${1:-help}" in
    scan)
        scan_files
        ;;
    report)
        generate_report
        ;;
    cleanup)
        cleanup_duplicates
        ;;
    dry-run)
        dry_run_cleanup
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1"
        echo ""
        usage
        exit 1
        ;;
esac
