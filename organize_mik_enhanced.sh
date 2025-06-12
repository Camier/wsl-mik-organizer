#!/bin/bash
# WSL Directory Organization v3.0 - Multi-Worker Enhanced
# High-performance parallel file organization with advanced features
# Usage: ./organize_mik_enhanced.sh [--dry-run] [--test] [--workers N] [--dashboard] [--resume]

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Worker Configuration
MAX_WORKERS=${MAX_WORKERS:-$(nproc)}  # Use all CPU cores by default
BATCH_SIZE=${BATCH_SIZE:-100}         # Files per batch
WORKER_TIMEOUT=${WORKER_TIMEOUT:-300} # 5 minutes per worker
PROGRESS_UPDATE_INTERVAL=50           # Update progress every N files
CHECKPOINT_INTERVAL=100               # Save state every N files

# Performance Optimization
declare -A PATTERN_CACHE=()
declare -A SIZE_CACHE=()
CACHE_HIT_RATIO=0

# Worker Management
declare -a WORKER_PIDS=()
declare -a WORKER_QUEUES=()
declare -a WORKER_STATS=()
declare -a WORKER_LOADS=()

WORKER_DIR="/tmp/organizer_workers_$$"
MAIN_QUEUE="$WORKER_DIR/main_queue"
PROGRESS_FILE="$WORKER_DIR/progress"
WORKER_LOG_DIR="$WORKER_DIR/logs"
STATE_FILE="$WORKER_DIR/organizer_state.json"

# Main bulk categories with SEARCH addition
BULK_CATEGORIES=(
    "THESIS"
    "CLAUDE-CODE"
    "DALLE2"
    "AI-TOOLS"
    "SEARCH"
    "MEDIA-WORK"
    "DEV-TOOLS"
    "PROJECTS"
    "RESOURCES"
    "_UNSORTED"
)

# Enhanced patterns from analysis
declare -A EXTENDED_PATTERNS=(
    [THESIS]="(thesis|dissertation|phd|master|academic|research|paper|journal|publication|citation|bibliography|literature.?review|methodology|abstract|conclusion|hypothesis|experiment|analysis|study|conference|proceedings|peer.?review|manuscript|draft|revision|proposal|defense|committee|advisor|supervisor|chapter.\d+|appendix|references|figure.\d+|table.\d+|equation|theorem|proof|lemma|corollary|definition|data.?set|statistical|quantitative|qualitative|survey|interview|case.?study|field.?work|lab.?report)"
    
    [CLAUDE-CODE]="(claude|anthropic|mcp|message.?control.?protocol|knowledge.?graph|prompt|llm|langchain|llamaindex|vector.?db|embedding|rag|retrieval.?augmented|semantic.?search|transformer|attention|fine.?tun|instruction.?tun|chat.?completion|conversation|assistant|agent|tool.?use|function.?call|system.?prompt|few.?shot|zero.?shot|chain.?of.?thought|cot|reasoning|artifacts|mcp.?server|mcp.?client|bedrock|vertex|api.?key|model.?config|memento)"
    
    [DALLE2]="(dall-?e.*(cli|cmd|app|api|gui|tool|helper|manager|batch|bulk|download|upload|android|mobile|apk)|openai.*dall|image.?generat|text.?to.?image|img2img|inpaint|outpaint|variation|edit.?image|mask|prompt.?engineer|negative.?prompt|seed|cfg.?scale|steps|sampler|checkpoint|lora|textual.?inversion|hypernetwork|aesthetic|style.?transfer|controlnet.*openai|clip.?interrogat|vision.?api)"
    
    [AI-TOOLS]="(midjourney|stable.?diffusion|controlnet|comfyui|automatic1111|a1111|webui|diffusers|hugging.?face|hf|civitai|runway|pika|sora|eleven.?labs|whisper|bark|tortoise|rvc|so-vits|musicgen|audiogen|florence|sam|segment.?anything|yolo|detectron|grounding.?dino|blip|coca|flamingo|llava|gemini|bard|copilot|cursor|codeium|tabnine|kite|sourcegraph|perplexity|you\.com|phind|chatgpt|gpt-?[0-9]|turbo|davinci|curie|babbage|ada)"
    
    [SEARCH]="(searx|searxng|metasearch|search.?engine|privacy.?search|duckduckgo|ddg|startpage|qwant|brave.?search|private.?search|anonymous.?search|search.?proxy|search.?api|search.?aggregat|search.?instance|search.?config|search.?plugin|search.?filter|search.?result|web.?scraper|scraping|crawl|spider|bot|indexer|elastic.?search|solr|lucene|meilisearch|typesense|algolia|whoosh|xapian|sphinx|manticore|opensearch|search.?ranking|search.?algorithm|pagerank|tf.?idf|bm25|vector.?search|similarity.?search|faceted.?search|full.?text|search.?ui|search.?frontend|search.?backend|query.?parser|search.?optimization|seo|search.?analytics|search.?metrics|click.?through|search.?quality|relevance|precision.?recall|search.?index|inverted.?index|search.?cluster|distributed.?search|federated.?search|unified.?search|search.?gateway|search.?middleware)"
    
    [MEDIA-WORK]="(ffmpeg|video|audio|media|encode|transcode|codec|h264|h265|hevc|av1|vp9|opus|aac|flac|mp[34]|mkv|webm|mov|avi|premiere|after.?effects|davinci|resolve|final.?cut|avid|nuke|blender|maya|3ds.?max|cinema.?4d|houdini|zbrush|substance|photoshop|illustrator|figma|sketch|xd|canva|gimp|inkscape|krita|procreate|\.psd|\.ai|\.eps|\.svg|\.raw|\.dng|\.exr|\.blend|\.c4d|\.ma|\.max|\.obj|\.fbx|\.gltf|\.usd|stream|broadcast|obs|wirecast|vmix|concat|filter)"
    
    [DEV-TOOLS]="(docker|nginx|api|webhook|\.sh|\.py|\.js|\.ts|\.jsx|\.tsx|\.go|\.rs|\.c|\.cpp|\.h|\.hpp|\.java|\.kt|\.swift|\.rb|\.php|\.lua|\.r|\.jl|\.scala|\.clj|makefile|cmake|gradle|maven|npm|yarn|pnpm|pip|cargo|gem|composer|\.env|\.git|\.vscode|\.idea|jetbrains|eclipse|vim|neovim|emacs|sublime|atom|bracket|lint|eslint|prettier|black|ruff|flake8|pylint|mypy|pytest|jest|mocha|vitest|cypress|playwright|selenium|postman|insomnia|swagger|openapi|graphql|rest|grpc|websocket|redis|postgres|mysql|mongodb|elasticsearch|kafka|rabbitmq|kubernetes|k8s|helm|terraform|ansible|vagrant|ci.?cd|jenkins|github.?action|gitlab.?ci|circle.?ci|travis|drone|argo|flux|compose|systemd|cron|server|apache)"
    
    [PROJECTS]="(project|demo|test|prototype|mvp|poc|proof.?of.?concept|experiment|sandbox|playground|workspace|repository|repo|codebase|application|app|service|microservice|monorepo|package|module|library|framework|starter|template|boilerplate|scaffold|skeleton|seed|example|sample|tutorial|workshop|hackathon|challenge|assignment|homework|exercise|practice|solution|implementation|build|release|v[0-9]+\.[0-9]+|alpha|beta|rc|stable|production|staging|development|feature|bugfix|hotfix|patch)"
    
    [RESOURCES]="(\.conf|\.json|\.yaml|\.yml|\.toml|\.ini|\.cfg|\.config|\.properties|\.xml|\.md|\.txt|\.rst|\.adoc|\.tex|readme|license|copyright|authors|contributors|changelog|history|todo|roadmap|contributing|code.?of.?conduct|security|codeowners|funding|issue.?template|pull.?request|\.gitignore|\.gitattributes|\.editorconfig|\.prettierrc|\.eslintrc|\.babelrc|\.dockerignore|\.npmignore|\.env\.example|requirements|dependencies|package\.json|package-lock|yarn\.lock|pnpm-lock|poetry\.lock|cargo\.lock|gemfile\.lock|composer\.lock|go\.sum|mix\.lock|pubspec\.lock|manifest|dockerfile|docker-compose|makefile|justfile|taskfile|procfile|netlify|vercel|railway|render|notes|docs?)"
)

# Global flags
DRY_RUN=${DRY_RUN:-false}
DASHBOARD_MODE=false
RESUME_MODE=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Logging with timestamps
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Error handling
error_exit() {
    echo "❌ ERROR: $*" >&2
    cleanup_workers
    exit 1
}

# Performance monitoring
monitor_memory_usage() {
    while true; do
        local mem_usage=$(ps -o pid,vsz,rss,comm -p $$ 2>/dev/null | tail -1)
        local rss=$(echo "$mem_usage" | awk '{print $3}')
        
        # Alert if memory usage exceeds 1GB
        if [[ $rss -gt 1048576 ]]; then
            log "Warning: High memory usage: ${rss}KB"
            clear_caches
        fi
        
        sleep 30
    done &
    echo $!  # Return monitor PID
}

clear_caches() {
    PATTERN_CACHE=()
    SIZE_CACHE=()
    log "Caches cleared due to high memory usage"
}

# ============================================================================
# ENHANCED FILE ANALYSIS
# ============================================================================

# Optimized category determination with caching
cached_pattern_match() {
    local filename="$1"
    local cache_key="${filename##*/}"  # Use basename as key
    
    if [[ -n "${PATTERN_CACHE[$cache_key]:-}" ]]; then
        echo "${PATTERN_CACHE[$cache_key]}"
        ((CACHE_HIT_RATIO++))
        return 0
    fi
    
    # Compute category
    local category
    category=$(determine_file_category_optimized "$filename")
    PATTERN_CACHE[$cache_key]="$category"
    echo "$category"
}

# Optimized category determination
determine_file_category_optimized() {
    local filename="$1"
    local lowercase_name="${filename,,}"  # Convert to lowercase once
    
    # Fast path: check file extension first
    case "$lowercase_name" in
        *.pdf|*.doc|*.docx|*.tex|*.bib) 
            [[ "$lowercase_name" =~ (thesis|dissertation|research|academic|paper|journal) ]] && echo "THESIS" && return ;;
        *.py|*.sh|*.js|*.ts|*.go|*.rs|*.c|*.cpp|*.java)
            [[ "$lowercase_name" =~ (searx|docker|nginx|api|server) ]] && echo "DEV-TOOLS" && return
            [[ "$lowercase_name" =~ (claude|mcp|anthropic) ]] && echo "CLAUDE-CODE" && return
            [[ "$lowercase_name" =~ (dalle?|openai) ]] && echo "DALLE2" && return
            echo "DEV-TOOLS" && return ;;
        *.mp4|*.mp3|*.avi|*.mkv|*.webm|*.flac|*.wav|*.mov|*.psd|*.ai)
            echo "MEDIA-WORK" && return ;;
        *.json|*.yaml|*.yml|*.conf|*.cfg|*.ini|*.md|*.txt)
            [[ "$lowercase_name" =~ (claude|mcp) ]] && echo "CLAUDE-CODE" && return
            [[ "$lowercase_name" =~ (searx|search) ]] && echo "SEARCH" && return
            echo "RESOURCES" && return ;;
        *.apk)
            [[ "$lowercase_name" =~ (dalle?) ]] && echo "DALLE2" && return
            echo "PROJECTS" && return ;;
    esac
    
    # Pattern matching with optimized regex
    for category in "${!EXTENDED_PATTERNS[@]}"; do
        if [[ "$lowercase_name" =~ ${EXTENDED_PATTERNS[$category]} ]]; then
            echo "$category"
            return
        fi
    done
    
    echo "_UNSORTED"
}

# ============================================================================
# WORKER SYSTEM
# ============================================================================

# Initialize worker system
init_workers() {
    mkdir -p "$WORKER_DIR" "$WORKER_LOG_DIR"
    echo "0" > "$PROGRESS_FILE"
    
    # Create named pipes for each worker
    for ((i=0; i<MAX_WORKERS; i++)); do
        local queue="$WORKER_DIR/queue_$i"
        mkfifo "$queue"
        WORKER_QUEUES+=("$queue")
        WORKER_STATS[$i]="0:0:0"  # processed:errors:avg_time
        WORKER_LOADS[$i]=0
    done
    
    log "Initialized $MAX_WORKERS workers"
}

# Enhanced worker process with performance tracking
worker_process_enhanced() {
    local worker_id="$1"
    local queue="$2"
    local log_file="$WORKER_LOG_DIR/worker_$worker_id.log"
    
    exec > "$log_file" 2>&1
    log "Enhanced worker $worker_id started (PID: $$)"
    
    local processed=0
    local errors=0
    local start_time=$(date +%s%3N)
    local processed_files=()
    local avg_time=0
    
    while IFS= read -r file_path; do
        [[ "$file_path" == "SHUTDOWN" ]] && break
        
        local file_start=$(date +%s%3N)
        
        if process_single_file "$file_path" "$worker_id"; then
            ((processed++))
            processed_files+=("$file_path")
            
            # Update worker stats
            local file_time=$(($(date +%s%3N) - file_start))
            avg_time=$(( (avg_time * (processed - 1) + file_time) / processed ))
            WORKER_STATS[$worker_id]="$processed:$errors:$avg_time"
            
            # Checkpoint every N files
            if ((processed % CHECKPOINT_INTERVAL == 0)); then
                save_checkpoint "${processed_files[@]}"
            fi
        else
            ((errors++))
            WORKER_STATS[$worker_id]="$processed:$errors:$avg_time"
        fi
        
        # Update global progress
        local current_progress
        current_progress=$(cat "$PROGRESS_FILE")
        echo $((current_progress + 1)) > "$PROGRESS_FILE"
        
    done < "$queue"
    
    # Final checkpoint
    [[ ${#processed_files[@]} -gt 0 ]] && save_checkpoint "${processed_files[@]}"
    
    local total_time=$(( ($(date +%s%3N) - start_time) / 1000 ))
    log "Worker $worker_id completed: $processed files, $errors errors, ${total_time}s total"
}

# Process single file with enhanced error handling
process_single_file() {
    local file_path="$1"
    local worker_id="$2"
    local filename=$(basename "$file_path")
    
    # Skip if file doesn't exist or is a directory
    [[ ! -f "$file_path" ]] && return 1
    
    # Determine category using cached pattern matching
    local category
    category=$(cached_pattern_match "$filename")
    
    # Create destination directory if needed
    local dest_dir="$HOME/mik/$category"
    mkdir -p "$dest_dir"
    
    # Handle conflicts with timestamp and worker ID suffix
    local dest_file="$dest_dir/$filename"
    if [[ -e "$dest_file" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local name="${filename%.*}"
        local ext="${filename##*.}"
        if [[ "$name" == "$filename" ]]; then
            dest_file="$dest_dir/${filename}_w${worker_id}_${timestamp}"
        else
            dest_file="$dest_dir/${name}_w${worker_id}_${timestamp}.${ext}"
        fi
    fi
    
    # Move file (with error handling)
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would move $filename -> $category/" >> "$WORKER_LOG_DIR/dryrun.log"
        return 0
    elif mv "$file_path" "$dest_file" 2>/dev/null; then
        echo "Moved: $filename -> $category/" >> "$WORKER_LOG_DIR/success.log"
        return 0
    else
        echo "Failed: $filename (worker $worker_id)" >> "$WORKER_LOG_DIR/errors.log"
        return 1
    fi
}

# Start all workers
start_workers() {
    log "Starting $MAX_WORKERS worker processes..."
    
    for ((i=0; i<MAX_WORKERS; i++)); do
        worker_process_enhanced "$i" "${WORKER_QUEUES[$i]}" &
        local pid=$!
        WORKER_PIDS+=("$pid")
        log "Started worker $i (PID: $pid)"
    done
}

# Smart file distribution with load balancing
distribute_files_adaptive() {
    local file_list=("$@")
    local total_files=${#file_list[@]}
    
    log "Using adaptive load balancing for $total_files files..."
    
    for ((i=0; i<total_files; i++)); do
        local file="${file_list[$i]}"
        local best_worker
        best_worker=$(find_best_worker "$file")
        
        # Send to best worker
        echo "$file" > "${WORKER_QUEUES[$best_worker]}" &
        ((WORKER_LOADS[$best_worker]++))
        
        # Rebalance every 100 files
        if ((i % 100 == 0 && i > 0)); then
            rebalance_workers
        fi
    done
}

# Find the best worker for a file
find_best_worker() {
    local file="$1"
    local best_worker=0
    local best_score=999999
    
    for ((i=0; i<MAX_WORKERS; i++)); do
        local stats="${WORKER_STATS[$i]}"
        IFS=':' read -r processed errors avg_time <<< "$stats"
        
        # Calculate worker score (lower is better)
        local current_load=${WORKER_LOADS[$i]}
        local error_rate=$((errors * 100 / (processed + 1)))
        local score=$((current_load * 10 + error_rate + avg_time / 1000))
        
        # Prefer workers with lower load and better performance
        if [[ $score -lt $best_score ]]; then
            best_score=$score
            best_worker=$i
        fi
    done
    
    echo "$best_worker"
}

# Rebalance workers if needed
rebalance_workers() {
    local total_load=0
    local max_load=0
    local min_load=999999
    
    for load in "${WORKER_LOADS[@]}"; do
        ((total_load += load))
        ((load > max_load)) && max_load=$load
        ((load < min_load)) && min_load=$load
    done
    
    local avg_load=$((total_load / MAX_WORKERS))
    local load_imbalance=$((max_load - min_load))
    
    # If imbalance is significant, log it
    if [[ $load_imbalance -gt $((avg_load / 2)) ]]; then
        log "Load imbalance detected: max=$max_load, min=$min_load, avg=$avg_load"
    fi
}

# ============================================================================
# STATE MANAGEMENT & RESUME
# ============================================================================

# Save current state
save_checkpoint() {
    local processed_files=("$@")
    
    cat > "$STATE_FILE" << EOF
{
    "timestamp": $(date +%s),
    "total_files": ${total_files:-0},
    "processed_count": ${#processed_files[@]},
    "processed_files": [
$(printf '        "%s",\n' "${processed_files[@]}" | sed '$s/,$//')
    ],
    "worker_stats": {
$(for ((i=0; i<MAX_WORKERS; i++)); do
    echo "        \"worker_$i\": \"${WORKER_STATS[$i]}\","
done | sed '$s/,$//')
    }
}
EOF
    
    log "Checkpoint saved: ${#processed_files[@]} files processed"
}

# Resume from checkpoint
resume_from_checkpoint() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log "No checkpoint found, starting fresh"
        return 1
    fi
    
    log "Found checkpoint, resuming..."
    
    # Parse JSON state (simplified)
    local processed_count
    processed_count=$(grep '"processed_count"' "$STATE_FILE" | sed 's/.*: *\([0-9]*\).*/\1/')
    
    log "Resuming from $processed_count processed files"
    
    # Extract processed files list
    local processed_files=()
    while IFS= read -r line; do
        local file
        file=$(echo "$line" | sed 's/.*"\(.*\)".*/\1/')
        processed_files+=("$file")
    done < <(sed -n '/processed_files/,/]/p' "$STATE_FILE" | grep '".*"' | sed 's/,$//')
    
    # Filter out already processed files
    local remaining_files=()
    for file in "${ALL_FILES[@]}"; do
        local already_processed=false
        for processed in "${processed_files[@]}"; do
            [[ "$file" == "$processed" ]] && already_processed=true && break
        done
        [[ "$already_processed" == false ]] && remaining_files+=("$file")
    done
    
    log "Found ${#remaining_files[@]} remaining files to process"
    ALL_FILES=("${remaining_files[@]}")
    return 0
}

# ============================================================================
# MONITORING & DASHBOARD
# ============================================================================

# Real-time progress monitoring
monitor_progress() {
    local total_files="$1"
    local start_time=$(date +%s)
    
    while true; do
        local current_progress
        current_progress=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
        local elapsed=$(($(date +%s) - start_time))
        local rate=$((current_progress / (elapsed + 1)))
        local eta=$(( (total_files - current_progress) / (rate + 1) ))
        
        printf "\rProgress: %d/%d files (%.1f%%) | Rate: %d files/sec | ETA: %dm%ds" \
            "$current_progress" "$total_files" \
            "$((current_progress * 100 / total_files))" \
            "$rate" "$((eta / 60))" "$((eta % 60))"
        
        [[ $current_progress -ge $total_files ]] && break
        sleep 2
    done
    echo
}

# Performance dashboard
show_performance_dashboard() {
    local total_files="$1"
    
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                    FILE ORGANIZER DASHBOARD                  ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        
        local current_progress
        current_progress=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "0")
        local percent=$((current_progress * 100 / total_files))
        
        # Progress bar
        local bar_width=50
        local filled=$((percent * bar_width / 100))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=filled; i<bar_width; i++)); do bar+="░"; done
        
        printf "║ Progress: [%s] %3d%% (%d/%d)\n" "$bar" "$percent" "$current_progress" "$total_files"
        echo "║"
        
        # Worker status
        echo "║ Worker Status:"
        for ((i=0; i<MAX_WORKERS; i++)); do
            local stats="${WORKER_STATS[$i]}"
            IFS=':' read -r processed errors avg_time <<< "$stats"
            local load=${WORKER_LOADS[$i]}
            printf "║   Worker %d: %4d files | %2d errors | %3dms avg | Load: %3d\n" \
                "$i" "$processed" "$errors" "$((avg_time / 1000))" "$load"
        done
        
        echo "║"
        
        # System stats
        local mem_usage
        mem_usage=$(ps -o rss= -p $$ 2>/dev/null | tr -d ' ' || echo "0")
        local cache_hits=$((CACHE_HIT_RATIO * 100 / (current_progress + 1)))
        
        echo "║ System Stats:"
        printf "║   Memory Usage: %d MB\n" "$((mem_usage / 1024))"
        printf "║   Cache Hit Rate: %d%%\n" "$cache_hits"
        printf "║   Active Workers: %d/%d\n" "${#WORKER_PIDS[@]}" "$MAX_WORKERS"
        
        echo "╚══════════════════════════════════════════════════════════════╝"
        
        [[ $current_progress -ge $total_files ]] && break
        sleep 1
    done
}

# ============================================================================
# CLEANUP & SHUTDOWN
# ============================================================================

# Graceful worker shutdown
shutdown_workers() {
    if [[ ${#WORKER_PIDS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Shutting down workers..."
    
    # Send shutdown signal to all workers
    for queue in "${WORKER_QUEUES[@]}"; do
        echo "SHUTDOWN" > "$queue" &
    done
    
    # Wait for workers to finish (with timeout)
    local timeout=$WORKER_TIMEOUT
    for pid in "${WORKER_PIDS[@]}"; do
        if timeout "$timeout" wait "$pid" 2>/dev/null; then
            log "Worker $pid finished gracefully"
        else
            log "Worker $pid timed out, force killing..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
}

# Complete cleanup
cleanup_workers() {
    shutdown_workers
    [[ -d "$WORKER_DIR" ]] && rm -rf "$WORKER_DIR"
}

# ============================================================================
# MAIN ORGANIZATION FUNCTION
# ============================================================================

# Enhanced main organization function
organize_files_parallel() {
    local source_dir="$1"
    
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              MULTI-WORKER FILE ORGANIZATION v3.0             ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║ Source: %-50s ║\n" "$source_dir"
    printf "║ Workers: %-49s ║\n" "$MAX_WORKERS"
    printf "║ Batch size: %-44s ║\n" "$BATCH_SIZE"
    printf "║ Mode: %-52s ║\n" "${DRY_RUN:+DRY RUN}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    # Validation
    [[ ! -d "$source_dir" ]] && error_exit "Source directory not found: $source_dir"
    [[ ! -w "$source_dir" ]] && error_exit "No write permission on source directory"
    
    # Initialize system
    init_workers
    
    # Start memory monitor
    local memory_monitor_pid
    memory_monitor_pid=$(monitor_memory_usage)
    
    # Collect all files to process
    log "Scanning for files..."
    local file_list=()
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(find "$source_dir" -maxdepth 1 -type f -print0)
    
    local total_files=${#file_list[@]}
    log "Found $total_files files to organize"
    
    if [[ $total_files -eq 0 ]]; then
        log "No files to organize"
        cleanup_workers
        return 0
    fi
    
    # Store for resume capability
    declare -g ALL_FILES=("${file_list[@]}")
    declare -g total_files=$total_files
    
    # Resume from checkpoint if requested
    if [[ "$RESUME_MODE" == "true" ]]; then
        resume_from_checkpoint
        total_files=${#ALL_FILES[@]}
        file_list=("${ALL_FILES[@]}")
    fi
    
    # Create category directories
    for category in "${BULK_CATEGORIES[@]}"; do
        mkdir -p "$source_dir/$category"
    done
    
    # Start workers
    start_workers
    
    # Start monitoring
    if [[ "$DASHBOARD_MODE" == "true" ]]; then
        show_performance_dashboard "$total_files" &
        local dashboard_pid=$!
    else
        monitor_progress "$total_files" &
        local monitor_pid=$!
    fi
    
    # Distribute work using adaptive load balancing
    distribute_files_adaptive "${file_list[@]}"
    
    # Wait for completion
    wait "${WORKER_PIDS[@]}"
    
    # Stop monitors
    [[ -n "${dashboard_pid:-}" ]] && kill "$dashboard_pid" 2>/dev/null && wait "$dashboard_pid" 2>/dev/null
    [[ -n "${monitor_pid:-}" ]] && kill "$monitor_pid" 2>/dev/null && wait "$monitor_pid" 2>/dev/null
    [[ -n "${memory_monitor_pid:-}" ]] && kill "$memory_monitor_pid" 2>/dev/null
    
    # Final progress update
    local final_count
    final_count=$(cat "$PROGRESS_FILE")
    log "Completed: $final_count/$total_files files processed"
    
    # Show summary
    show_processing_summary
    
    # Cleanup
    cleanup_workers
}

# Show processing summary
show_processing_summary() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                      PROCESSING SUMMARY                      ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    
    if [[ -f "$WORKER_LOG_DIR/success.log" ]]; then
        local success_count
        success_count=$(wc -l < "$WORKER_LOG_DIR/success.log" 2>/dev/null || echo "0")
        printf "║ Successfully processed: %-34s ║\n" "$success_count files"
    fi
    
    if [[ -f "$WORKER_LOG_DIR/errors.log" ]]; then
        local error_count
        error_count=$(wc -l < "$WORKER_LOG_DIR/errors.log" 2>/dev/null || echo "0")
        printf "║ Errors encountered: %-38s ║\n" "$error_count files"
    fi
    
    # Category distribution
    echo "║                                                              ║"
    echo "║ Files per category:                                          ║"
    for category in "${BULK_CATEGORIES[@]}"; do
        if [[ -d "$HOME/mik/$category" ]]; then
            local count
            count=$(find "$HOME/mik/$category" -maxdepth 1 -type f 2>/dev/null | wc -l)
            printf "║   %-15s: %-39s ║\n" "$category" "$count files"
        fi
    done
    
    local cache_hits=$((CACHE_HIT_RATIO * 100 / (${total_files:-1})))
    printf "║ Cache hit rate: %-42s ║\n" "$cache_hits%"
    
    echo "╚══════════════════════════════════════════════════════════════╝"
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

# Help function
show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║           WSL Directory Organization v3.0 Enhanced           ║
║                  Multi-Worker Performance Edition            ║
╚══════════════════════════════════════════════════════════════╝

Usage: ./organize_mik_enhanced.sh [OPTIONS]

Options:
    --dry-run           Preview changes without executing
    --test              Run classification tests
    --workers N         Set number of worker processes (default: all cores)
    --batch-size N      Set files per batch (default: 100)
    --dashboard         Show real-time performance dashboard
    --resume            Resume from previous checkpoint
    --help              Show this help

Environment Variables:
    MAX_WORKERS         Number of worker processes
    BATCH_SIZE          Files per batch
    WORKER_TIMEOUT      Timeout per worker (seconds)

Enhanced Categories:
    THESIS              Academic work, research papers
    CLAUDE-CODE         Claude/MCP/Anthropic ecosystem
    DALLE2              DALL-E tools (CLI/App/Android)
    AI-TOOLS            Other AI tools (MJ, SD, etc.)
    SEARCH              SearXNG and search engines
    MEDIA-WORK          Video/audio processing
    DEV-TOOLS           Development utilities
    PROJECTS            General projects and applications
    RESOURCES           Configs, docs, data files
    _UNSORTED           Uncategorized files

Performance Features:
    ✓ Multi-worker parallel processing
    ✓ Adaptive load balancing
    ✓ Pattern matching cache
    ✓ Memory usage monitoring
    ✓ Resume capability
    ✓ Real-time dashboard
    ✓ Conflict resolution
    ✓ Progress tracking

Examples:
    # Use all CPU cores
    ./organize_mik_enhanced.sh

    # Custom worker count with dashboard
    ./organize_mik_enhanced.sh --workers 8 --dashboard

    # Dry run with 4 workers
    ./organize_mik_enhanced.sh --dry-run --workers 4

    # Resume interrupted organization
    ./organize_mik_enhanced.sh --resume

EOF
}

# Test function
test_classification_logic() {
    echo "🧪 Testing enhanced classification logic..."
    
    local test_files=(
        "thesis_chapter1.tex"
        "dalle-cli-v2.py"
        "dalle_android_v3.apk"
        "claude_desktop_config.json"
        "claude_mcp_server.py"
        "midjourney_bot.py"
        "stable_diffusion_webui.sh"
        "searxng-docker-compose.yml"
        "searxng_config.yml"
        "video_concat_ffmpeg.sh"
        "my_project_v2.zip"
        "nginx_config.conf"
        "research_paper_analysis.pdf"
        "memento_knowledge_graph.json"
    )
    
    echo
    printf "%-35s → %s\n" "Test File" "Category:Score"
    echo "────────────────────────────────────────────────────────────"
    
    for file in "${test_files[@]}"; do
        local result=$(determine_file_category_optimized "$file")
        printf "%-35s → %s\n" "$file" "$result"
    done
    
    echo
    echo "✅ Classification test completed"
}

# Trap for cleanup on exit
trap cleanup_workers EXIT INT TERM

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                echo "🔍 DRY RUN MODE - No files will be moved"
                DRY_RUN=true
                shift ;;
            --test)
                test_classification_logic
                exit 0 ;;
            --workers)
                MAX_WORKERS="$2"
                shift 2 ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2 ;;
            --dashboard)
                DASHBOARD_MODE=true
                shift ;;
            --resume)
                RESUME_MODE=true
                shift ;;
            --help)
                show_help
                exit 0 ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1 ;;
        esac
    done
    
    # Validate worker count
    if [[ $MAX_WORKERS -lt 1 || $MAX_WORKERS -gt 32 ]]; then
        error_exit "Invalid worker count: $MAX_WORKERS (must be 1-32)"
    fi
    
    # Run main organization
    organize_files_parallel "$HOME/mik"
}

# Run main function with all arguments
main "$@"