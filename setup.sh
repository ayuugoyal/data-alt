#!/bin/bash

# Fixed Multi-Sensor FastAPI Server Setup Script with Cloudflare Tunnel
# This script fixes the Cloudflare authentication and tunnel creation issues

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
TUNNEL_NAME="multi-sensor-tunnel-$(date +%s)"  # Add timestamp for uniqueness
CLOUDFLARE_CONFIG_DIR="$HOME/.cloudflared"
CUSTOM_DOMAIN=""
USE_CUSTOM_DOMAIN=false

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
    echo "You'll get a FREE .trycloudflare.com subdomain automatically."
    echo
    echo "Benefits of Cloudflare Tunnel:"
    echo "• Completely free"
    echo "• No port forwarding needed"
    echo "• Built-in DDoS protection"
    echo "• FREE .trycloudflare.com subdomain"
    echo "• Custom domain support (optional)"
    echo "• Excellent performance and reliability"
    echo
    
    # Simplified domain question
    echo "Domain Options:"
    echo "1. Use FREE .trycloudflare.com subdomain (recommended for testing)"
    echo "2. Use custom domain (requires domain in Cloudflare)"
    echo
    read -p "Choose option (1 or 2): " domain_choice
    
    case $domain_choice in
        2)
            read -p "Enter your custom domain/subdomain (e.g., api.yourdomain.com): " CUSTOM_DOMAIN
            if [ -n "$CUSTOM_DOMAIN" ]; then
                USE_CUSTOM_DOMAIN=true
                print_status "Will configure tunnel for: $CUSTOM_DOMAIN"
                echo
                print_warning "Important: Make sure your domain is added to Cloudflare Dashboard!"
                print_status "Your domain must be managed by Cloudflare for this to work."
                echo
                read -p "Is your domain already in Cloudflare Dashboard? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    print_warning "Please add your domain to Cloudflare first:"
                    print_status "1. Go to https://dash.cloudflare.com"
                    print_status "2. Click 'Add Site' and enter your domain"
                    print_status "3. Follow the setup instructions"
                    echo
                    read -p "Press Enter after adding your domain to Cloudflare..."
                fi
            else
                print_warning "No domain provided, using free subdomain"
                USE_CUSTOM_DOMAIN=false
            fi
            ;;
        *)
            print_status "Using free .trycloudflare.com subdomain"
            USE_CUSTOM_DOMAIN=false
            ;;
    esac
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
    
    # Check if already installed
    if command -v cloudflared &> /dev/null; then
        print_status "Cloudflared already installed"
        cloudflared --version
        return
    fi
    
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
    
    # Check if already authenticated
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        print_status "Already authenticated with Cloudflare"
        return
    fi
    
    echo
    echo "📝 Cloudflare Authentication Steps:"
    echo "1. You need a FREE Cloudflare account"
    echo "2. The login process will show you a URL"
    echo "3. Copy the URL and open it in your browser"
    echo "4. Login to Cloudflare and authorize the tunnel"
    echo "5. You'll see a success message in your browser"
    echo
    
    read -p "Do you have a Cloudflare account? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Create a free account at: https://dash.cloudflare.com/sign-up"
        read -p "Press Enter after creating your account..."
    fi
    
    print_status "Starting Cloudflare authentication..."
    echo
    print_warning "IMPORTANT: Copy the URL that appears below and paste it in your browser!"
    echo
    
    # Try authentication with better error handling
    if timeout 120 cloudflared tunnel login; then
        print_success "Cloudflare authentication successful!"
        
        # Verify authentication worked
        if [ -f "$HOME/.cloudflared/cert.pem" ]; then
            print_success "Certificate file created successfully"
        else
            print_error "Authentication may have failed - no certificate file found"
            exit 1
        fi
    else
        print_error "Cloudflare authentication failed or timed out"
        print_status "Troubleshooting tips:"
        print_status "1. Make sure you have a Cloudflare account"
        print_status "2. Copy the full URL shown above"
        print_status "3. Complete the browser authorization"
        print_status "4. Try running: cloudflared tunnel login"
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
    
    # Check if tunnel already exists
    if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        print_warning "Tunnel '$TUNNEL_NAME' already exists"
        TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    else
        # Create tunnel
        print_status "Creating new tunnel: $TUNNEL_NAME"
        if cloudflared tunnel create "$TUNNEL_NAME"; then
            print_success "Cloudflare Tunnel '$TUNNEL_NAME' created successfully"
            TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
        else
            print_error "Failed to create Cloudflare Tunnel"
            print_status "Possible issues:"
            print_status "1. Not authenticated - run: cloudflared tunnel login"
            print_status "2. Network connectivity issues"
            print_status "3. Cloudflare service issues"
            exit 1
        fi
    fi
    
    if [ -z "$TUNNEL_ID" ]; then
        print_error "Could not retrieve tunnel ID"
        exit 1
    fi
    
    print_success "Tunnel ID: $TUNNEL_ID"
    
    # Create tunnel configuration directory
    mkdir -p "$CLOUDFLARE_CONFIG_DIR"
    
    # Determine hostname and create configuration
    if [ "$USE_CUSTOM_DOMAIN" = true ] && [ -n "$CUSTOM_DOMAIN" ]; then
        HOSTNAME="$CUSTOM_DOMAIN"
        print_status "Using custom domain: $HOSTNAME"
        
        # Create DNS record for custom domain
        print_status "Creating DNS record for $CUSTOM_DOMAIN..."
        if cloudflared tunnel route dns "$TUNNEL_NAME" "$CUSTOM_DOMAIN"; then
            print_success "DNS record created for $CUSTOM_DOMAIN"
        else
            print_warning "Could not create DNS record automatically"
            print_status "Please create it manually in Cloudflare Dashboard:"
            print_status "1. Go to https://dash.cloudflare.com"
            print_status "2. Select your domain"
            print_status "3. Go to DNS settings"
            print_status "4. Add CNAME record: $CUSTOM_DOMAIN → $TUNNEL_ID.cfargotunnel.com"
        fi
        
        # Create config for custom domain
        cat > "$CLOUDFLARE_CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CLOUDFLARE_CONFIG_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $HOSTNAME
    service: http://localhost:8000
  - service: http_status:404
EOF
    else
        # Use trycloudflare.com (no hostname needed)
        HOSTNAME="Generated automatically"
        print_status "Using free .trycloudflare.com subdomain"
        
        # Create config for trycloudflare
        cat > "$CLOUDFLARE_CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $CLOUDFLARE_CONFIG_DIR/$TUNNEL_ID.json

ingress:
  - service: http://localhost:8000
EOF
    fi
    
    # Save configuration info
    echo "$HOSTNAME" > "$PROJECT_DIR/.tunnel_hostname"
    echo "$TUNNEL_ID" > "$PROJECT_DIR/.tunnel_id"
    echo "$USE_CUSTOM_DOMAIN" > "$PROJECT_DIR/.use_custom_domain"
    
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
    cat > "$PROJECT_DIR/start.sh" << 'EOF'
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

# Check if using custom domain
USE_CUSTOM=\$(cat "$PROJECT_DIR/.use_custom_domain" 2>/dev/null || echo "false")

if [ "\$USE_CUSTOM" = "true" ]; then
    # Custom domain setup
    if [ -f "$PROJECT_DIR/.tunnel_hostname" ]; then
        HOSTNAME=\$(cat "$PROJECT_DIR/.tunnel_hostname")
        echo "✅ Cloudflare Tunnel is active with custom domain!"
        echo "🌐 External URL: https://\$HOSTNAME"
    else
        echo "❌ Custom domain configuration not found"
        exit 1
    fi
else
    # trycloudflare.com setup - need to get URL from logs
    echo "🔍 Looking for tunnel URL in logs..."
    TUNNEL_URL=\$(sudo journalctl -u $TUNNEL_SERVICE_NAME -n 50 --no-pager | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -1)
    
    if [ -n "\$TUNNEL_URL" ]; then
        echo "✅ Cloudflare Tunnel is active!"
        echo "🌐 External URL: \$TUNNEL_URL"
        echo "\$TUNNEL_URL" > "$PROJECT_DIR/.current_tunnel_url"
    else
        echo "❌ Could not find tunnel URL in logs"
        echo "The tunnel might still be starting up. Wait a moment and try again."
        echo "Check logs with: sudo journalctl -u $TUNNEL_SERVICE_NAME -f"
        exit 1
    fi
fi

echo
echo "📡 Test your Multi-Sensor API:"
if [ "\$USE_CUSTOM" = "true" ]; then
    BASE_URL="https://\$HOSTNAME"
else
    BASE_URL="\$TUNNEL_URL"
fi

echo "   \$BASE_URL/ (Homepage)"
echo "   \$BASE_URL/docs (Swagger UI)"
echo "   \$BASE_URL/sensors (All sensors)"
echo "   \$BASE_URL/sensors/ultrasonic (Distance)"
echo "   \$BASE_URL/sensors/mq135 (Air quality)"
echo "   \$BASE_URL/sensors/dht11 (Temperature/Humidity)"
echo "   \$BASE_URL/sensors/alerts (Alerts)"
echo "   \$BASE_URL/health (Health check)"
echo
echo "📋 Use this URL to connect from any device anywhere in the world!"
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
        sleep 5
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
        sleep 5
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
    tunnel-list)
        cloudflared tunnel list
        ;;
    tunnel-config)
        echo "Current tunnel configuration:"
        cat $CLOUDFLARE_CONFIG_DIR/config.yml
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|enable|disable|login|tunnel-list|tunnel-config}"
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
        echo "  tunnel-list   - List all tunnels"
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
    local USE_CUSTOM=$(cat "$PROJECT_DIR/.use_custom_domain" 2>/dev/null || echo "false")
    
    echo
    print_success "🎉 Setup completed successfully!"
    echo
    echo "📁 Project directory: $PROJECT_DIR"
    echo "🏠 Local API URL: http://$IP:8000"
    echo "📚 API Documentation: http://$IP:8000/docs (Swagger UI)"
    
    if [ "$USE_CUSTOM" = "true" ]; then
        local HOSTNAME=$(cat "$PROJECT_DIR/.tunnel_hostname")
        echo "🌐 External URL: https://$HOSTNAME"
    else
        echo "🌐 External URL: Will be generated when tunnel starts (*.trycloudflare.com)"
    fi
    
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
    echo "🔑 Important Notes:"
    echo "• Free .trycloudflare.com URLs change when tunnel restarts"
    echo "• Use custom domain for permanent URL"
    echo "• Check tunnel URL with: $PROJECT_DIR/manage.sh url"
    echo "• Tunnel logs: sudo journalctl -u $TUNNEL_SERVICE_NAME -f"
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
        sleep 5
        echo
        print_status "Services started! Getting tunnel URL..."
        "$PROJECT_DIR/get_tunnel_url.sh"
    fi
}

# Run main function
main "$@"