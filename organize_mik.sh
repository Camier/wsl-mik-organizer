#!/bin/bash
# WSL Directory Organization v2.1 - Bulk Optimized
# Usage: ./organize_mik.sh [--dry-run] [--test]

set -euo pipefail

# Configuration for bulk sorting
declare -A CATEGORY_CONFIG=(
    [MIN_FILES]=3
    [SIMILARITY_THRESHOLD]=0.7
    [MAX_SUBCATEGORIES]=5
)

# Main bulk categories
BULK_CATEGORIES=(
    "THESIS"
    "CLAUDE-CODE"
    "DALLE2"
    "AI-TOOLS"
    "MEDIA-WORK"
    "DEV-TOOLS"
    "PROJECTS"
    "RESOURCES"
    "_UNSORTED"
)

# Extended patterns
declare -A EXTENDED_PATTERNS=(
    [THESIS]="(thesis|dissertation|phd|master|mneru|academic|research|paper|journal|citation|bibliography|latex|.+\\.bib$|.+\\.tex$)"
    [CLAUDE-CODE]="(claude|anthropic|mcp|memento|knowledge.?graph|instruction|prompt|preference|.+\\.mcp$|mcp-.+|claude.?desktop)"
    [DALLE2]="(dall-?e.*(cli|cmd|command|app|application|gui|android|mobile|apk|api|client|endpoint)|dalle?2|openai.*dall)"
    [AI-TOOLS]="(midjourney|mj-|stable.?diffusion|sd-webui|comfy.?ui|automatic1111|controlnet|lora|checkpoint|safetensors|ckpt|ai.?(art|image|gen)(?!.*dall-?e)|prompt.?(eng|lib)(?!.*dall-?e))"
    [MEDIA-WORK]="(ffmpeg|concat|filter|encode|transcode|video|audio|media|premiere|resolve|.+\\.(mp4|mkv|avi|mov|mp3|wav|flac|aac|opus)$)"
    [DEV-TOOLS]="(searx|docker|compose|nginx|apache|server|api|webhook|cron|systemd|.+\\.service$|.+\\.(sh|py|js|go|rs)$)"
    [PROJECTS]="(project|app|demo|test|experiment|prototype|poc|mvp|alpha|beta|v[0-9]+|.+[-_]v[0-9]+)"
    [RESOURCES]="(.+\\.(conf|config|cfg|ini|json|yaml|yml|md|txt|csv|sql|env|properties)$|readme|license|todo|notes|docs?/)"
)

# Global dry run flag
DRY_RUN=${DRY_RUN:-false}

# Validation function
validate_environment() {
    echo "🔍 Starting pre-flight checks..."
    
    [[ ! -d "$HOME/mik" ]] && { echo "❌ ERROR: ~/mik directory not found"; return 1; }
    [[ ! -w "$HOME/mik" ]] && { echo "❌ ERROR: No write permission on ~/mik"; return 1; }
    
    local file_count=$(find ~/mik -maxdepth 1 -type f 2>/dev/null | wc -l)
    echo "📊 Found $file_count files to organize"
    
    if [[ $file_count -eq 0 ]]; then
        echo "⚠️  No files found in ~/mik directory"
        return 1
    fi
    
    local available=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    [[ $available -lt 5 ]] && echo "⚠️  WARNING: Low disk space (${available}GB available)"
    
    mkdir -p ~/mik_reorg/{logs,backup,temp,analysis,bulk_groups}
    
    echo "===== Reorganization started at $(date) =====" > ~/mik_reorg/logs/transaction.log
    echo "✅ Pre-flight checks passed"
}

# Backup function
create_backup() {
    [[ "$DRY_RUN" == "true" ]] && { echo "📦 [DRY RUN] Would create backup"; return 0; }
    
    local backup_file="$HOME/mik_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    echo "📦 Creating backup: $backup_file"
    
    tar -czf "$backup_file" -C "$HOME" mik/ 2>/dev/null
    
    if tar -tzf "$backup_file" > /dev/null 2>&1; then
        echo "✅ Backup verified: $backup_file"
        echo "$backup_file" > ~/mik_reorg/logs/latest_backup.txt
    else
        echo "❌ Backup verification failed!"
        return 1
    fi
}

# Analyze file with bulk awareness
analyze_file_bulk() {
    local file="$1"
    local basename=$(basename "$file")
    local stem="${basename%.*}"
    
    declare -A scores=(
        [THESIS]=0
        [CLAUDE-CODE]=0
        [DALLE2]=0
        [AI-TOOLS]=0
        [MEDIA-WORK]=0
        [DEV-TOOLS]=0
        [PROJECTS]=0
        [RESOURCES]=0
    )
    
    # Check each pattern
    for category in "${!EXTENDED_PATTERNS[@]}"; do
        if [[ "$basename" =~ ${EXTENDED_PATTERNS[$category]} ]]; then
            ((scores[$category]+=5))
        fi
    done
    
    # Special boost for DALLE2 to ensure separation
    if [[ "$basename" =~ (dall-?e) ]]; then
        ((scores[DALLE2]+=5))
        scores[AI-TOOLS]=0  # Ensure it doesn't go to AI-TOOLS
    fi
    
    # Find highest scoring category
    local max_score=0
    local best_category="_UNSORTED"
    
    for cat in "${!scores[@]}"; do
        if [[ ${scores[$cat]} -gt $max_score ]]; then
            max_score=${scores[$cat]}
            best_category=$cat
        fi
    done
    
    echo "$best_category:$max_score"
}

# Safe move function
safe_move() {
    local src="$1"
    local dst_category="$2"
    local dst_dir="$HOME/mik/$dst_category"
    local basename=$(basename "$src")
    local dst="$dst_dir/$basename"
    
    [[ "$DRY_RUN" == "true" ]] && { echo "   [DRY RUN] Would move: $basename → $dst_category/"; return 0; }
    
    # Handle existing file
    if [[ -e "$dst" ]]; then
        local suffix=1
        while [[ -e "${dst%.*}_$suffix.${dst##*.}" ]]; do
            ((suffix++))
        done
        dst="${dst%.*}_$suffix.${dst##*.}"
    fi
    
    if mv -n "$src" "$dst" 2>/dev/null; then
        echo "   ✅ Moved: $basename → $dst_category/"
        return 0
    else
        echo "   ❌ Failed to move: $basename"
        return 1
    fi
}

# Preview changes
preview_bulk_changes() {
    echo "📊 Bulk Organization Summary:"
    
    declare -A category_counts
    while IFS=':' read -r file classification _; do
        local category="${classification%%:*}"
        ((category_counts[$category]++))
    done < ~/mik_reorg/analysis/classifications.txt
    
    printf "   %-15s | %s\n" "Category" "Files"
    printf "   %s\n" "--------------------------------"
    
    for cat in "${BULK_CATEGORIES[@]}"; do
        if [[ -n "${category_counts[$cat]:-}" ]]; then
            printf "   %-15s | %3d files" "$cat" "${category_counts[$cat]}"
            
            case "$cat" in
                THESIS)      echo " (Academic work)" ;;
                CLAUDE-CODE) echo " (Claude/MCP tools)" ;;
                DALLE2)      echo " (DALL-E CLI/App/Android)" ;;
                AI-TOOLS)    echo " (Other AI: MJ, SD, etc.)" ;;
                MEDIA-WORK)  echo " (Video/Audio processing)" ;;
                DEV-TOOLS)   echo " (Dev utilities)" ;;
                PROJECTS)    echo " (General projects)" ;;
                RESOURCES)   echo " (Configs/Docs)" ;;
                _UNSORTED)   echo " (Uncategorized)" ;;
            esac
        fi
    done
}

# Execute moves
execute_bulk_moves() {
    while IFS=':' read -r file classification _; do
        local category="${classification%%:*}"
        safe_move "$file" "$category"
    done < ~/mik_reorg/analysis/classifications.txt
}

# Main reorganization function
reorganize_mik_bulk() {
    validate_environment || return 1
    create_backup || return 1
    
    echo -e "\n📊 Phase 1: Analyzing directory structure..."
    
    # Create directories
    for cat in "${BULK_CATEGORIES[@]}"; do
        mkdir -p "$HOME/mik/$cat"
    done
    
    # Analyze files
    > ~/mik_reorg/analysis/classifications.txt
    local total_files=$(find ~/mik -maxdepth 1 -type f 2>/dev/null | wc -l)
    local processed=0
    
    find ~/mik -maxdepth 1 -type f 2>/dev/null | while read -r file; do
        ((processed++))
        echo -ne "\r   Analyzing: $processed/$total_files files..."
        
        local classification=$(analyze_file_bulk "$file")
        echo "$file:$classification" >> ~/mik_reorg/analysis/classifications.txt
    done
    
    echo -e "\n   ✅ Analysis complete"
    
    echo -e "\n📋 Preview of changes:"
    preview_bulk_changes
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "\n🔍 DRY RUN COMPLETE - No files were moved"
        return 0
    fi
    
    echo ""
    read -p "Proceed with reorganization? [y/N]: " confirm
    [[ "$confirm" != "y" ]] && { echo "❌ Cancelled"; return 1; }
    
    echo -e "\n🚀 Executing reorganization..."
    execute_bulk_moves
    
    echo -e "\n✅ Reorganization complete!"
}

# Test function
test_bulk_logic() {
    echo "🧪 Testing classification logic..."
    
    local test_files=(
        "thesis_chapter1.tex"
        "dalle-cli-v2.py"
        "claude_desktop_config.json"
        "midjourney_bot.py"
        "video_concat.sh"
        "searxng-docker-compose.yml"
        "my_project_v2.zip"
        "config.json"
    )
    
    for file in "${test_files[@]}"; do
        local result=$(analyze_file_bulk "/tmp/$file")
        printf "%-30s → %s\n" "$file" "$result"
    done
}

# Help function
show_help() {
    cat << EOF
WSL Directory Organization v2.1 - Bulk Optimized

Usage: $0 [OPTIONS]

Options:
    --dry-run    Preview changes without executing
    --test       Run classification tests
    --help       Show this help

Categories:
    - THESIS: Academic work
    - CLAUDE-CODE: Claude/MCP specific  
    - DALLE2: DALL-E ecosystem (CLI/App/Android)
    - AI-TOOLS: Other AI tools (MJ, SD, etc.)
    - MEDIA-WORK: Video/audio processing
    - DEV-TOOLS: Development utilities
    - PROJECTS: General projects
    - RESOURCES: Configs, docs, data
    - _UNSORTED: Uncategorized files

EOF
}

# Main entry point
main() {
    case "${1:-}" in
        --dry-run)
            echo "🔍 DRY RUN MODE - No files will be moved"
            DRY_RUN=true
            reorganize_mik_bulk ;;
        --test)
            test_bulk_logic ;;
        --help)
            show_help ;;
        *)
            reorganize_mik_bulk ;;
    esac
}

# Run main
main "$@"
