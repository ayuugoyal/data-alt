#!/bin/bash

# Multi-Sensor FastAPI Server Setup Script with Cloudflare Tunnel
# This script sets up the complete environment for the multi-sensor FastAPI server with external access via Cloudflare Tunnel

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="multi-sensor-api"
PROJECT_DIR="$HOME/$PROJECT_NAME"
SERVICE_NAME="multi-sensor-api"
TUNNEL_SERVICE_NAME="cloudflared-tunnel"
USER=$(whoami)
TUNNEL_NAME="multi-sensor-tunnel"
CLOUDFLARE_CONFIG_DIR="$HOME/.cloudflared"

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

get_cloudflare_info() {
    echo
    print_status "🌐 Setting up Cloudflare Tunnel for external access"
    echo
    echo "Cloudflare Tunnel provides secure access to local applications via Cloudflare's network."
    echo "You'll need a Cloudflare account (free) to use this service."
    echo
    echo "Benefits of Cloudflare Tunnel:"
    echo "• Completely free"
    echo "• No port forwarding needed"
    echo "• Built-in DDoS protection"
    echo "• Custom domain support"
    echo "• Excellent performance and reliability"
    echo
    read -p "Do you have a Cloudflare account? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "You'll need to create a free Cloudflare account."
        print_status "Visit: https://dash.cloudflare.com/sign-up to create a free account"
        echo
        read -p "Press Enter after creating your Cloudflare account..."
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
        python3-dev \
        build-essential \
        git \
        curl \
        nano \
        wget \
        unzip \
        jq \
        lsb-release
    print_success "System packages installed"
}

install_cloudflared() {
    print_status "Installing Cloudflare Tunnel (cloudflared)..."
    
    # Add Cloudflare GPG key
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    
    # Add Cloudflare repository
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bullseye main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
    
    # Update package list and install cloudflared
    sudo apt update
    sudo apt install -y cloudflared
    
    print_success "Cloudflared installed successfully"
    
    # Test installation
    if cloudflared --version > /dev/null 2>&1; then
        print_success "Cloudflared is working"
        cloudflared --version
    else
        print_error "Cloudflared installation failed"
        exit 1
    fi
}

setup_cloudflare_auth() {
    print_status "Setting up Cloudflare authentication..."
    
    echo
    echo "You need to authenticate with Cloudflare to create tunnels."
    echo "This will open a browser window for authentication."
    echo
    read -p "Proceed with Cloudflare login? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting Cloudflare authentication..."
        echo "If you're using SSH, copy and paste the URL that appears into your browser."
        
        if cloudflared tunnel login; then
            print_success "Cloudflare authentication successful"
        else
            print_error "Cloudflare authentication failed"
            print_status "You can authenticate later using: cloudflared tunnel login"
            exit 1
        fi
    else
        print_warning "Skipping Cloudflare login. You'll need to authenticate later."
        print_status "Run this command later: cloudflared tunnel login"
        exit 1
    fi
}

check_project_files() {
    print_status "Checking for project files..."
    
    if [ ! -f "$HOME/server.py" ] && [ ! -f "$HOME/requirements.txt" ]; then
        print_error "server.py and requirements.txt not found in $HOME"
        print_status "Please ensure both files are in your home directory before running this script."
        exit 1
    fi
    
    if [ ! -f "$HOME/server.py" ]; then
        print_error "server.py not found in $HOME"
        exit 1
    fi
    
    if [ ! -f "$HOME/requirements.txt" ]; then
        print_error "requirements.txt not found in $HOME"
        exit 1
    fi
    
    print_success "Project files found"
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
    
    # Copy files from home directory
    cp "$HOME/server.py" "$PROJECT_DIR/"
    cp "$HOME/requirements.txt" "$PROJECT_DIR/"
    
    print_success "Project directory created and files copied: $PROJECT_DIR"
}

setup_virtual_environment() {
    print_status "Creating Python virtual environment..."
    cd "$PROJECT_DIR"
    python3 -m venv venv
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install requirements
    pip install -r requirements.txt
    
    print_success "Virtual environment created and packages installed"
}

create_cloudflare_tunnel() {
    print_status "Creating Cloudflare Tunnel..."
    
    # Create tunnel
    if cloudflared tunnel create "$TUNNEL_NAME"; then
        print_success "Cloudflare Tunnel '$TUNNEL_NAME' created successfully"
    else
        print_error "Failed to create Cloudflare Tunnel"
        exit 1
    fi
    
    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [ -z "$TUNNEL_ID" ]; then
        print_error "Could not retrieve tunnel ID"
        exit 1
    fi
    
    print_success "Tunnel ID: $TUNNEL_ID"
    
    # Create tunnel configuration
    mkdir -p "$CLOUDFLARE_CONFIG_DIR"
    
    cat > "$CLOUDFLARE_CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CLOUDFLARE_CONFIG_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $TUNNEL_NAME.cfargotunnel.com
    service: http://localhost:8000
  - service: http_status:404
EOF
    
    print_success "Tunnel configuration created"
}

create_systemd_services() {
    print_status "Creating systemd services..."
    
    # Main API service
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Multi-Sensor FastAPI Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/server.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Cloudflare Tunnel service
    sudo tee /etc/systemd/system/${TUNNEL_SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel for Multi-Sensor API
After=network.target ${SERVICE_NAME}.service
Wants=network.target
Requires=${SERVICE_NAME}.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME
ExecStart=/usr/bin/cloudflared tunnel --config $CLOUDFLARE_CONFIG_DIR/config.yml run
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable services
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service
    sudo systemctl enable ${TUNNEL_SERVICE_NAME}.service
    
    print_success "Systemd services created and enabled"
}

create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Create start script
    cat > "$PROJECT_DIR/start.sh" << EOF
#!/bin/bash
cd $PROJECT_DIR
source venv/bin/activate
python3 server.py
EOF
    chmod +x "$PROJECT_DIR/start.sh"
    
    # Create tunnel URL checker script
    cat > "$PROJECT_DIR/get_tunnel_url.sh" << EOF
#!/bin/bash

echo "🌐 Checking Cloudflare Tunnel status..."
echo

# Check if tunnel service is running
if ! sudo systemctl is-active --quiet $TUNNEL_SERVICE_NAME; then
    echo "❌ Cloudflare Tunnel service is not running"
    echo "Start it with: sudo systemctl start $TUNNEL_SERVICE_NAME"
    exit 1
fi

# Get tunnel information
TUNNEL_LIST=\$(cloudflared tunnel list 2>/dev/null)

if [ \$? -eq 0 ] && echo "\$TUNNEL_LIST" | grep -q "$TUNNEL_NAME"; then
    echo "✅ Cloudflare Tunnel is active!"
    echo "🌐 External URL: https://$TUNNEL_NAME.cfargotunnel.com"
    echo
    echo "📡 Test your Multi-Sensor API:"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/ (Homepage)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/docs (Swagger UI)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/sensors (All sensors)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/sensors/ultrasonic (Distance)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/sensors/mq135 (Air quality)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/sensors/dht11 (Temperature/Humidity)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/sensors/alerts (Alerts)"
    echo "   https://$TUNNEL_NAME.cfargotunnel.com/health (Health check)"
    echo
    echo "📋 Use this URL to connect from any device anywhere in the world!"
else
    echo "❌ Could not get tunnel information"
    echo "Possible issues:"
    echo "- Not logged in to Cloudflare (run: cloudflared tunnel login)"
    echo "- Tunnel not created properly"
    echo "- Network connectivity issues"
    echo
    echo "Check tunnel logs: sudo journalctl -u $TUNNEL_SERVICE_NAME -f"
fi
EOF
    chmod +x "$PROJECT_DIR/get_tunnel_url.sh"
    
    # Create service management script
    cat > "$PROJECT_DIR/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        sudo systemctl start $SERVICE_NAME
        sudo systemctl start $TUNNEL_SERVICE_NAME
        echo "Services started"
        sleep 3
        echo "Getting tunnel URL..."
        $PROJECT_DIR/get_tunnel_url.sh
        ;;
    stop)
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl stop $TUNNEL_SERVICE_NAME
        echo "Services stopped"
        ;;
    restart)
        sudo systemctl restart $SERVICE_NAME
        sudo systemctl restart $TUNNEL_SERVICE_NAME
        echo "Services restarted"
        sleep 3
        echo "Getting tunnel URL..."
        $PROJECT_DIR/get_tunnel_url.sh
        ;;
    status)
        echo "=== Multi-Sensor API Service Status ==="
        sudo systemctl status $SERVICE_NAME --no-pager
        echo
        echo "=== Cloudflare Tunnel Service Status ==="
        sudo systemctl status $TUNNEL_SERVICE_NAME --no-pager
        ;;
    logs)
        echo "Choose logs to view:"
        echo "1) API logs"
        echo "2) Tunnel logs"
        echo "3) Both"
        read -p "Enter choice (1-3): " choice
        case \$choice in
            1) sudo journalctl -u $SERVICE_NAME -f ;;
            2) sudo journalctl -u $TUNNEL_SERVICE_NAME -f ;;
            3) sudo journalctl -u $SERVICE_NAME -u $TUNNEL_SERVICE_NAME -f ;;
            *) echo "Invalid choice" ;;
        esac
        ;;
    url)
        $PROJECT_DIR/get_tunnel_url.sh
        ;;
    enable)
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl enable $TUNNEL_SERVICE_NAME
        echo "Services enabled for auto-start"
        ;;
    disable)
        sudo systemctl disable $SERVICE_NAME
        sudo systemctl disable $TUNNEL_SERVICE_NAME
        echo "Services disabled"
        ;;
    login)
        cloudflared tunnel login
        ;;
    tunnel-create)
        cloudflared tunnel create $TUNNEL_NAME
        echo "Tunnel '$TUNNEL_NAME' created"
        ;;
    tunnel-list)
        cloudflared tunnel list
        ;;
    tunnel-delete)
        read -p "Are you sure you want to delete tunnel '$TUNNEL_NAME'? (y/N): " -n 1 -r
        echo
        if [[ \$REPLY =~ ^[Yy]$ ]]; then
            cloudflared tunnel delete $TUNNEL_NAME
            echo "Tunnel deleted"
        fi
        ;;
    tunnel-config)
        echo "Current tunnel configuration:"
        cat $CLOUDFLARE_CONFIG_DIR/config.yml
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|enable|disable|login|tunnel-create|tunnel-list|tunnel-delete|tunnel-config}"
        echo
        echo "Commands:"
        echo "  start         - Start both API and tunnel services"
        echo "  stop          - Stop both services"
        echo "  restart       - Restart both services"
        echo "  status        - Show status of both services"
        echo "  logs          - View service logs"
        echo "  url           - Get current tunnel URL"
        echo "  enable        - Enable auto-start on boot"
        echo "  disable       - Disable auto-start on boot"
        echo "  login         - Login to Cloudflare"
        echo "  tunnel-create - Create a new tunnel"
        echo "  tunnel-list   - List all tunnels"
        echo "  tunnel-delete - Delete the current tunnel"
        echo "  tunnel-config - Show tunnel configuration"
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
    
    # Add user to spi group for MQ-135 sensor
    if getent group spi > /dev/null 2>&1; then
        sudo usermod -a -G spi $USER
        print_success "User added to spi group"
    else
        print_warning "SPI group not found."
    fi
}

test_installation() {
    print_status "Testing installation..."
    
    # Check if Python can import required modules
    cd "$PROJECT_DIR"
    source venv/bin/activate
    
    python3 -c "import fastapi; print('FastAPI:', fastapi.__version__)" 2>/dev/null || print_error "FastAPI import failed"
    python3 -c "import uvicorn; print('Uvicorn imported successfully')" 2>/dev/null || print_error "Uvicorn import failed"
    python3 -c "import pydantic; print('Pydantic imported successfully')" 2>/dev/null || print_error "Pydantic import failed"
    
    # Try to import RPi.GPIO (might fail on non-Pi systems)
    python3 -c "import RPi.GPIO; print('RPi.GPIO imported successfully')" 2>/dev/null || print_warning "RPi.GPIO import failed (normal on non-Pi systems)"
    
    # Test Cloudflared
    if command -v cloudflared &> /dev/null; then
        print_success "Cloudflared installed successfully"
        cloudflared --version
    else
        print_error "Cloudflared installation failed"
    fi
    
    # Check tunnel configuration
    if [ -f "$CLOUDFLARE_CONFIG_DIR/config.yml" ]; then
        print_success "Tunnel configuration found"
    else
        print_error "Tunnel configuration missing"
    fi
    
    print_success "Installation test completed"
}

display_usage_info() {
    local IP=$(hostname -I | awk '{print $1}')
    
    echo
    print_success "🎉 Setup completed successfully!"
    echo
    echo "📁 Project directory: $PROJECT_DIR"
    echo "🏠 Local API URL: http://$IP:8000"
    echo "📚 API Documentation: http://$IP:8000/docs (Swagger UI)"
    echo "🌐 External URL: https://$TUNNEL_NAME.cfargotunnel.com"
    echo
    echo "📋 Sensor Wiring Guide:"
    echo
    echo "     🌊 HC-SR04 Ultrasonic Sensor:"
    echo "     VCC  → 5V (Pin 2 or 4)"
    echo "     GND  → Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39)"
    echo "     Trig → GPIO 18 (Pin 12)"
    echo "     Echo → GPIO 24 (Pin 18)"
    echo
    echo "     🌬️ MQ-135 Air Quality Sensor:"
    echo "     VCC → 5V"
    echo "     GND → Ground"
    echo "     A0  → MCP3008 CH0 → SPI (CE0)"
    echo
    echo "     🌡️ DHT11 Temperature/Humidity Sensor:"
    echo "     VCC  → 3.3V"
    echo "     GND  → Ground"
    echo "     Data → GPIO 22"
    echo "     + 10kΩ pull-up resistor between VCC and Data"
    echo
    echo "🚀 Management commands:"
    echo "  Start both services:  $PROJECT_DIR/manage.sh start"
    echo "  Stop both services:   $PROJECT_DIR/manage.sh stop"
    echo "  Check status:         $PROJECT_DIR/manage.sh status"
    echo "  Get tunnel URL:       $PROJECT_DIR/manage.sh url"
    echo "  View logs:            $PROJECT_DIR/manage.sh logs"
    echo "  Manual start:         $PROJECT_DIR/start.sh"
    echo
    echo "🔧 Individual service commands:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl start $TUNNEL_SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl stop $TUNNEL_SERVICE_NAME"
    echo
    echo "🌐 API Endpoints (accessible via both local and tunnel URLs):"
    echo "  /                    - Homepage with documentation"
    echo "  /docs               - Interactive API docs (Swagger)"
    echo "  /sensors            - All sensor readings"
    echo "  /sensors/alerts     - Sensor alerts"
    echo "  /sensors/ultrasonic - Distance sensor only"
    echo "  /sensors/mq135      - Air quality sensor only"
    echo "  /sensors/dht11      - Temperature/humidity sensor only"
    echo "  /health             - Health check all sensors"
    echo "  /config             - Sensor configurations"
    echo
    echo "📡 Test API endpoints:"
    echo "  Local:  curl http://localhost:8000/sensors"
    echo "  Remote: curl https://$TUNNEL_NAME.cfargotunnel.com/sensors"
    echo
    echo "🌐 Your External URL: https://$TUNNEL_NAME.cfargotunnel.com"
    echo "   This URL works from anywhere in the world!"
    echo
    echo "🔑 Cloudflare Tunnel Commands:"
    echo "  cloudflared tunnel login                - Authenticate with Cloudflare"
    echo "  cloudflared tunnel list                 - List all your tunnels"
    echo "  cloudflared tunnel create TUNNEL_NAME  - Create a new tunnel"
    echo "  cloudflared tunnel delete TUNNEL_NAME  - Delete a tunnel"
    echo "  cloudflared tunnel run TUNNEL_NAME     - Run tunnel manually"
}

# Main execution
main() {
    echo "🚀 Multi-Sensor FastAPI Server Setup with Cloudflare Tunnel"
    echo "============================================================="
    
    # Pre-flight checks
    check_root
    check_raspberry_pi
    get_cloudflare_info
    check_project_files
    
    # Setup steps
    update_system
    install_dependencies
    install_cloudflared
    setup_cloudflare_auth
    setup_project_directory
    setup_virtual_environment
    create_cloudflare_tunnel
    create_systemd_services
    create_management_scripts
    setup_gpio_permissions
    test_installation
    
    # Display final information
    display_usage_info
    
    echo
    print_success "Setup script completed! 🎉"
    echo
    read -p "Would you like to start both services now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl start $SERVICE_NAME
        sleep 2
        sudo systemctl start $TUNNEL_SERVICE_NAME
        sleep 3
        echo
        print_status "Services started! Your API is now accessible at:"
        echo "🌐 https://$TUNNEL_NAME.cfargotunnel.com"
        "$PROJECT_DIR/get_tunnel_url.sh"
    fi
}

# Run main function
main "$@"