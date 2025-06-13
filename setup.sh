#!/bin/bash

# Ultrasonic Sensor API Server Setup Script with ngrok
# This script sets up the complete environment for the ultrasonic sensor API server with external access via ngrok

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
NGROK_SERVICE_NAME="ultrasonic-ngrok"
USER=$(whoami)
NGROK_AUTH_TOKEN=""  # Will be prompted for

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

get_ngrok_auth_token() {
    echo
    print_status "🌐 Setting up ngrok for external access"
    echo "To use ngrok, you need a free account and auth token from https://ngrok.com"
    echo
    echo "Steps to get your auth token:"
    echo "1. Go to https://ngrok.com and sign up for a free account"
    echo "2. Go to https://dashboard.ngrok.com/get-started/your-authtoken"
    echo "3. Copy your auth token"
    echo
    read -p "Do you have an ngrok auth token? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your ngrok auth token: " NGROK_AUTH_TOKEN
        if [ -z "$NGROK_AUTH_TOKEN" ]; then
            print_warning "No auth token provided. ngrok will be installed but not configured."
            print_warning "You can configure it later using: ngrok config add-authtoken YOUR_TOKEN"
        fi
    else
        print_warning "Skipping ngrok auth token setup."
        print_status "You can set it up later using: ngrok config add-authtoken YOUR_TOKEN"
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
        nano \
        wget \
        unzip
    print_success "System packages installed"
}

install_ngrok() {
    print_status "Installing ngrok..."
    
    # Download and install ngrok
    cd /tmp
    
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "armv7l" ]] || [[ "$ARCH" == "armv6l" ]]; then
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
    else
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
    fi
    
    wget -O ngrok.tgz "$NGROK_URL"
    tar -xzf ngrok.tgz
    sudo mv ngrok /usr/local/bin/
    rm ngrok.tgz
    
    # Configure ngrok if auth token is provided
    if [ -n "$NGROK_AUTH_TOKEN" ]; then
        ngrok config add-authtoken "$NGROK_AUTH_TOKEN"
        print_success "ngrok installed and configured with auth token"
    else
        print_success "ngrok installed (auth token not configured)"
    fi
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
flask-cors==4.0.0
EOF
        
        cat > README.md << EOF
# Ultrasonic Sensor API Server with ngrok

Upload your ultrasonic_server.py file to this directory.

## Quick Start
1. Upload ultrasonic_server.py to $PROJECT_DIR
2. Run: sudo systemctl start $SERVICE_NAME
3. Run: sudo systemctl start $NGROK_SERVICE_NAME
4. Check ngrok URL: $PROJECT_DIR/get_ngrok_url.sh

## Local Access
http://$(hostname -I | awk '{print $1}'):5000

## External Access
Check ngrok URL with: $PROJECT_DIR/get_ngrok_url.sh

## Manual Start
\`\`\`bash
cd $PROJECT_DIR
source venv/bin/activate
sudo python3 ultrasonic_server.py
# In another terminal:
ngrok http 5000
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
        pip install flask RPi.GPIO flask-cors
    fi
    
    print_success "Virtual environment created and packages installed"
}

create_systemd_service() {
    print_status "Creating systemd service..."
    
    # Main API service
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
    
    # ngrok service
    sudo tee /etc/systemd/system/${NGROK_SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=ngrok tunnel for Ultrasonic API
After=network.target ${SERVICE_NAME}.service
Wants=network.target
Requires=${SERVICE_NAME}.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/ngrok http 5000 --log stdout
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
    sudo systemctl enable ${NGROK_SERVICE_NAME}.service
    
    print_success "Systemd services created and enabled"
}

create_management_scripts() {
    print_status "Creating convenience scripts..."
    
    # Create start script
    cat > "$PROJECT_DIR/start.sh" << EOF
#!/bin/bash
cd $PROJECT_DIR
source venv/bin/activate
sudo python3 ultrasonic_server.py
EOF
    chmod +x "$PROJECT_DIR/start.sh"
    
    # Create ngrok URL checker script
    cat > "$PROJECT_DIR/get_ngrok_url.sh" << EOF
#!/bin/bash

echo "🌐 Checking ngrok tunnel status..."
echo

# Check if ngrok service is running
if ! sudo systemctl is-active --quiet $NGROK_SERVICE_NAME; then
    echo "❌ ngrok service is not running"
    echo "Start it with: sudo systemctl start $NGROK_SERVICE_NAME"
    exit 1
fi

# Wait a moment for ngrok to establish tunnel
sleep 2

# Get ngrok URL from API
NGROK_URL=\$(curl -s http://localhost:4040/api/tunnels | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tunnels = data.get('tunnels', [])
    for tunnel in tunnels:
        if tunnel.get('proto') == 'https':
            print(tunnel['public_url'])
            break
    else:
        print('No HTTPS tunnel found')
except:
    print('Error getting tunnel info')
" 2>/dev/null)

if [ -n "\$NGROK_URL" ] && [ "\$NGROK_URL" != "No HTTPS tunnel found" ] && [ "\$NGROK_URL" != "Error getting tunnel info" ]; then
    echo "✅ ngrok tunnel is active!"
    echo "🌐 External URL: \$NGROK_URL"
    echo
    echo "📡 Test your API:"
    echo "   \$NGROK_URL/"
    echo "   \$NGROK_URL/distance"
    echo "   \$NGROK_URL/health"
    echo
    echo "📋 Use this URL to connect from any device on any network!"
else
    echo "❌ Could not get ngrok URL"
    echo "Check ngrok logs: sudo journalctl -u $NGROK_SERVICE_NAME -f"
    echo
    echo "Possible issues:"
    echo "- ngrok auth token not configured"
    echo "- ngrok service not running properly"
    echo "- Network connectivity issues"
fi
EOF
    chmod +x "$PROJECT_DIR/get_ngrok_url.sh"
    
    # Create service management script
    cat > "$PROJECT_DIR/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        sudo systemctl start $SERVICE_NAME
        sudo systemctl start $NGROK_SERVICE_NAME
        echo "Services started"
        sleep 3
        echo "Getting ngrok URL..."
        $PROJECT_DIR/get_ngrok_url.sh
        ;;
    stop)
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl stop $NGROK_SERVICE_NAME
        echo "Services stopped"
        ;;
    restart)
        sudo systemctl restart $SERVICE_NAME
        sudo systemctl restart $NGROK_SERVICE_NAME
        echo "Services restarted"
        sleep 3
        echo "Getting ngrok URL..."
        $PROJECT_DIR/get_ngrok_url.sh
        ;;
    status)
        echo "=== API Service Status ==="
        sudo systemctl status $SERVICE_NAME --no-pager
        echo
        echo "=== ngrok Service Status ==="
        sudo systemctl status $NGROK_SERVICE_NAME --no-pager
        ;;
    logs)
        echo "Choose logs to view:"
        echo "1) API logs"
        echo "2) ngrok logs"
        echo "3) Both"
        read -p "Enter choice (1-3): " choice
        case \$choice in
            1) sudo journalctl -u $SERVICE_NAME -f ;;
            2) sudo journalctl -u $NGROK_SERVICE_NAME -f ;;
            3) sudo journalctl -u $SERVICE_NAME -u $NGROK_SERVICE_NAME -f ;;
            *) echo "Invalid choice" ;;
        esac
        ;;
    url)
        $PROJECT_DIR/get_ngrok_url.sh
        ;;
    enable)
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl enable $NGROK_SERVICE_NAME
        echo "Services enabled for auto-start"
        ;;
    disable)
        sudo systemctl disable $SERVICE_NAME
        sudo systemctl disable $NGROK_SERVICE_NAME
        echo "Services disabled"
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|enable|disable}"
        echo
        echo "Commands:"
        echo "  start    - Start both API and ngrok services"
        echo "  stop     - Stop both services"
        echo "  restart  - Restart both services"
        echo "  status   - Show status of both services"
        echo "  logs     - View service logs"
        echo "  url      - Get current ngrok URL"
        echo "  enable   - Enable auto-start on boot"
        echo "  disable  - Disable auto-start on boot"
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
    python3 -c "import flask_cors; print('Flask-CORS imported successfully')" 2>/dev/null || print_warning "Flask-CORS import failed"
    
    # Try to import RPi.GPIO (might fail on non-Pi systems)
    python3 -c "import RPi.GPIO; print('RPi.GPIO imported successfully')" 2>/dev/null || print_warning "RPi.GPIO import failed (normal on non-Pi systems)"
    
    # Test ngrok
    if command -v ngrok &> /dev/null; then
        print_success "ngrok installed successfully"
    else
        print_error "ngrok installation failed"
    fi
    
    print_success "Installation test completed"
}

display_usage_info() {
    local IP=$(hostname -I | awk '{print $1}')
    
    echo
    print_success "🎉 Setup completed successfully!"
    echo
    echo "📁 Project directory: $PROJECT_DIR"
    echo "🏠 Local API URL: http://$IP:5000"
    echo "🌐 External access: via ngrok (see commands below)"
    echo
    echo "📋 Next steps:"
    echo "  1. If you haven't already, upload your ultrasonic_server.py file to:"
    echo "     $PROJECT_DIR"
    echo
    if [ -z "$NGROK_AUTH_TOKEN" ]; then
        echo "  2. Configure ngrok auth token:"
        echo "     ngrok config add-authtoken YOUR_TOKEN"
        echo "     (Get your token from https://dashboard.ngrok.com/get-started/your-authtoken)"
        echo
    fi
    echo "  3. Wire your HC-SR04 sensor:"
    echo "     VCC  → 5V (Pin 2 or 4)"
    echo "     GND  → Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39)"
    echo "     Trig → GPIO 18 (Pin 12)"
    echo "     Echo → GPIO 24 (Pin 18)"
    echo
    echo "🚀 Management commands:"
    echo "  Start both services:  $PROJECT_DIR/manage.sh start"
    echo "  Stop both services:   $PROJECT_DIR/manage.sh stop"
    echo "  Check status:         $PROJECT_DIR/manage.sh status"
    echo "  Get ngrok URL:        $PROJECT_DIR/manage.sh url"
    echo "  View logs:            $PROJECT_DIR/manage.sh logs"
    echo "  Manual start:         $PROJECT_DIR/start.sh"
    echo
    echo "🔧 Individual service commands:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl start $NGROK_SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl stop $NGROK_SERVICE_NAME"
    echo
    echo "📡 Test API endpoints:"
    echo "  Local:  curl http://localhost:5000/distance"
    echo "  Remote: Use the ngrok URL from 'manage.sh url'"
    echo
    echo "🌐 Getting your external URL:"
    echo "  After starting services, run: $PROJECT_DIR/manage.sh url"
    echo "  This URL will work from anywhere in the world!"
    echo
    if [ -z "$REPO_URL" ]; then
        print_warning "Remember to upload your ultrasonic_server.py file before starting the service!"
    fi
    
    if [ -z "$NGROK_AUTH_TOKEN" ]; then
        print_warning "Remember to configure your ngrok auth token for external access!"
    fi
}

# Main execution
main() {
    echo "🚀 Ultrasonic Sensor API Server Setup with ngrok"
    echo "==============================================="
    
    # Parse arguments
    if [ $# -gt 0 ]; then
        REPO_URL=$1
        print_status "Repository URL provided: $REPO_URL"
    fi
    
    # Pre-flight checks
    check_root
    check_raspberry_pi
    get_ngrok_auth_token
    
    # Setup steps
    update_system
    install_dependencies
    install_ngrok
    setup_project_directory
    clone_or_download_code
    setup_virtual_environment
    create_systemd_service
    create_management_scripts
    setup_gpio_permissions
    test_installation
    
    # Display final information
    display_usage_info
    
    echo
    print_success "Setup script completed! 🎉"
    
    if [ -n "$REPO_URL" ] && [ -f "$PROJECT_DIR/ultrasonic_server.py" ]; then
        echo
        read -p "Would you like to start both services now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl start $SERVICE_NAME
            sleep 2
            sudo systemctl start $NGROK_SERVICE_NAME
            sleep 3
            echo
            print_status "Services started! Getting your external URL..."
            "$PROJECT_DIR/get_ngrok_url.sh"
        fi
    fi
}

# Run main function
main "$@"