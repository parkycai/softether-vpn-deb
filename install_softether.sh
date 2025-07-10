#!/bin/bash

# Script to download and install SoftEther VPN components from GitHub repository
# Repository: https://github.com/parkycai/softether-vpn-deb
# Downloads .deb files from the latest GitHub release via jsDelivr CDN or GitHub assets
# Downloads .service files via jsDelivr CDN or GitHub raw
# Extracts version exactly from release tag (e.g., 5.02.5187 from v5.02.5187-deb)
# Extracts .deb filenames and URLs from browser_download_url matching softether-${component}
# Automatically installs common and vpncmd, allows user to select vpnclient, vpnserver, vpnclient+vpnserver, or vpnbridge
# Installs common first, uninstalls it last to respect dependencies
# Displays version number from release tag in the menu
# Supports uninstalling all components and services
# Sets up and starts corresponding systemd services for installations

# Exit on error
set -e

# Check if running with bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash, not sh or another shell."
    echo "Run as: sudo bash install_softether.sh or sudo ./install_softether.sh"
    exit 1
fi

# Check Bash version (arrays require Bash 3.0+, associative arrays require 4.0+)
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: Bash version 4.0 or higher is required. Current version: $BASH_VERSION"
    exit 1
fi

# Base URLs for downloads
REPO_URL_JSDELIVR="https://cdn.jsdelivr.net/gh/parkycai/softether-vpn-deb@latest"
REPO_URL_GITHUB="https://raw.githubusercontent.com/parkycai/softether-vpn-deb/main"
# GitHub API for fetching release information
RELEASE_API_URL="https://api.github.com/repos/parkycai/softether-vpn-deb/releases/latest"
# jsDelivr base URL for release assets
JSDELIVR_RELEASE_BASE="https://cdn.jsdelivr.net/gh/parkycai/softether-vpn-deb@packages"

# Directory to store downloaded files
DOWNLOAD_DIR="/tmp/softether-install"

# List of components for reference
COMPONENTS=("vpnclient" "vpnserver" "vpnbridge")

# Associative arrays to store detected .deb package names, versions, and URLs
declare -A DEB_PACKAGES
declare -A DEB_VERSIONS
declare -A DEB_URLS

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Function to create download directory
setup_download_dir() {
    mkdir -p "$DOWNLOAD_DIR"
    cd "$DOWNLOAD_DIR"
}

# Function to download a file with curl
download_file() {
    local file_url="$1"
    local file_name="$2"
    echo "Downloading $file_name..."

    # Use curl with --fail option to return non-zero exit code on HTTP errors
    # --connect-timeout and --max-time options are added to handle network timeouts
    curl -s -L --fail --connect-timeout 20 --max-time 600 -o "$file_name" "$file_url"
    local curl_exit_code=$?

    case $curl_exit_code in
        0)
            echo "Download of $file_name completed successfully."
            ;;
        6)
            echo "Error: Could not resolve host. Check your DNS settings or the URL ($file_url)."
            exit 1
            ;;
        7)
            echo "Error: Failed to connect to the server. Check your network connection or the server status ($file_url)."
            exit 1
            ;;
        22)
            echo "Error: HTTP request returned a 404 (Not Found) status for $file_url."
            exit 1
            ;;
        28)
            echo "Error: Connection timed out while downloading $file_name from $file_url."
            exit 1
            ;;
        *)
            echo "Error: An unknown error occurred while downloading $file_name from $file_url. Curl exit code: $curl_exit_code"
            exit 1
            ;;
    esac
}

# Function to fetch .deb package names and version from GitHub Release API
fetch_deb_packages() {
    echo "Fetching package names and version from GitHub Release API ($RELEASE_API_URL)..."
    # Temporary file for API response
    local temp_json="/tmp/repo_release.json"
    if ! curl -s -L "$RELEASE_API_URL" -o "$temp_json"; then
        echo "Failed to fetch release information from GitHub API"
        rm -f "$temp_json"
        exit 1
    fi

    # Extract the latest release tag (e.g., v5.02.5187-deb)
    local release_tag
    release_tag=$(grep -o '"tag_name":\s*"[^"]*"' "$temp_json" | sed 's/"tag_name":\s*"\(.*\)"/\1/' | head -n 1)
    if [ -z "$release_tag" ]; then
        echo "Failed to extract release tag"
        rm -f "$temp_json"
        exit 1
    fi

    # Extract version number (e.g., 5.02.5187 from v5.02.5187-deb)
    local version
    version=$(echo "$release_tag" | sed -n 's/v\([^ ]*\)-deb/\1/p')
    if [ -z "$version" ]; then
        echo "Failed to extract version from tag $release_tag"
        rm -f "$temp_json"
        exit 1
    fi

    # Parse .deb files and URLs for each component from release assets
    for component in "common" "vpncmd" "${COMPONENTS[@]}"; do
        # Extract browser_download_url for softether-${component}
        local download_url
        download_url=$(grep '"browser_download_url":.*softether-'${component}'_' "$temp_json" | sed 's/.*"browser_download_url":\s*"\(.*\)"/\1/' | head -n 1)
        if [ -z "$download_url" ]; then
            echo "No .deb package found for softether-${component} in release $release_tag"
            rm -f "$temp_json"
            exit 1
        fi
        # Extract filename from browser_download_url
        local deb_file
        deb_file=$(echo "$download_url" | sed 's|.*/\([^/]*\)$|\1|')
        if [ -z "$deb_file" ]; then
            echo "Failed to extract filename for softether-${component} from $download_url"
            rm -f "$temp_json"
            exit 1
        fi
        DEB_PACKAGES["$component"]="$deb_file"
        DEB_VERSIONS["$component"]="$version"
        # Set jsDelivr URL as primary, GitHub as backup
        DEB_URLS["$component"]="jsdelivr:${JSDELIVR_RELEASE_BASE}-${version}/${deb_file}|github:${download_url}"
    done

    rm -f "$temp_json"
}

# Function to display menu and get user selection
display_menu() {
    echo "Select SoftEther VPN components to install (common v${DEB_VERSIONS[common]} and vpncmd v${DEB_VERSIONS[vpncmd]} will be installed automatically):"
    echo "1) vpnclient (v${DEB_VERSIONS[vpnclient]})"
    echo "2) vpnserver (v${DEB_VERSIONS[vpnserver]})"
    echo "3) vpnclient (v${DEB_VERSIONS[vpnclient]})+vpnserver (v${DEB_VERSIONS[vpnserver]})"
    echo "4) vpnbridge (v${DEB_VERSIONS[vpnbridge]})"
    echo "5) Uninstall All"
    echo "6) Exit without installing"
    echo ""
    echo "Enter the number of your choice (e.g., '1' for vpnclient):"
    if [ -e /dev/tty ]; then
        read -r choice < /dev/tty
    else
        echo "Error: No terminal available for interactive input. Please run interactively."
        exit 1
    fi
}

# Function to validate and process user input
get_selected_components() {
    local input="$1"
    selected_components=()
    case $input in
        1) selected_components=("vpnclient");;
        2) selected_components=("vpnserver");;
        3) selected_components=("vpnclient" "vpnserver");;
        4) selected_components=("vpnbridge");;
        5) uninstall_all; exit 0;;
        6) echo "Exiting without installing."; exit 0;;
        *) echo "Invalid choice: $input"; exit 1;;
    esac
}

# Function to uninstall all SoftEther VPN components and services
uninstall_all() {
    echo "Uninstalling all SoftEther VPN components and services..."
    # Stop and disable services if they exist
    for component in "${COMPONENTS[@]}"; do
        if systemctl is-active --quiet "softether-${component}.service"; then
            echo "Stopping softether-${component}.service..."
            systemctl stop "softether-${component}.service"
        fi
        if systemctl is-enabled --quiet "softether-${component}.service"; then
            echo "Disabling softether-${component}.service..."
            systemctl disable "softether-${component}.service"
        fi
        # Remove service file
        if [ -f "/etc/systemd/system/softether-${component}.service" ]; then
            echo "Removing softether-${component}.service..."
            rm -f "/etc/systemd/system/softether-${component}.service"
        fi
    done
    # Reload systemd daemon
    systemctl daemon-reload

    # Uninstall all packages, common last
    for component in "${COMPONENTS[@]}" "vpncmd" "common"; do
        # Get package name without version for apt remove
        local pkg_name="softether-${component}"
        if dpkg -l | grep -q "$pkg_name"; then
            echo "Removing $pkg_name..."
            apt-get remove -y --purge "$pkg_name"
        fi
    done
    # Clean up any residual dependencies
    apt-get autoremove -y
    echo "Uninstallation completed successfully!"
}

# Function to download deb packages and service files
download_components() {
    # Download mandatory .deb components (common and vpncmd)
    echo "Downloading mandatory components (common and vpncmd) from release..."
    for component in "common" "vpncmd"; do
        local url_pair="${DEB_URLS[$component]}"
        local jsdelivr_url="${url_pair#jsdelivr:}"
        jsdelivr_url="${jsdelivr_url%%|*}"
        local github_url="${url_pair##*|github:}"
        if ! download_file "$jsdelivr_url" "${DEB_PACKAGES[$component]}"; then
            echo "jsDelivr CDN failed for ${DEB_PACKAGES[$component]}, falling back to GitHub..."
            download_file "$github_url" "${DEB_PACKAGES[$component]}"
        fi
    done

    # Download selected components' .deb files
    for component in "${selected_components[@]}"; do
        local url_pair="${DEB_URLS[$component]}"
        local jsdelivr_url="${url_pair#jsdelivr:}"
        jsdelivr_url="${jsdelivr_url%%|*}"
        local github_url="${url_pair##*|github:}"
        if ! download_file "$jsdelivr_url" "${DEB_PACKAGES[$component]}"; then
            echo "jsDelivr CDN failed for ${DEB_PACKAGES[$component]}, falling back to GitHub..."
            download_file "$github_url" "${DEB_PACKAGES[$component]}"
        fi
    done

    # Download selected components' .service files from repository (jsDelivr or GitHub)
    local repo_url="$REPO_URL_JSDELIVR"
    echo "Downloading .service files from jsDelivr CDN ($REPO_URL_JSDELIVR)..."
    for component in "${selected_components[@]}"; do
        if ! download_file "${repo_url}/softether-${component}.service" "softether-${component}.service"; then
            echo "jsDelivr CDN failed for softether-${component}.service, falling back to GitHub ($REPO_URL_GITHUB)..."
            repo_url="$REPO_URL_GITHUB"
            download_file "${repo_url}/softether-${component}.service" "softether-${component}.service"
        fi
    done
}

# Function to install deb packages
install_deb_packages() {
    echo "Installing deb packages..."
    # Install common first
    dpkg -i "${DEB_PACKAGES[common]}" || apt-get install -f -y
    # Install vpncmd second
    dpkg -i "${DEB_PACKAGES[vpncmd]}" || apt-get install -f -y
    # Install selected components
    for component in "${selected_components[@]}"; do
        dpkg -i "${DEB_PACKAGES[$component]}" || apt-get install -f -y
    done
}

# Function to set up systemd services
setup_services() {
    for component in "${selected_components[@]}"; do
        echo "Setting up service for $component..."
        # Move service file to systemd directory
        mv "softether-${component}.service" "/etc/systemd/system/softether-${component}.service"
        # Reload systemd to recognize new service
        systemctl daemon-reload
        # Enable and start the service
        systemctl enable "softether-${component}.service"
        systemctl start "softether-${component}.service"
        # Check service status
        systemctl status "softether-${component}.service" --no-pager
    done
}

# Main execution
check_root
fetch_deb_packages
display_menu
get_selected_components "$choice"
if [ ${#selected_components[@]} -gt 0 ]; then
    setup_download_dir
    download_components
    install_deb_packages
    setup_services
    echo "Installation and service setup completed successfully!"
    echo "You can configure SoftEther VPN using vpncmd or SoftEther VPN Server Manager."
    echo "For more information, visit: https://www.softether.org/"
    # Clean up
    cd /tmp
    rm -rf "$DOWNLOAD_DIR"
fi
