#!/bin/bash

# Multi-Sensor FastAPI Server Setup Script with Azure Dev Tunnels
# This script sets up the complete environment for the multi-sensor FastAPI server with external access via Azure Dev Tunnels

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
REPO_URL=""  # Will be set if provided as argument
SERVICE_NAME="multi-sensor-api"
TUNNEL_SERVICE_NAME="multi-sensor-tunnel"
USER=$(whoami)
AZURE_USER_EMAIL=""  # Will be prompted for
TUNNEL_NAME="multi-sensor-tunnel"

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

get_azure_account_info() {
    echo
    print_status "🌐 Setting up Azure Dev Tunnels for external access"
    echo
    echo "Azure Dev Tunnels provides secure access to local applications via Azure."
    echo "You'll need a Microsoft account (personal) or Azure account to use this service."
    echo
    echo "Benefits of Azure Dev Tunnels:"
    echo "• Free tier available"
    echo "• Secure HTTPS tunnels"
    echo "• Custom subdomain support"
    echo "• Integrated with Microsoft ecosystem"
    echo
    read -p "Do you have a Microsoft/Azure account for Dev Tunnels? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter your Microsoft account email: " AZURE_USER_EMAIL
        if [ -z "$AZURE_USER_EMAIL" ]; then
            print_warning "No email provided. You'll need to login manually later."
        fi
    else
        print_warning "You'll need to create a Microsoft account and login manually."
        print_status "Visit: https://signup.live.com to create a free Microsoft account"
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
        jq
    print_success "System packages installed"
}

install_azure_dev_tunnels() {
    print_status "Installing Azure Dev Tunnels CLI..."
    
    cd /tmp
    
    # Detect architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "armv7l" ]] || [[ "$ARCH" == "armv6l" ]]; then
        DEVTUNNEL_URL="https://aka.ms/TunnelsCliDownload/linux-arm"
    elif [[ "$ARCH" == "aarch64" ]]; then
        DEVTUNNEL_URL="https://aka.ms/TunnelsCliDownload/linux-arm64"
    else
        DEVTUNNEL_URL="https://aka.ms/TunnelsCliDownload/linux-x64"
    fi
    
    print_status "Downloading Dev Tunnels CLI for $ARCH..."
    wget -O devtunnel "$DEVTUNNEL_URL"
    chmod +x devtunnel
    sudo mv devtunnel /usr/local/bin/
    
    print_success "Azure Dev Tunnels CLI installed"
    
    # Test installation
    if /usr/local/bin/devtunnel --version > /dev/null 2>&1; then
        print_success "Dev Tunnels CLI is working"
    else
        print_error "Dev Tunnels CLI installation failed"
        exit 1
    fi
}

setup_azure_login() {
    print_status "Setting up Azure Dev Tunnels authentication..."
    
    echo
    echo "You need to authenticate with Microsoft/Azure to use Dev Tunnels."
    echo "This will open a browser window or provide a device code for authentication."
    echo
    read -p "Proceed with Azure login? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting Azure authentication..."
        echo "If you're using SSH, you'll get a device code to enter at https://microsoft.com/devicelogin"
        
        if /usr/local/bin/devtunnel user login; then
            print_success "Azure authentication successful"
        else
            print_error "Azure authentication failed"
            print_status "You can authenticate later using: devtunnel user login"
        fi
    else
        print_warning "Skipping Azure login. You'll need to authenticate later."
        print_status "Run this command later: devtunnel user login"
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
        
        # Rename ultrasonic_server.py to server.py if it exists
        if [ -f "ultrasonic_server.py" ]; then
            mv ultrasonic_server.py server.py
            print_status "Renamed ultrasonic_server.py to server.py"
        fi
        
        print_success "Repository cloned successfully"
    else
        print_status "No repository URL provided. You'll need to upload your code manually."
        print_status "Creating placeholder files..."
        
        # Create placeholder requirements.txt for FastAPI
        cat > requirements.txt << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
RPi.GPIO==0.7.1
Adafruit-DHT==1.4.0
spidev==3.6
EOF
        
        cat > README.md << EOF
# Multi-Sensor FastAPI Server with Azure Dev Tunnels

Upload your server.py and requirements.txt files to this directory.

## Supported Sensors
- HC-SR04 Ultrasonic Distance Sensor
- MQ-135 Air Quality Sensor
- DHT11 Temperature/Humidity Sensor

## Quick Start
1. Upload server.py to $PROJECT_DIR
2. Upload requirements.txt to $PROJECT_DIR
3. Run: sudo systemctl start $SERVICE_NAME
4. Run: sudo systemctl start $TUNNEL_SERVICE_NAME
5. Check tunnel URL: $PROJECT_DIR/get_tunnel_url.sh

## Local Access
http://$(hostname -I | awk '{print $1}'):8000

## API Documentation
- Swagger UI: http://$(hostname -I | awk '{print $1}'):8000/docs
- ReDoc: http://$(hostname -I | awk '{print $1}'):8000/redoc

## External Access
Check Azure Dev Tunnel URL with: $PROJECT_DIR/get_tunnel_url.sh

## Manual Start
\`\`\`bash
cd $PROJECT_DIR
source venv/bin/activate
python3 server.py
# In another terminal:
devtunnel host -p 8000 --allow-anonymous
\`\`\`

## Pin Connections

### HC-SR04 Ultrasonic Sensor:
- VCC → 5V (Pin 2 or 4)
- GND → Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39)
- Trig → GPIO 18 (Pin 12)
- Echo → GPIO 24 (Pin 18)

### MQ-135 Air Quality Sensor:
- VCC → 5V
- GND → Ground
- A0 → MCP3008 CH0 → SPI (CE0)
- D0 → Not used

### DHT11 Temperature/Humidity Sensor:
- VCC → 3.3V
- GND → Ground
- Data → GPIO 22
- Pull-up resistor (10kΩ) between VCC and Data
EOF
        
        print_warning "Please upload your server.py and requirements.txt files to: $PROJECT_DIR"
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
        pip install fastapi uvicorn[standard] pydantic RPi.GPIO Adafruit-DHT spidev
    fi
    
    print_success "Virtual environment created and packages installed"
}

create_tunnel() {
    print_status "Creating Azure Dev Tunnel..."
    
    # Create a persistent tunnel
    if /usr/local/bin/devtunnel create --allow-anonymous --name "$TUNNEL_NAME" > /dev/null 2>&1; then
        print_success "Azure Dev Tunnel '$TUNNEL_NAME' created successfully"
    else
        print_warning "Tunnel creation failed or tunnel already exists"
        print_status "This is normal if the tunnel was already created"
    fi
}

create_systemd_service() {
    print_status "Creating systemd service..."
    
    # Main API service (updated for FastAPI on port 8000)
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
    
    # Azure Dev Tunnels service
    sudo tee /etc/systemd/system/${TUNNEL_SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Azure Dev Tunnel for Multi-Sensor API
After=network.target ${SERVICE_NAME}.service
Wants=network.target
Requires=${SERVICE_NAME}.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/devtunnel host $TUNNEL_NAME -p 8000 --allow-anonymous
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
    sudo systemctl enable ${TUNNEL_SERVICE_NAME}.service
    
    print_success "Systemd services created and enabled"
}

create_management_scripts() {
    print_status "Creating convenience scripts..."
    
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

echo "🌐 Checking Azure Dev Tunnel status..."
echo

# Check if tunnel service is running
if ! sudo systemctl is-active --quiet $TUNNEL_SERVICE_NAME; then
    echo "❌ Azure Dev Tunnel service is not running"
    echo "Start it with: sudo systemctl start $TUNNEL_SERVICE_NAME"
    exit 1
fi

# Wait a moment for tunnel to establish
sleep 2

# Get tunnel information
TUNNEL_INFO=\$(/usr/local/bin/devtunnel show $TUNNEL_NAME --output json 2>/dev/null)

if [ \$? -eq 0 ] && [ -n "\$TUNNEL_INFO" ]; then
    # Extract the HTTPS URL
    TUNNEL_URL=\$(echo "\$TUNNEL_INFO" | jq -r '.endpoints[] | select(.hostHeader != null) | "https://" + .hostHeader' 2>/dev/null | head -1)
    
    if [ -n "\$TUNNEL_URL" ] && [ "\$TUNNEL_URL" != "null" ]; then
        echo "✅ Azure Dev Tunnel is active!"
        echo "🌐 External URL: \$TUNNEL_URL"
        echo
        echo "📡 Test your Multi-Sensor API:"
        echo "   \$TUNNEL_URL/ (Homepage with documentation)"
        echo "   \$TUNNEL_URL/docs (Swagger UI)"
        echo "   \$TUNNEL_URL/sensors (All sensor readings)"
        echo "   \$TUNNEL_URL/sensors/ultrasonic (Distance sensor)"
        echo "   \$TUNNEL_URL/sensors/mq135 (Air quality sensor)"
        echo "   \$TUNNEL_URL/sensors/dht11 (Temperature/Humidity)"
        echo "   \$TUNNEL_URL/sensors/alerts (Sensor alerts)"
        echo "   \$TUNNEL_URL/health (Health check)"
        echo
        echo "📋 Use this URL to connect from any device on any network!"
    else
        echo "❌ Could not extract tunnel URL"
        echo "Check tunnel logs: sudo journalctl -u $TUNNEL_SERVICE_NAME -f"
    fi
else
    echo "❌ Could not get tunnel information"
    echo "Possible issues:"
    echo "- Not logged in to Azure (run: devtunnel user login)"
    echo "- Tunnel not created (run: devtunnel create --allow-anonymous --name $TUNNEL_NAME)"
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
        echo "=== Azure Dev Tunnel Service Status ==="
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
        devtunnel user login
        ;;
    tunnel-create)
        devtunnel create --allow-anonymous --name $TUNNEL_NAME
        echo "Tunnel '$TUNNEL_NAME' created"
        ;;
    tunnel-list)
        devtunnel list
        ;;
    tunnel-delete)
        read -p "Are you sure you want to delete tunnel '$TUNNEL_NAME'? (y/N): " -n 1 -r
        echo
        if [[ \$REPLY =~ ^[Yy]$ ]]; then
            devtunnel delete $TUNNEL_NAME
            echo "Tunnel deleted"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|enable|disable|login|tunnel-create|tunnel-list|tunnel-delete}"
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
        echo "  login         - Login to Azure Dev Tunnels"
        echo "  tunnel-create - Create a new tunnel"
        echo "  tunnel-list   - List all tunnels"
        echo "  tunnel-delete - Delete the current tunnel"
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
    python3 -c "import pydantic; print('Pydantic:', pydantic.__version__)" 2>/dev/null || print_error "Pydantic import failed"
    
    # Try to import RPi.GPIO (might fail on non-Pi systems)
    python3 -c "import RPi.GPIO; print('RPi.GPIO imported successfully')" 2>/dev/null || print_warning "RPi.GPIO import failed (normal on non-Pi systems)"
    
    # Try to import Adafruit_DHT
    python3 -c "import Adafruit_DHT; print('Adafruit_DHT imported successfully')" 2>/dev/null || print_warning "Adafruit_DHT import failed"
    
    # Try to import spidev
    python3 -c "import spidev; print('spidev imported successfully')" 2>/dev/null || print_warning "spidev import failed"
    
    # Test Azure Dev Tunnels CLI
    if command -v devtunnel &> /dev/null; then
        print_success "Azure Dev Tunnels CLI installed successfully"
        /usr/local/bin/devtunnel --version
    else
        print_error "Azure Dev Tunnels CLI installation failed"
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
    echo "🌐 External access: via Azure Dev Tunnels (see commands below)"
    echo
    echo "📋 Next steps:"
    echo "  1. If you haven't already, upload your files to:"
    echo "     server.py → $PROJECT_DIR"
    echo "     requirements.txt → $PROJECT_DIR"
    echo
    echo "  2. If not logged in to Azure, authenticate:"
    echo "     $PROJECT_DIR/manage.sh login"
    echo "     (You'll need a Microsoft account - free at https://signup.live.com)"
    echo
    echo "  3. Wire your sensors:"
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
    echo "  Azure login:          $PROJECT_DIR/manage.sh login"
    echo "  Manual start:         $PROJECT_DIR/start.sh"
    echo
    echo "🔧 Individual service commands:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl start $TUNNEL_SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl stop $TUNNEL_SERVICE_NAME"
    echo
    echo "📡 Test API endpoints:"
    echo "  Local:  curl http://localhost:8000/sensors"
    echo "  Remote: Use the tunnel URL from 'manage.sh url'"
    echo
    echo "🌐 API Endpoints:"
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
    echo "🌐 Getting your external URL:"
    echo "  After starting services, run: $PROJECT_DIR/manage.sh url"
    echo "  This URL will work from anywhere in the world!"
    echo
    echo "🔑 Azure Dev Tunnels Commands:"
    echo "  devtunnel user login                    - Authenticate with Microsoft"
    echo "  devtunnel list                         - List all your tunnels"
    echo "  devtunnel create --allow-anonymous     - Create a new tunnel"
    echo "  devtunnel host -p 8000 --allow-anonymous - Host on port 8000"
    echo "  devtunnel delete TUNNEL_NAME           - Delete a tunnel"
    echo
    if [ -z "$REPO_URL" ]; then
        print_warning "Remember to upload your server.py and requirements.txt files before starting the service!"
    fi
    
    print_warning "Remember to login to Azure Dev Tunnels: $PROJECT_DIR/manage.sh login"
}

# Main execution
main() {
    echo "🚀 Multi-Sensor FastAPI Server Setup with Azure Dev Tunnels"
    echo "==========================================================="
    
    # Parse arguments
    if [ $# -gt 0 ]; then
        REPO_URL=$1
        print_status "Repository URL provided: $REPO_URL"
    fi
    
    # Pre-flight checks
    check_root
    check_raspberry_pi
    get_azure_account_info
    
    # Setup steps
    update_system
    install_dependencies
    install_azure_dev_tunnels
    setup_azure_login
    setup_project_directory
    clone_or_download_code
    setup_virtual_environment
    create_tunnel
    create_systemd_service
    create_management_scripts
    setup_gpio_permissions
    test_installation
    
    # Display final information
    display_usage_info
    
    echo
    print_success "Setup script completed! 🎉"
    
    if [ -n "$REPO_URL" ] && [ -f "$PROJECT_DIR/server.py" ]; then
        echo
        read -p "Would you like to start both services now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl start $SERVICE_NAME
            sleep 2
            sudo systemctl start $TUNNEL_SERVICE_NAME
            sleep 3
            echo
            print_status "Services started! Getting your external URL..."
            "$PROJECT_DIR/get_tunnel_url.sh"
        fi
    fi
}

# Run main function
main "$@"