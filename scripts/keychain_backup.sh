#!/bin/bash
#
# keychain_backup.sh - Dynamic Entitlement Resign Wrapper for KeychainHelper
#
# This script extracts keychain-access-groups entitlements from a target app,
# resigns the KeychainHelper binary with those entitlements, and executes it.
#
# Usage:
#   keychain_backup.sh backup <bundleID> <backup_file>
#   keychain_backup.sh restore <bundleID> <backup_file> [--overwrite]
#   keychain_backup.sh wipe <bundleID>
#   keychain_backup.sh list <bundleID>
#
# Requirements:
#   - Jailbroken iOS device with AMFI patches
#   - ldid installed (/usr/bin/ldid or rootless path)
#   - plutil installed (comes with iOS)
#

# Removed 'set -e' for better error handling - we handle errors explicitly

# === Configuration ===
HELPER_TOOL_PATH="/Library/WeaponX/backup_helper"
TEMP_DIR="/tmp/keychain_helper_$$"
VERBOSE=0

# Optional subset of keychain groups (CSV) provided by caller.
OVERRIDE_KEYCHAIN_GROUPS=""

# === Color Output ===
# Only use colors if running in a TTY (interactive terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "[DEBUG] $1" >&2
    fi
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# === Find ldid binary ===
find_ldid() {
    local paths=(
        "/usr/bin/ldid"
        "/var/jb/usr/bin/ldid"
        "/private/preboot/jb/usr/bin/ldid"
        "/bin/ldid"
    )
    
    for path in "${paths[@]}"; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# === Find plutil binary ===
find_plutil() {
    local paths=(
        "/usr/bin/plutil"
        "/var/jb/usr/bin/plutil"
        "/bin/plutil"
    )
    
    for path in "${paths[@]}"; do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# === Find app executable path from bundle ID ===
find_app_executable() {
    local bundle_id="$1"
    
    log_verbose "Searching for app with bundle ID: $bundle_id"
    
    # === 1. Check system apps in /Applications ===
    local system_app_paths=(
        "/Applications"
        "/var/jb/Applications"
        "/private/preboot/jb/Applications"
    )
    
    for base_path in "${system_app_paths[@]}"; do
        if [ ! -d "$base_path" ]; then
            continue
        fi
        
        for app_dir in "$base_path"/*.app; do
            if [ ! -d "$app_dir" ]; then
                continue
            fi
            
            local info_plist="$app_dir/Info.plist"
            if [ ! -f "$info_plist" ]; then
                continue
            fi
            
            # Extract CFBundleIdentifier
            local found_bundle_id
            found_bundle_id=$(plutil -key CFBundleIdentifier "$info_plist" 2>/dev/null || true)
            
            if [ "$found_bundle_id" = "$bundle_id" ]; then
                # Found matching app, get executable name
                local exe_name
                exe_name=$(plutil -key CFBundleExecutable "$info_plist" 2>/dev/null || true)
                
                if [ -n "$exe_name" ] && [ -f "$app_dir/$exe_name" ]; then
                    log_verbose "Found system app: $app_dir/$exe_name"
                    echo "$app_dir/$exe_name"
                    return 0
                fi
            fi
        done
    done
    
    # === 2. Check App Store apps in /var/containers/Bundle/Application ===
    local bundle_paths=(
        "/var/containers/Bundle/Application"
        "/var/mobile/Containers/Bundle/Application"
        "/private/var/containers/Bundle/Application"
    )
    
    for base_path in "${bundle_paths[@]}"; do
        if [ ! -d "$base_path" ]; then
            continue
        fi
        
        # Search through all app UUIDs
        for uuid_dir in "$base_path"/*; do
            if [ ! -d "$uuid_dir" ]; then
                continue
            fi
            
            # Find .app directory
            for app_dir in "$uuid_dir"/*.app; do
                if [ ! -d "$app_dir" ]; then
                    continue
                fi
                
                # Check Info.plist for bundle ID
                local info_plist="$app_dir/Info.plist"
                if [ ! -f "$info_plist" ]; then
                    continue
                fi
                
                # Extract CFBundleIdentifier
                local found_bundle_id
                found_bundle_id=$(plutil -key CFBundleIdentifier "$info_plist" 2>/dev/null || true)
                
                if [ "$found_bundle_id" = "$bundle_id" ]; then
                    # Found matching app, get executable name
                    local exe_name
                    exe_name=$(plutil -key CFBundleExecutable "$info_plist" 2>/dev/null || true)
                    
                    if [ -n "$exe_name" ] && [ -f "$app_dir/$exe_name" ]; then
                        log_verbose "Found App Store app: $app_dir/$exe_name"
                        echo "$app_dir/$exe_name"
                        return 0
                    fi
                fi
            done
        done
    done
    
    return 1
}

# === Extract entitlements from app ===
extract_entitlements() {
    local app_binary="$1"
    local output_file="$2"
    local ldid_path
    
    ldid_path=$(find_ldid) || {
        log_error "ldid not found. Please install ldid."
        return 1
    }
    
    log_verbose "Using ldid: $ldid_path"
    log_verbose "Extracting entitlements from: $app_binary"
    
    "$ldid_path" -e "$app_binary" > "$output_file" 2>/dev/null
    
    if [ ! -s "$output_file" ]; then
        log_error "Failed to extract entitlements or app has no entitlements"
        return 1
    fi
    
    return 0
}

# === Parse keychain access groups from entitlements ===
parse_keychain_groups() {
    local ent_file="$1"
    local plutil_path
    
    plutil_path=$(find_plutil) || {
        log_error "plutil not found"
        return 1
    }
    
    # Try to extract keychain-access-groups array
    # plutil -extract keychain-access-groups xml1 -o - "$ent_file"
    
    # Use grep/sed as fallback for extracting groups
    local groups=""
    local in_groups=0
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "keychain-access-groups"; then
            in_groups=1
            continue
        fi
        
        if [ "$in_groups" -eq 1 ]; then
            if echo "$line" | grep -q "</array>"; then
                in_groups=0
                continue
            fi
            
            if echo "$line" | grep -q "<string>"; then
                local group
                group=$(echo "$line" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
                if [ -n "$group" ]; then
                    if [ -n "$groups" ]; then
                        groups="$groups,$group"
                    else
                        groups="$group"
                    fi
                fi
            fi
        fi
    done < "$ent_file"
    
    echo "$groups"
}

# === Parse application-identifier from entitlements ===
parse_app_identifier() {
    local ent_file="$1"
    local identifier=""
    
    # Look for application-identifier key and extract the string value
    local found_key=0
    while IFS= read -r line; do
        if echo "$line" | grep -q "application-identifier"; then
            found_key=1
            continue
        fi
        
        if [ "$found_key" -eq 1 ]; then
            if echo "$line" | grep -q "<string>"; then
                identifier=$(echo "$line" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
                break
            fi
        fi
    done < "$ent_file"
    
    echo "$identifier"
}

# === Generate entitlements plist for helper tool ===
# For system apps, we copy the full entitlements and add our extras
# For App Store apps, we generate minimal entitlements
generate_helper_entitlements() {
    local keychain_groups="$1"
    local app_groups="$2"
    local output_file="$3"
    local app_identifier="$4"
    local source_ent_file="$5"  # Optional: full entitlements file from target app
    
    log_verbose "Generating entitlements to: $output_file"
    log_verbose "Keychain groups: $keychain_groups"
    log_verbose "App identifier: $app_identifier"
    log_verbose "Source entitlements: $source_ent_file"
    
    # Check if this is a system app (use full entitlements)
    if [ -n "$source_ent_file" ] && [ -f "$source_ent_file" ]; then
        log_verbose "Using full entitlements from target app (system app mode)"
        
        # Copy source entitlements and inject our security overrides
        # We'll modify the plist to add no-sandbox and no-container
        cp "$source_ent_file" "$output_file"
        
        # Add our security entitlements using plutil if available
        local plutil_path
        plutil_path=$(find_plutil) || true
        
        if [ -n "$plutil_path" ]; then
            # Add security entitlements
            "$plutil_path" -replace "com.apple.private.security.no-sandbox" -bool true "$output_file" 2>/dev/null || true
            "$plutil_path" -replace "com.apple.private.security.no-container" -bool true "$output_file" 2>/dev/null || true
            "$plutil_path" -replace "com.apple.private.security.container-required" -bool false "$output_file" 2>/dev/null || true
            
            log_verbose "Injected security entitlements via plutil"
        else
            log_warn "plutil not available, using source entitlements as-is"
        fi
    else
        log_verbose "Generating custom entitlements (App Store app mode)"
        
        # Use printf to avoid heredoc CRLF issues
        {
            printf '<?xml version="1.0" encoding="UTF-8"?>\n'
            printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            printf '<plist version="1.0">\n'
            printf '<dict>\n'
            
            # Platform application - required for system-level access
            printf '    <key>platform-application</key>\n'
            printf '    <true/>\n'
            
            # Application identifier - critical for keychain access matching
            if [ -n "$app_identifier" ]; then
                printf '    <key>application-identifier</key>\n'
                printf '    <string>%s</string>\n' "$app_identifier"
            fi
            
            # Security entitlements
            printf '    <key>com.apple.private.security.no-sandbox</key>\n'
            printf '    <true/>\n'
            printf '    <key>com.apple.private.security.no-container</key>\n'
            printf '    <true/>\n'
            printf '    <key>com.apple.private.security.container-required</key>\n'
            printf '    <false/>\n'
            
            # Keychain specific entitlements
            printf '    <key>com.apple.keystore.access-keychain-keys</key>\n'
            printf '    <true/>\n'
            printf '    <key>com.apple.keystore.device</key>\n'
            printf '    <true/>\n'
            
            # Add keychain-access-groups
            if [ -n "$keychain_groups" ]; then
                printf '    <key>keychain-access-groups</key>\n'
                printf '    <array>\n'
                
                IFS=',' read -ra GROUPS <<< "$keychain_groups"
                for group in "${GROUPS[@]}"; do
                    printf '        <string>%s</string>\n' "$group"
                done
                
                printf '    </array>\n'
            fi
            
            # Add application-groups if present
            if [ -n "$app_groups" ]; then
                printf '    <key>com.apple.security.application-groups</key>\n'
                printf '    <array>\n'
                
                IFS=',' read -ra GROUPS <<< "$app_groups"
                for group in "${GROUPS[@]}"; do
                    printf '        <string>%s</string>\n' "$group"
                done
                
                printf '    </array>\n'
            fi
            
            printf '</dict>\n'
            printf '</plist>\n'
        } > "$output_file"
    fi
    
    # Verify file was created
    if [ ! -f "$output_file" ]; then
        log_error "Failed to create entitlements file: $output_file"
        return 1
    fi
    
    log_verbose "Entitlements file created successfully"
    return 0
}

# === Parse application groups from entitlements ===
parse_app_groups() {
    local ent_file="$1"
    local groups=""
    local in_groups=0
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "com.apple.security.application-groups"; then
            in_groups=1
            continue
        fi
        
        if [ "$in_groups" -eq 1 ]; then
            if echo "$line" | grep -q "</array>"; then
                in_groups=0
                continue
            fi
            
            if echo "$line" | grep -q "<string>"; then
                local group
                group=$(echo "$line" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
                if [ -n "$group" ]; then
                    if [ -n "$groups" ]; then
                        groups="$groups,$group"
                    else
                        groups="$group"
                    fi
                fi
            fi
        fi
    done < "$ent_file"
    
    echo "$groups"
}

# === Resign helper tool with new entitlements ===
# Usage: resign_helper <entitlements_file> <target_binary>
resign_helper() {
    local ent_file="$1"
    local binary_path="$2"
    local ldid_path
    
    ldid_path=$(find_ldid) || {
        log_error "ldid not found"
        return 1
    }
    
    # Check if binary exists
    if [ ! -f "$binary_path" ]; then
        log_error "Binary not found at: $binary_path"
        return 1
    fi
    
    # Check if entitlements file exists
    if [ ! -f "$ent_file" ]; then
        log_error "Entitlements file not found: $ent_file"
        return 1
    fi
    
    log_verbose "Resigning binary: $binary_path"
    log_verbose "With entitlements: $ent_file"
    
    # Run ldid and capture any errors
    local ldid_output
    ldid_output=$("$ldid_path" -S"$ent_file" "$binary_path" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "ldid failed with exit code $exit_code"
        if [ -n "$ldid_output" ]; then
            log_error "ldid output: $ldid_output"
        fi
        return 1
    fi
    
    # Verify signing worked
    if [ ! -x "$binary_path" ]; then
        chmod +x "$binary_path"
    fi
    
    log_verbose "Binary resigned successfully"
    return 0
}

# === Main functions ===

do_backup() {
    local bundle_id="$1"
    local backup_file="$2"
    local override_groups="$3"
    
    log_info "Starting keychain backup for: $bundle_id"
    
    # Find app executable
    log_info "Locating app executable..."
    local app_binary
    app_binary=$(find_app_executable "$bundle_id") || {
        log_error "Could not find app with bundle ID: $bundle_id"
        return 1
    }
    log_verbose "Found app: $app_binary"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Extract entitlements
    log_info "Extracting entitlements..."
    local ent_file="$TEMP_DIR/app_ent.xml"
    extract_entitlements "$app_binary" "$ent_file" || return 1
    
    # Parse keychain groups
    log_info "Parsing keychain access groups..."
    local keychain_groups
    keychain_groups=$(parse_keychain_groups "$ent_file")

    # If caller provided a subset, use it.
    if [ -n "$override_groups" ]; then
        log_info "Using override keychain groups: $override_groups"
        keychain_groups="$override_groups"
    fi
    
    if [ -z "$keychain_groups" ]; then
        log_error "No keychain-access-groups found in app entitlements"
        return 1
    fi
    log_info "Found keychain groups: $keychain_groups"
    
    # Parse app groups (optional)
    local app_groups
    app_groups=$(parse_app_groups "$ent_file")
    
    # Parse application-identifier (critical for keychain access)
    local app_identifier
    app_identifier=$(parse_app_identifier "$ent_file")
    if [ -n "$app_identifier" ]; then
        log_info "Found application-identifier: $app_identifier"
    else
        log_warn "No application-identifier found, using bundle ID"
        app_identifier="$bundle_id"
    fi
    
    # Detect if this is a system/Apple app that needs full entitlements
    # Check: 1) In /Applications, OR 2) Bundle ID starts with com.apple.
    local is_system_app=0
    local source_ent_for_system=""
    if echo "$app_binary" | grep -q "^/Applications/"; then
        is_system_app=1
        source_ent_for_system="$ent_file"
        log_info "Detected system app (by path) - will use full entitlements"
    elif echo "$app_identifier" | grep -q "^com\.apple\."; then
        is_system_app=1
        source_ent_for_system="$ent_file"
        log_info "Detected Apple app (by identifier) - will use full entitlements"
    fi
    
    # Generate helper entitlements
    log_info "Generating helper entitlements..."
    local helper_ent="$TEMP_DIR/helper_ent.plist"
    if ! generate_helper_entitlements "$keychain_groups" "$app_groups" "$helper_ent" "$app_identifier" "$source_ent_for_system"; then
        log_error "Failed to generate helper entitlements"
        return 1
    fi
    
    # Prepare working copy of helper tool
    local working_helper="$TEMP_DIR/backup_helper"
    if ! cp "$HELPER_TOOL_PATH" "$working_helper"; then
        log_error "Failed to copy helper tool to temp: $working_helper"
        return 1
    fi
    chmod 755 "$working_helper"
    
    # Resign helper
    log_info "Resigning KeychainHelper..."
    if ! resign_helper "$helper_ent" "$working_helper"; then
        log_error "Failed to resign helper tool"
        return 1
    fi
    
    # Execute backup using the resigned copy
    log_info "Executing backup..."
    "$working_helper" --action backup --file "$backup_file" --groups "$keychain_groups"
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "Backup completed successfully: $backup_file"
    else
        log_error "Backup failed with exit code: $exit_code"
    fi
    
    return $exit_code
}

do_restore() {
    local bundle_id="$1"
    local backup_file="$2"
    local overwrite="$3"
    local override_groups="$4"
    
    log_info "Starting keychain restore for: $bundle_id"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Find app executable and resign with its entitlements
    log_info "Locating app executable..."
    local app_binary
    app_binary=$(find_app_executable "$bundle_id") || {
        log_error "Could not find app with bundle ID: $bundle_id"
        return 1
    }
    
    mkdir -p "$TEMP_DIR"
    
    log_info "Extracting entitlements..."
    local ent_file="$TEMP_DIR/app_ent.xml"
    extract_entitlements "$app_binary" "$ent_file" || return 1
    
    local keychain_groups
    keychain_groups=$(parse_keychain_groups "$ent_file")

    if [ -n "$override_groups" ]; then
        log_info "Using override keychain groups: $override_groups"
        keychain_groups="$override_groups"
    fi
    local app_groups
    app_groups=$(parse_app_groups "$ent_file")
    local app_identifier
    app_identifier=$(parse_app_identifier "$ent_file")
    [ -z "$app_identifier" ] && app_identifier="$bundle_id"
    
    # Detect system/Apple app
    local source_ent_for_system=""
    if echo "$app_binary" | grep -q "^/Applications/"; then
        source_ent_for_system="$ent_file"
    elif echo "$app_identifier" | grep -q "^com\.apple\."; then
        source_ent_for_system="$ent_file"
        log_info "Detected Apple app - will use full entitlements"
    fi
    
    local helper_ent="$TEMP_DIR/helper_ent.plist"
    generate_helper_entitlements "$keychain_groups" "$app_groups" "$helper_ent" "$app_identifier" "$source_ent_for_system"
    
    # Prepare working copy of helper tool
    local working_helper="$TEMP_DIR/backup_helper"
    if ! cp "$HELPER_TOOL_PATH" "$working_helper"; then
        log_error "Failed to copy helper tool to temp: $working_helper"
        return 1
    fi
    chmod 755 "$working_helper"
    
    log_info "Resigning KeychainHelper..."
    resign_helper "$helper_ent" "$working_helper" || return 1
    
    # Execute restore using the resigned copy
    log_info "Executing restore..."
    local extra_args=""
    if [ "$overwrite" = "--overwrite" ]; then
        extra_args="--overwrite"
    fi
    
    "$working_helper" --action restore --file "$backup_file" $extra_args
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "Restore completed successfully"
    else
        log_error "Restore failed with exit code: $exit_code"
    fi
    
    return $exit_code
}

do_wipe() {
    local bundle_id="$1"
    local override_groups="$2"
    
    log_info "Starting keychain wipe for: $bundle_id"
    
    # Find app and get entitlements
    local app_binary
    app_binary=$(find_app_executable "$bundle_id") || {
        log_error "Could not find app with bundle ID: $bundle_id"
        return 1
    }
    
    mkdir -p "$TEMP_DIR"
    
    local ent_file="$TEMP_DIR/app_ent.xml"
    extract_entitlements "$app_binary" "$ent_file" || return 1
    
    local keychain_groups
    keychain_groups=$(parse_keychain_groups "$ent_file")

    if [ -n "$override_groups" ]; then
        log_info "Using override keychain groups: $override_groups"
        keychain_groups="$override_groups"
    fi
    
    if [ -z "$keychain_groups" ]; then
        log_error "No keychain-access-groups found"
        return 1
    fi
    
    log_warn "This will DELETE all keychain items for: $keychain_groups"
    
    local app_groups
    app_groups=$(parse_app_groups "$ent_file")
    local app_identifier
    app_identifier=$(parse_app_identifier "$ent_file")
    [ -z "$app_identifier" ] && app_identifier="$bundle_id"
    
    # Detect system/Apple app
    local source_ent_for_system=""
    if echo "$app_binary" | grep -q "^/Applications/"; then
        source_ent_for_system="$ent_file"
    elif echo "$app_identifier" | grep -q "^com\.apple\."; then
        source_ent_for_system="$ent_file"
    fi
    
    local helper_ent="$TEMP_DIR/helper_ent.plist"
    generate_helper_entitlements "$keychain_groups" "$app_groups" "$helper_ent" "$app_identifier" "$source_ent_for_system"
    
    # Prepare working copy
    local working_helper="$TEMP_DIR/backup_helper"
    if ! cp "$HELPER_TOOL_PATH" "$working_helper"; then
        log_error "Failed to copy helper"
        return 1
    fi
    chmod 755 "$working_helper"
    
    resign_helper "$helper_ent" "$working_helper" || return 1
    
    "$working_helper" --action wipe --groups "$keychain_groups"
    
    return $?
}

do_list() {
    local bundle_id="$1"
    local override_groups="$2"
    
    log_info "Listing keychain items for: $bundle_id"
    
    local app_binary
    app_binary=$(find_app_executable "$bundle_id") || {
        log_error "Could not find app with bundle ID: $bundle_id"
        return 1
    }
    
    mkdir -p "$TEMP_DIR"
    
    local ent_file="$TEMP_DIR/app_ent.xml"
    extract_entitlements "$app_binary" "$ent_file" || return 1
    
    local keychain_groups
    keychain_groups=$(parse_keychain_groups "$ent_file")

    if [ -n "$override_groups" ]; then
        log_info "Using override keychain groups: $override_groups"
        keychain_groups="$override_groups"
    fi
    
    if [ -z "$keychain_groups" ]; then
        log_info "No keychain-access-groups found in app"
        return 0
    fi
    
    local app_groups
    app_groups=$(parse_app_groups "$ent_file")
    local app_identifier
    app_identifier=$(parse_app_identifier "$ent_file")
    [ -z "$app_identifier" ] && app_identifier="$bundle_id"
    
    # Detect system/Apple app
    local source_ent_for_system=""
    if echo "$app_binary" | grep -q "^/Applications/"; then
        source_ent_for_system="$ent_file"
    elif echo "$app_identifier" | grep -q "^com\.apple\."; then
        source_ent_for_system="$ent_file"
    fi
    
    local helper_ent="$TEMP_DIR/helper_ent.plist"
    generate_helper_entitlements "$keychain_groups" "$app_groups" "$helper_ent" "$app_identifier" "$source_ent_for_system"
    
    # Prepare working copy
    local working_helper="$TEMP_DIR/backup_helper"
    if ! cp "$HELPER_TOOL_PATH" "$working_helper"; then
        log_error "Failed to copy helper"
        return 1
    fi
    chmod 755 "$working_helper"
    
    resign_helper "$helper_ent" "$working_helper" || return 1
    
    "$working_helper" --action list --groups "$keychain_groups"
    
    return $?
}

# === Entry Point ===

print_usage() {
    echo "Usage: $0 <action> <bundleID> [options]"
    echo ""
    echo "Actions:"
    echo "  backup <bundleID> <backup_file>   Backup keychain to file"
    echo "  restore <bundleID> <backup_file>  Restore keychain from file"
    echo "  wipe <bundleID>                   Delete all keychain items"
    echo "  list <bundleID>                   List keychain items"
    echo ""
    echo "Options:"
    echo "  --overwrite   For restore: replace existing items"
    echo "  --verbose     Show detailed output"
    echo ""
    echo "Example:"
    echo "  $0 backup com.game.app /var/tmp/game_keychain.plist"
    echo "  $0 restore com.game.app /var/tmp/game_keychain.plist --overwrite"
}

# Check helper tool exists
if [ ! -x "$HELPER_TOOL_PATH" ]; then
    log_error "KeychainHelper not found at: $HELPER_TOOL_PATH"
    log_error "Please ensure the WeaponX package is properly installed"
    exit 1
fi

# Parse global options
while [[ "$1" == --* ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Require at least action and bundle ID
if [ $# -lt 2 ]; then
    print_usage
    exit 1
fi

ACTION="$1"
BUNDLE_ID="$2"
shift 2

case "$ACTION" in
    backup)
        if [ -z "$1" ]; then
            log_error "Backup file path required"
            print_usage
            exit 1
        fi
        shift_file="$1"
        shift
        # Parse optional args after required ones
        while [[ "$1" == --* ]]; do
            case "$1" in
                --groups)
                    OVERRIDE_KEYCHAIN_GROUPS="$2"
                    shift 2
                    ;;
                --groups=*)
                    OVERRIDE_KEYCHAIN_GROUPS="${1#*=}"
                    shift 1
                    ;;
                *)
                    break
                    ;;
            esac
        done
        do_backup "$BUNDLE_ID" "$shift_file" "$OVERRIDE_KEYCHAIN_GROUPS"
        ;;
    restore)
        if [ -z "$1" ]; then
            log_error "Backup file path required"
            print_usage
            exit 1
        fi
        shift_file="$1"
        shift
        # Next arg may be --overwrite
        restore_overwrite="$1"
        if [ "$restore_overwrite" = "--overwrite" ]; then
            shift
        else
            restore_overwrite=""
        fi
        while [[ "$1" == --* ]]; do
            case "$1" in
                --groups)
                    OVERRIDE_KEYCHAIN_GROUPS="$2"
                    shift 2
                    ;;
                --groups=*)
                    OVERRIDE_KEYCHAIN_GROUPS="${1#*=}"
                    shift 1
                    ;;
                *)
                    break
                    ;;
            esac
        done
        do_restore "$BUNDLE_ID" "$shift_file" "$restore_overwrite" "$OVERRIDE_KEYCHAIN_GROUPS"
        ;;
    wipe)
        while [[ "$1" == --* ]]; do
            case "$1" in
                --groups)
                    OVERRIDE_KEYCHAIN_GROUPS="$2"
                    shift 2
                    ;;
                --groups=*)
                    OVERRIDE_KEYCHAIN_GROUPS="${1#*=}"
                    shift 1
                    ;;
                *)
                    break
                    ;;
            esac
        done
        do_wipe "$BUNDLE_ID" "$OVERRIDE_KEYCHAIN_GROUPS"
        ;;
    list)
        while [[ "$1" == --* ]]; do
            case "$1" in
                --groups)
                    OVERRIDE_KEYCHAIN_GROUPS="$2"
                    shift 2
                    ;;
                --groups=*)
                    OVERRIDE_KEYCHAIN_GROUPS="${1#*=}"
                    shift 1
                    ;;
                *)
                    break
                    ;;
            esac
        done
        do_list "$BUNDLE_ID" "$OVERRIDE_KEYCHAIN_GROUPS"
        ;;
    *)
        log_error "Unknown action: $ACTION"
        print_usage
        exit 1
        ;;
esac

exit $?
