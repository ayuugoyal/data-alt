#!/bin/bash

# Ultrasonic Sensor API Server Setup Script
# This script sets up the complete environment for the ultrasonic sensor API server

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="ultrasonic-api"
PROJECT_DIR="$HOME/$PROJECT_NAME"
REPO_URL=""  # Will be set if provided as argument
SERVICE_NAME="ultrasonic-api"
USER=$(whoami)

# Functions
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

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user."
        print_status "The script will use sudo when needed."
        exit 1
    fi
}

check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        print_warning "This doesn't appear to be a Raspberry Pi. GPIO functionality may not work."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

update_system() {
    print_status "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    print_success "System updated successfully"
}

install_dependencies() {
    print_status "Installing required system packages..."
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-rpi.gpio \
        git \
        curl \
        nano
    print_success "System packages installed"
}

setup_project_directory() {
    print_status "Setting up project directory..."
    
    # Remove existing directory if it exists
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "Directory $PROJECT_DIR already exists"
        read -p "Remove and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR"
        else
            print_error "Setup cancelled"
            exit 1
        fi
    fi
    
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    print_success "Project directory created: $PROJECT_DIR"
}

clone_or_download_code() {
    print_status "Setting up project code..."
    
    if [ -n "$REPO_URL" ]; then
        print_status "Cloning from repository: $REPO_URL"
        git clone "$REPO_URL" .
        print_success "Repository cloned successfully"
    else
        print_status "No repository URL provided. You'll need to upload your code manually."
        print_status "Creating placeholder files..."
        
        # Create placeholder files
        cat > requirements.txt << EOF
flask==2.3.3
RPi.GPIO==0.7.1
EOF
        
        cat > README.md << EOF
# Ultrasonic Sensor API Server

Upload your ultrasonic_server.py file to this directory.

## Quick Start
1. Upload ultrasonic_server.py to $PROJECT_DIR
2. Run: sudo systemctl start $SERVICE_NAME
3. Access API at: http://$(hostname -I | awk '{print $1}'):5000

## Manual Start
\`\`\`bash
cd $PROJECT_DIR
source venv/bin/activate
sudo python3 ultrasonic_server.py
\`\`\`
EOF
        
        print_warning "Please upload your ultrasonic_server.py file to: $PROJECT_DIR"
    fi
}

setup_virtual_environment() {
    print_status "Creating Python virtual environment..."
    cd "$PROJECT_DIR"
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install requirements
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        pip install flask RPi.GPIO
    fi
    
    print_success "Virtual environment created and packages installed"
}

create_systemd_service() {
    print_status "Creating systemd service..."
    
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Ultrasonic Sensor API Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/ultrasonic_server.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service
    
    print_success "Systemd service created and enabled"
}

create_start_script() {
    print_status "Creating convenience scripts..."
    
    # Create start script
    cat > "$PROJECT_DIR/start.sh" << EOF
#!/bin/bash
cd $PROJECT_DIR
source venv/bin/activate
sudo python3 ultrasonic_server.py
EOF
    chmod +x "$PROJECT_DIR/start.sh"
    
    # Create service management script
    cat > "$PROJECT_DIR/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        sudo systemctl start $SERVICE_NAME
        echo "Service started"
        ;;
    stop)
        sudo systemctl stop $SERVICE_NAME
        echo "Service stopped"
        ;;
    restart)
        sudo systemctl restart $SERVICE_NAME
        echo "Service restarted"
        ;;
    status)
        sudo systemctl status $SERVICE_NAME
        ;;
    logs)
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    enable)
        sudo systemctl enable $SERVICE_NAME
        echo "Service enabled for auto-start"
        ;;
    disable)
        sudo systemctl disable $SERVICE_NAME
        echo "Service disabled"
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|enable|disable}"
        exit 1
        ;;
esac
EOF
    chmod +x "$PROJECT_DIR/manage.sh"
    
    print_success "Management scripts created"
}

setup_gpio_permissions() {
    print_status "Setting up GPIO permissions..."
    
    # Add user to gpio group if it exists
    if getent group gpio > /dev/null 2>&1; then
        sudo usermod -a -G gpio $USER
        print_success "User added to gpio group"
    else
        print_warning "GPIO group not found. Service will run as root."
    fi
}

test_installation() {
    print_status "Testing installation..."
    
    # Check if Python can import required modules
    cd "$PROJECT_DIR"
    source venv/bin/activate
    
    python3 -c "import flask; print('Flask:', flask.__version__)" 2>/dev/null || print_error "Flask import failed"
    
    # Try to import RPi.GPIO (might fail on non-Pi systems)
    python3 -c "import RPi.GPIO; print('RPi.GPIO imported successfully')" 2>/dev/null || print_warning "RPi.GPIO import failed (normal on non-Pi systems)"
    
    print_success "Installation test completed"
}

display_usage_info() {
    local IP=$(hostname -I | awk '{print $1}')
    
    echo
    print_success "🎉 Setup completed successfully!"
    echo
    echo "📁 Project directory: $PROJECT_DIR"
    echo "🌐 API will be available at: http://$IP:5000"
    echo
    echo "📋 Next steps:"
    echo "  1. If you haven't already, upload your ultrasonic_server.py file to:"
    echo "     $PROJECT_DIR"
    echo
    echo "  2. Wire your HC-SR04 sensor:"
    echo "     VCC  → 5V (Pin 2 or 4)"
    echo "     GND  → Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39)"
    echo "     Trig → GPIO 18 (Pin 12)"
    echo "     Echo → GPIO 24 (Pin 18)"
    echo
    echo "🚀 Management commands:"
    echo "  Start service:    $PROJECT_DIR/manage.sh start"
    echo "  Stop service:     $PROJECT_DIR/manage.sh stop"
    echo "  Check status:     $PROJECT_DIR/manage.sh status"
    echo "  View logs:        $PROJECT_DIR/manage.sh logs"
    echo "  Manual start:     $PROJECT_DIR/start.sh"
    echo
    echo "🔧 Service commands:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo
    echo "📡 Test API endpoints:"
    echo "  curl http://localhost:5000/"
    echo "  curl http://localhost:5000/distance"
    echo "  curl http://localhost:5000/health"
    echo
    if [ -z "$REPO_URL" ]; then
        print_warning "Remember to upload your ultrasonic_server.py file before starting the service!"
    fi
}

# Main execution
main() {
    echo "🚀 Ultrasonic Sensor API Server Setup"
    echo "======================================"
    
    # Parse arguments
    if [ $# -gt 0 ]; then
        REPO_URL=$1
        print_status "Repository URL provided: $REPO_URL"
    fi
    
    # Pre-flight checks
    check_root
    check_raspberry_pi
    
    # Setup steps
    update_system
    install_dependencies
    setup_project_directory
    clone_or_download_code
    setup_virtual_environment
    create_systemd_service
    create_start_script
    setup_gpio_permissions
    test_installation
    
    # Display final information
    display_usage_info
    
    echo
    print_success "Setup script completed! 🎉"
    
    if [ -n "$REPO_URL" ] && [ -f "$PROJECT_DIR/ultrasonic_server.py" ]; then
        echo
        read -p "Would you like to start the service now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl start $SERVICE_NAME
            sleep 2
            sudo systemctl status $SERVICE_NAME --no-pager
        fi
    fi
}

# Run main function
main "$@"