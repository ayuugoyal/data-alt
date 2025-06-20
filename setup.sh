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
REPO_URL=""  # Will be set if provided as argument
SERVICE_NAME="multi-sensor-api"
CLOUDFLARED_SERVICE_NAME="multi-sensor-cloudflared"
USER=$(whoami)
CLOUDFLARE_TOKEN=""  # Will be prompted for
DOMAIN_NAME=""       # Will be prompted for
SUBDOMAIN=""         # Will be prompted for

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

cleanup_existing_cloudflare() {
    print_status "🧹 Cleaning up existing Cloudflare Tunnel setup..."
    
    # Stop and disable existing cloudflared services
    sudo systemctl stop cloudflared 2>/dev/null || true
    sudo systemctl disable cloudflared 2>/dev/null || true
    sudo systemctl stop $CLOUDFLARED_SERVICE_NAME 2>/dev/null || true
    sudo systemctl disable $CLOUDFLARED_SERVICE_NAME 2>/dev/null || true
    
    # Remove existing service files
    sudo rm -f /etc/systemd/system/cloudflared.service
    sudo rm -f /etc/systemd/system/$CLOUDFLARED_SERVICE_NAME.service
    
    # List and delete all existing tunnels
    if command -v cloudflared &> /dev/null; then
        print_status "Checking for existing tunnels..."
        EXISTING_TUNNELS=$(cloudflared tunnel list 2>/dev/null | grep -E '^[a-f0-9-]{36}' | awk '{print $1}' || true)
        
        if [ -n "$EXISTING_TUNNELS" ]; then
            echo "Found existing tunnels:"
            cloudflared tunnel list 2>/dev/null || true
            echo
            read -p "Delete all existing tunnels? This will break any current tunnel connections. (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                for tunnel_id in $EXISTING_TUNNELS; do
                    print_status "Deleting tunnel: $tunnel_id"
                    cloudflared tunnel delete $tunnel_id --force 2>/dev/null || true
                done
                print_success "All existing tunnels deleted"
            else
                print_warning "Keeping existing tunnels. This may cause conflicts."
            fi
        else
            print_status "No existing tunnels found"
        fi
    fi
    
    # Clean up configuration files
    rm -rf ~/.cloudflared/ 2>/dev/null || true
    
    # Remove cloudflared package
    sudo apt remove --purge cloudflared -y 2>/dev/null || true
    
    # Remove cloudflare repository
    sudo rm -f /etc/apt/sources.list.d/cloudflared.list
    sudo rm -f /usr/share/keyrings/cloudflare-main.gpg
    
    sudo systemctl daemon-reload
    print_success "Cloudflare cleanup completed"
}

get_cloudflare_config() {
    echo
    print_status "🌐 Setting up Cloudflare Tunnel for external access"
    echo "To use Cloudflare Tunnel, you need:"
    echo "1. A domain registered with Cloudflare (DNS managed by Cloudflare)"
    echo "2. A Cloudflare API token with Zone:Zone:Read and Zone:DNS:Edit permissions"
    echo
    echo "Steps to get your API token:"
    echo "1. Go to https://dash.cloudflare.com/profile/api-tokens"
    echo "2. Click 'Create Token'"
    echo "3. Use 'Edit zone DNS' template or create custom token with:"
    echo "   - Zone:Zone:Read"
    echo "   - Zone:DNS:Edit"
    echo "4. Select your zone (domain)"
    echo "5. Copy the generated token"
    echo
    
    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        print_error "Domain name is required for Cloudflare Tunnel"
        exit 1
    fi
    
    read -p "Enter subdomain for API (e.g., sensors for sensors.example.com): " SUBDOMAIN
    if [ -z "$SUBDOMAIN" ]; then
        SUBDOMAIN="api"
        print_status "Using default subdomain: api"
    fi
    
    read -p "Enter your Cloudflare API token: " CLOUDFLARE_TOKEN
    if [ -z "$CLOUDFLARE_TOKEN" ]; then
        print_error "Cloudflare API token is required"
        exit 1
    fi
    
    print_success "Cloudflare configuration collected"
    print_status "Your API will be accessible at: https://${SUBDOMAIN}.${DOMAIN_NAME}"
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
        lsb-release \
        ca-certificates \
        gnupg
    print_success "System packages installed"
}

install_cloudflared() {
    print_status "Installing Cloudflare Tunnel (cloudflared)..."
    
    # Detect architecture
    ARCH=$(dpkg --print-architecture)
    print_status "Detected architecture: $ARCH"
    
    # Download and install cloudflared directly
    case $ARCH in
        amd64)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        arm64)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        armhf|arm)
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    print_status "Downloading cloudflared from: $CLOUDFLARED_URL"
    wget -O /tmp/cloudflared "$CLOUDFLARED_URL"
    
    # Make executable and install
    chmod +x /tmp/cloudflared
    sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
    
    # Verify installation
    if cloudflared version; then
        print_success "cloudflared installed successfully"
    else
        print_error "cloudflared installation failed"
        exit 1
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
# Multi-Sensor FastAPI Server with Cloudflare Tunnel

Upload your server.py and requirements.txt files to this directory.

## Supported Sensors
- HC-SR04 Ultrasonic Distance Sensor
- MQ-135 Air Quality Sensor
- DHT11 Temperature/Humidity Sensor

## Quick Start
1. Upload server.py to $PROJECT_DIR
2. Upload requirements.txt to $PROJECT_DIR
3. Run: sudo systemctl start $SERVICE_NAME
4. Run: sudo systemctl start $CLOUDFLARED_SERVICE_NAME
5. Access API: https://${SUBDOMAIN}.${DOMAIN_NAME}

## Local Access
http://$(hostname -I | awk '{print $1}'):8000

## API Documentation
- Swagger UI: http://$(hostname -I | awk '{print $1}'):8000/docs
- ReDoc: http://$(hostname -I | awk '{print $1}'):8000/redoc

## External Access
https://${SUBDOMAIN}.${DOMAIN_NAME}

## Manual Start
\`\`\`bash
cd $PROJECT_DIR
source venv/bin/activate
python3 server.py
# In another terminal:
cloudflared tunnel run
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

setup_cloudflare_tunnel() {
    print_status "Setting up Cloudflare Tunnel..."
    
    # Create tunnel
    TUNNEL_NAME="multi-sensor-api-$(date +%s)"
    print_status "Creating tunnel: $TUNNEL_NAME"
    
    # Authenticate cloudflared with token
    export CLOUDFLARE_TUNNEL_TOKEN="$CLOUDFLARE_TOKEN"
    
    # Create tunnel
    TUNNEL_CREATE_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
    if [ $? -eq 0 ]; then
        print_success "Tunnel created successfully"
        echo "$TUNNEL_CREATE_OUTPUT"
    else
        print_error "Failed to create tunnel. Output:"
        echo "$TUNNEL_CREATE_OUTPUT"
        
        # Try alternative authentication method
        print_status "Trying alternative authentication method..."
        echo "$CLOUDFLARE_TOKEN" > /tmp/cf_token
        cloudflared tunnel login --token-file /tmp/cf_token
        rm -f /tmp/cf_token
        
        cloudflared tunnel create "$TUNNEL_NAME"
    fi
    
    # Get tunnel UUID
    TUNNEL_UUID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    
    if [ -z "$TUNNEL_UUID" ]; then
        # Try to get tunnel ID from the create output
        TUNNEL_UUID=$(echo "$TUNNEL_CREATE_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
        
        if [ -z "$TUNNEL_UUID" ]; then
            print_error "Failed to get tunnel UUID"
            print_status "Available tunnels:"
            cloudflared tunnel list
            exit 1
        fi
    fi
    
    print_success "Tunnel created with UUID: $TUNNEL_UUID"
    
    # Create tunnel configuration
    mkdir -p ~/.cloudflared
    cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_UUID
credentials-file: ~/.cloudflared/$TUNNEL_UUID.json

ingress:
  - hostname: ${SUBDOMAIN}.${DOMAIN_NAME}
    service: http://localhost:8000
  - service: http_status:404
EOF
    
    # Create DNS record
    print_status "Creating DNS record..."
    if cloudflared tunnel route dns "$TUNNEL_UUID" "${SUBDOMAIN}.${DOMAIN_NAME}"; then
        print_success "DNS record created successfully"
    else
        print_warning "DNS record creation may have failed. You may need to create it manually."
        print_status "Manual DNS setup: Create a CNAME record for ${SUBDOMAIN} pointing to $TUNNEL_UUID.cfargotunnel.com"
    fi
    
    print_success "Cloudflare Tunnel configured successfully"
    print_success "API will be accessible at: https://${SUBDOMAIN}.${DOMAIN_NAME}"
}

create_systemd_service() {
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
    sudo tee /etc/systemd/system/${CLOUDFLARED_SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel for Multi-Sensor API
After=network.target ${SERVICE_NAME}.service
Wants=network.target
Requires=${SERVICE_NAME}.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/cloudflared tunnel run
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
    sudo systemctl enable ${CLOUDFLARED_SERVICE_NAME}.service
    
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
    
    # Create tunnel status checker script
    cat > "$PROJECT_DIR/check_tunnel.sh" << EOF
#!/bin/bash

echo "🌐 Checking Cloudflare Tunnel status..."
echo

# Check if cloudflared service is running
if ! sudo systemctl is-active --quiet $CLOUDFLARED_SERVICE_NAME; then
    echo "❌ Cloudflare Tunnel service is not running"
    echo "Start it with: sudo systemctl start $CLOUDFLARED_SERVICE_NAME"
    exit 1
fi

echo "✅ Cloudflare Tunnel service is running!"
echo "🌐 External URL: https://${SUBDOMAIN}.${DOMAIN_NAME}"
echo
echo "📡 Test your Multi-Sensor API:"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/ (Homepage with documentation)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/docs (Swagger UI)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors (All sensor readings)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors/ultrasonic (Distance sensor)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors/mq135 (Air quality sensor)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors/dht11 (Temperature/Humidity)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors/alerts (Sensor alerts)"
echo "   https://${SUBDOMAIN}.${DOMAIN_NAME}/health (Health check)"
echo
echo "📋 Use this URL to connect from any device on any network!"
echo "🔒 Secure HTTPS connection provided by Cloudflare"

# Check tunnel connectivity
echo
echo "🔍 Testing tunnel connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "https://${SUBDOMAIN}.${DOMAIN_NAME}/health" | grep -q "200"; then
    echo "✅ Tunnel is working correctly!"
else
    echo "⚠️  Tunnel may not be fully ready yet or API is not responding"
    echo "Check service logs: sudo journalctl -u $SERVICE_NAME -f"
fi
EOF
    chmod +x "$PROJECT_DIR/check_tunnel.sh"
    
    # Create service management script
    cat > "$PROJECT_DIR/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        sudo systemctl start $SERVICE_NAME
        sudo systemctl start $CLOUDFLARED_SERVICE_NAME
        echo "Services started"
        sleep 5
        echo "Checking tunnel status..."
        $PROJECT_DIR/check_tunnel.sh
        ;;
    stop)
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl stop $CLOUDFLARED_SERVICE_NAME
        echo "Services stopped"
        ;;
    restart)
        sudo systemctl restart $SERVICE_NAME
        sudo systemctl restart $CLOUDFLARED_SERVICE_NAME
        echo "Services restarted"
        sleep 5
        echo "Checking tunnel status..."
        $PROJECT_DIR/check_tunnel.sh
        ;;
    status)
        echo "=== Multi-Sensor API Service Status ==="
        sudo systemctl status $SERVICE_NAME --no-pager
        echo
        echo "=== Cloudflare Tunnel Service Status ==="
        sudo systemctl status $CLOUDFLARED_SERVICE_NAME --no-pager
        ;;
    logs)
        echo "Choose logs to view:"
        echo "1) API logs"
        echo "2) Cloudflare Tunnel logs"
        echo "3) Both"
        read -p "Enter choice (1-3): " choice
        case \$choice in
            1) sudo journalctl -u $SERVICE_NAME -f ;;
            2) sudo journalctl -u $CLOUDFLARED_SERVICE_NAME -f ;;
            3) sudo journalctl -u $SERVICE_NAME -u $CLOUDFLARED_SERVICE_NAME -f ;;
            *) echo "Invalid choice" ;;
        esac
        ;;
    url)
        $PROJECT_DIR/check_tunnel.sh
        ;;
    enable)
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl enable $CLOUDFLARED_SERVICE_NAME
        echo "Services enabled for auto-start"
        ;;
    disable)
        sudo systemctl disable $SERVICE_NAME
        sudo systemctl disable $CLOUDFLARED_SERVICE_NAME
        echo "Services disabled"
        ;;
    tunnel-info)
        echo "=== Cloudflare Tunnel Information ==="
        cloudflared tunnel list
        echo
        echo "=== Tunnel Configuration ==="
        cat ~/.cloudflared/config.yml 2>/dev/null || echo "No config file found"
        ;;
    cleanup)
        echo "🧹 Cleaning up tunnels and configuration..."
        sudo systemctl stop $SERVICE_NAME $CLOUDFLARED_SERVICE_NAME
        cloudflared tunnel list
        echo
        echo "This will delete ALL tunnels. Are you sure?"
        read -p "Type 'yes' to confirm: " confirm
        if [ "\$confirm" = "yes" ]; then
            for tunnel in \$(cloudflared tunnel list | grep -E '^[a-f0-9-]{36}' | awk '{print \$1}'); do
                cloudflared tunnel delete \$tunnel --force
            done
            rm -rf ~/.cloudflared/
            echo "Cleanup completed"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|enable|disable|tunnel-info|cleanup}"
        echo
        echo "Commands:"
        echo "  start       - Start both API and Cloudflare Tunnel services"
        echo "  stop        - Stop both services"
        echo "  restart     - Restart both services"
        echo "  status      - Show status of both services"
        echo "  logs        - View service logs"
        echo "  url         - Check tunnel status and show URL"
        echo "  enable      - Enable auto-start on boot"
        echo "  disable     - Disable auto-start on boot"
        echo "  tunnel-info - Show tunnel configuration and details"
        echo "  cleanup     - Clean up all tunnels and configuration"
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
    
    # Test cloudflared
    if command -v cloudflared &> /dev/null; then
        print_success "cloudflared installed successfully"
        cloudflared version
    else
        print_error "cloudflared installation failed"
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
    echo "🌐 External URL: https://${SUBDOMAIN}.${DOMAIN_NAME}"
    echo "🔒 Secure HTTPS connection provided by Cloudflare"
    echo
    echo "📋 Next steps:"
    echo "  1. If you haven't already, upload your files to:"
    echo "     server.py → $PROJECT_DIR"
    echo "     requirements.txt → $PROJECT_DIR"
    echo
    echo "  2. Wire your sensors:"
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
    echo "  Start both services:    $PROJECT_DIR/manage.sh start"
    echo "  Stop both services:     $PROJECT_DIR/manage.sh stop"
    echo "  Check status:           $PROJECT_DIR/manage.sh status"
    echo "  Check tunnel & URL:     $PROJECT_DIR/manage.sh url"
    echo "  View logs:              $PROJECT_DIR/manage.sh logs"
    echo "  Tunnel information:     $PROJECT_DIR/manage.sh tunnel-info"
    echo "  Clean up tunnels:       $PROJECT_DIR/manage.sh cleanup"
    echo "  Manual start:           $PROJECT_DIR/start.sh"
    echo
    echo "🔧 Individual service commands:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl start $CLOUDFLARED_SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl stop $CLOUDFLARED_SERVICE_NAME"
    echo
    echo "📡 Test API endpoints:"
    echo "  Local:  curl http://localhost:8000/sensors"
    echo "  Remote: curl https://${SUBDOMAIN}.${DOMAIN_NAME}/sensors"
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
    echo "🌐 Your permanent external URL:"
    echo "  https://${SUBDOMAIN}.${DOMAIN_NAME}"
    echo "  This URL will work from anywhere in the world with HTTPS!"
    echo
    if [ -z "$REPO_URL" ]; then
        print_warning "Remember to upload your server.py and requirements.txt files before starting the service!"
    fi
    
    echo "🔍 Troubleshooting:"
    echo "  Check tunnel status: $PROJECT_DIR/check_tunnel.sh"
    echo "  View API logs:       sudo journalctl -u $SERVICE_NAME -f"
    echo "  View tunnel logs:    sudo journalctl -u $CLOUDFLARED_SERVICE_NAME -f"
    echo "  List tunnels:        cloudflared tunnel list"
    echo "  Clean up tunnels:    $PROJECT_DIR/manage.sh cleanup"
}

# Main execution
main() {
    echo "🚀 Multi-Sensor FastAPI Server Setup with Cloudflare Tunnel"
    echo "==========================================================="
    
    # Parse arguments
    if [ $# -gt 0 ]; then
        REPO_URL=$1
        print_status "Repository URL provided: $REPO_URL"
    fi
    
    # Pre-flight checks
    check_root
    check_raspberry_pi
    cleanup_existing_cloudflare
    get_cloudflare_config
    
    # Setup steps
    update_system
    install_dependencies
    install_cloudflared
    setup_project_directory
    clone_or_download_code
    setup_virtual_environment
    setup_cloudflare_tunnel
    create_systemd_service
    create_management_scripts
    setup_gpio_permissions
    test_installation
    display_usage_info
    
    echo
    print_success "🎯 Setup completed! Your Multi-Sensor API is ready!"
    print_status "Run: $PROJECT_DIR/manage.sh start"
    print_status "Then check: $PROJECT_DIR/check_tunnel.sh"
    echo
}

# Trap to cleanup on script exit
trap 'echo "Setup interrupted"; exit 1' INT TERM

# Run main function with all arguments
main "$@"

# End of script marker
print_success "✨ Multi-Sensor FastAPI Server setup script completed successfully!"
print_status "External URL: https://${SUBDOMAIN}.${DOMAIN_NAME}"
print_status "Management: $PROJECT_DIR/manage.sh"