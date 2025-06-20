#!/bin/bash

# Complete Azure CLI and Dev Tunnels Cleanup Script
# This script removes all Azure CLI, Dev Tunnels, and related components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to stop and remove systemd services
cleanup_systemd_services() {
    print_header "Cleaning up systemd services"
    
    # List of possible service names
    SERVICES=(
        "multi-sensor-api"
        "multi-sensor-tunnel"
        "azure-dev-tunnel"
        "devtunnel"
    )
    
    for service in "${SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "${service}.service"; then
            print_status "Stopping and disabling ${service}.service"
            sudo systemctl stop "${service}.service" 2>/dev/null || true
            sudo systemctl disable "${service}.service" 2>/dev/null || true
            sudo rm -f "/etc/systemd/system/${service}.service"
            print_success "Removed ${service}.service"
        fi
    done
    
    # Reload systemd
    sudo systemctl daemon-reload
    sudo systemctl reset-failed 2>/dev/null || true
    print_success "Systemd services cleaned up"
}

# Function to remove Azure CLI
remove_azure_cli() {
    print_header "Removing Azure CLI"
    
    # Method 1: Remove via apt if installed via repository
    if dpkg -l | grep -q azure-cli; then
        print_status "Removing Azure CLI via apt..."
        sudo apt remove --purge -y azure-cli 2>/dev/null || true
        print_success "Azure CLI removed via apt"
    fi
    
    # Method 2: Remove via pip if installed via pip
    if pip3 list | grep -q azure-cli; then
        print_status "Removing Azure CLI via pip3..."
        pip3 uninstall -y azure-cli 2>/dev/null || true
        print_success "Azure CLI removed via pip3"
    fi
    
    # Method 3: Remove via snap if installed via snap
    if snap list | grep -q azure-cli; then
        print_status "Removing Azure CLI via snap..."
        sudo snap remove azure-cli 2>/dev/null || true
        print_success "Azure CLI removed via snap"
    fi
    
    # Remove Azure CLI repository and GPG key
    if [ -f "/etc/apt/sources.list.d/azure-cli.list" ]; then
        print_status "Removing Azure CLI repository..."
        sudo rm -f /etc/apt/sources.list.d/azure-cli.list
        print_success "Azure CLI repository removed"
    fi
    
    # Remove Microsoft GPG key
    if [ -f "/etc/apt/trusted.gpg.d/microsoft.gpg" ]; then
        sudo rm -f /etc/apt/trusted.gpg.d/microsoft.gpg
        print_success "Microsoft GPG key removed"
    fi
    
    # Remove any Azure CLI binaries from /usr/local/bin
    sudo rm -f /usr/local/bin/az 2>/dev/null || true
    
    print_success "Azure CLI cleanup completed"
}

# Function to remove Azure Dev Tunnels
remove_azure_dev_tunnels() {
    print_header "Removing Azure Dev Tunnels"
    
    # Remove devtunnel binary
    if [ -f "/usr/local/bin/devtunnel" ]; then
        print_status "Removing devtunnel binary..."
        sudo rm -f /usr/local/bin/devtunnel
        print_success "devtunnel binary removed"
    fi
    
    # Remove devtunnel from other possible locations
    sudo rm -f /usr/bin/devtunnel 2>/dev/null || true
    sudo rm -f /bin/devtunnel 2>/dev/null || true
    
    print_success "Azure Dev Tunnels cleanup completed"
}

# Function to remove Azure configuration directories
remove_azure_config() {
    print_header "Removing Azure configuration directories"
    
    # Remove Azure CLI config directory
    if [ -d "$HOME/.azure" ]; then
        print_status "Removing Azure CLI configuration..."
        rm -rf "$HOME/.azure"
        print_success "Azure CLI configuration removed"
    fi
    
    # Remove Dev Tunnels config directory
    if [ -d "$HOME/.devtunnel" ]; then
        print_status "Removing Dev Tunnels configuration..."
        rm -rf "$HOME/.devtunnel"
        print_success "Dev Tunnels configuration removed"
    fi
    
    # Remove any cached Azure data
    rm -rf "$HOME/.cache/azure-cli" 2>/dev/null || true
    rm -rf "$HOME/.azure-cli" 2>/dev/null || true
    
    print_success "Azure configuration cleanup completed"
}

# Function to remove Azure-related Python packages
remove_azure_python_packages() {
    print_header "Removing Azure-related Python packages"
    
    # List of Azure-related packages
    AZURE_PACKAGES=(
        "azure-cli"
        "azure-cli-core"
        "azure-cli-telemetry"
        "azure-common"
        "azure-core"
        "azure-identity"
        "azure-mgmt-core"
        "azure-storage-blob"
        "azure-storage-common"
        "azure-devtools"
        "knack"
        "msrest"
        "msrestazure"
    )
    
    for package in "${AZURE_PACKAGES[@]}"; do
        if pip3 list | grep -q "$package"; then
            print_status "Removing Python package: $package"
            pip3 uninstall -y "$package" 2>/dev/null || true
        fi
    done
    
    print_success "Azure Python packages cleanup completed"
}

# Function to clean up package cache
cleanup_package_cache() {
    print_header "Cleaning up package cache"
    
    # Update package lists
    sudo apt update
    
    # Remove unnecessary packages
    sudo apt autoremove -y
    
    # Clean package cache
    sudo apt autoclean
    
    print_success "Package cache cleaned up"
}

# Function to remove old project directories
cleanup_old_projects() {
    print_header "Cleaning up old project directories"
    
    # Ask user if they want to remove old multi-sensor-api directory
    if [ -d "$HOME/multi-sensor-api" ]; then
        echo
        print_warning "Found existing multi-sensor-api directory at: $HOME/multi-sensor-api"
        read -p "Do you want to remove it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/multi-sensor-api"
            print_success "Old project directory removed"
        else
            print_status "Keeping existing project directory"
        fi
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_header "Verifying cleanup"
    
    # Check if Azure CLI is still installed
    if command -v az &> /dev/null; then
        print_warning "Azure CLI still found in PATH"
    else
        print_success "Azure CLI not found in PATH"
    fi
    
    # Check if devtunnel is still installed
    if command -v devtunnel &> /dev/null; then
        print_warning "devtunnel still found in PATH"
    else
        print_success "devtunnel not found in PATH"
    fi
    
    # Check for remaining Azure processes
    if pgrep -f "azure\|devtunnel" > /dev/null; then
        print_warning "Azure-related processes still running"
        echo "Running processes:"
        pgrep -f "azure\|devtunnel" -l || true
    else
        print_success "No Azure-related processes running"
    fi
    
    # Check for remaining systemd services
    if systemctl list-unit-files | grep -E "(azure|devtunnel|multi-sensor)" > /dev/null; then
        print_warning "Some systemd services might still exist:"
        systemctl list-unit-files | grep -E "(azure|devtunnel|multi-sensor)" || true
    else
        print_success "No Azure-related systemd services found"
    fi
}

# Function to display final status
display_final_status() {
    print_header "Cleanup Summary"
    
    echo "✅ Systemd services removed"
    echo "✅ Azure CLI removed"
    echo "✅ Azure Dev Tunnels removed"
    echo "✅ Configuration directories cleaned"
    echo "✅ Python packages cleaned"
    echo "✅ Package cache cleaned"
    echo
    print_success "Azure CLI and Dev Tunnels completely removed!"
    echo
    print_status "Your system is now clean and ready for the Cloudflare Tunnel setup."
    echo
    echo "Next steps:"
    echo "1. Ensure server.py and requirements.txt are in your home directory"
    echo "2. Run the Cloudflare Tunnel setup script"
    echo "3. Create a free Cloudflare account if you haven't already"
}

# Main execution
main() {
    echo "🧹 Complete Azure CLI and Dev Tunnels Cleanup"
    echo "=============================================="
    echo
    print_warning "This script will completely remove:"
    echo "• Azure CLI and all related packages"
    echo "• Azure Dev Tunnels (devtunnel)"
    echo "• All Azure configuration files"
    echo "• Related systemd services"
    echo "• Python packages"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled"
        exit 0
    fi
    
    # Execute cleanup steps
    cleanup_systemd_services
    remove_azure_cli
    remove_azure_dev_tunnels
    remove_azure_config
    remove_azure_python_packages
    cleanup_package_cache
    cleanup_old_projects
    verify_cleanup
    display_final_status
    
    echo
    print_success "Cleanup completed successfully! 🎉"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user."
    print_status "The script will use sudo when needed."
    exit 1
fi

# Run main function
main "$@"