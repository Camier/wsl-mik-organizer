# Example configuration overrides
# Source this before running organize_mik.sh to customize

# Minimum files to maintain a category
CATEGORY_CONFIG[MIN_FILES]=5

# Custom categories (example)
CUSTOM_CATEGORIES=(
    "THESIS"
    "CLAUDE-CODE"
    "DALLE2"
    "AI-TOOLS"
    "MEDIA-WORK"
    "DEV-TOOLS"
    "PROJECTS"
    "RESOURCES"
    "ARCHIVE"
    "_UNSORTED"
)

# Additional patterns (example)
EXTENDED_PATTERNS[ARCHIVE]="(backup|old|deprecated|archive|.+_old$|.+_backup$)"
