#!/bin/bash

# Multi-Sensor FastAPI Server Setup Script with Cloudflare Tunnel
# Fixed version - simplified and reliable

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
TUNNEL_NAME="sensor-api-tunnel"

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
        exit 1
    fi
}

cleanup_existing() {
    print_status "Cleaning up existing installation..."
    
    # Stop and disable services
    sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
    sudo systemctl stop $TUNNEL_SERVICE_NAME 2>/dev/null || true
    sudo systemctl disable $SERVICE_NAME 2>/dev/null || true
    sudo systemctl disable $TUNNEL_SERVICE_NAME 2>/dev/null || true
    
    # Remove service files
    sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
    sudo rm -f /etc/systemd/system/${TUNNEL_SERVICE_NAME}.service
    
    # Remove old tunnels (keep only the last 3)
    print_status "Cleaning up old tunnels..."
    OLD_TUNNELS=$(cloudflared tunnel list 2>/dev/null | grep "multi-sensor-tunnel\|sensor-api-tunnel" | head -n -3 | awk '{print $2}' || true)
    if [ -n "$OLD_TUNNELS" ]; then
        for tunnel in $OLD_TUNNELS; do
            print_status "Deleting old tunnel: $tunnel"
            cloudflared tunnel delete "$tunnel" --force 2>/dev/null || true
        done
    fi
    
    # Remove project directory
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
    fi
    
    sudo systemctl daemon-reload
    print_success "Cleanup completed"
}

check_cloudflare_auth() {
    print_status "Checking Cloudflare authentication..."
    
    if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
        print_error "Cloudflare authentication not found!"
        print_status "Please run: cloudflared tunnel login"
        print_status "Then run this script again."
        exit 1
    fi
    
    # Test authentication by listing tunnels
    if ! cloudflared tunnel list >/dev/null 2>&1; then
        print_error "Cloudflare authentication failed!"
        print_status "Please run: cloudflared tunnel login"
        exit 1
    fi
    
    print_success "Cloudflare authentication verified"
}

install_dependencies() {
    print_status "Installing system dependencies..."
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential git curl
    
    # Install cloudflared if not present
    if ! command -v cloudflared &> /dev/null; then
        print_status "Installing cloudflared..."
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi
    
    print_success "Dependencies installed"
}

setup_project() {
    print_status "Setting up project..."
    
    # Check for required files
    if [ ! -f "$HOME/server.py" ] || [ ! -f "$HOME/requirements.txt" ]; then
        print_error "Required files not found in $HOME"
        print_status "Please ensure server.py and requirements.txt are in your home directory"
        exit 1
    fi
    
    # Create project directory
    mkdir -p "$PROJECT_DIR"
    cp "$HOME/server.py" "$PROJECT_DIR/"
    cp "$HOME/requirements.txt" "$PROJECT_DIR/"
    
    # Setup Python environment
    cd "$PROJECT_DIR"
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    
    print_success "Project setup completed"
}

create_tunnel() {
    print_status "Creating Cloudflare tunnel..."
    
    # Delete existing tunnel if it exists
    if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        print_status "Deleting existing tunnel: $TUNNEL_NAME"
        cloudflared tunnel delete "$TUNNEL_NAME" --force 2>/dev/null || true
    fi
    
    # Create new tunnel
    print_status "Creating tunnel: $TUNNEL_NAME"
    cloudflared tunnel create "$TUNNEL_NAME"
    
    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    if [ -z "$TUNNEL_ID" ]; then
        print_error "Failed to get tunnel ID"
        exit 1
    fi
    
    print_success "Tunnel created with ID: $TUNNEL_ID"
    
    # Create tunnel config for trycloudflare (simple approach)
    mkdir -p "$HOME/.cloudflared"
    cat > "$HOME/.cloudflared/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $HOME/.cloudflared/$TUNNEL_ID.json

ingress:
  - service: http://localhost:8000
EOF
    
    # Save tunnel info
    echo "$TUNNEL_ID" > "$PROJECT_DIR/.tunnel_id"
    echo "$TUNNEL_NAME" > "$PROJECT_DIR/.tunnel_name"
    
    print_success "Tunnel configuration created"
}

create_services() {
    print_status "Creating systemd services..."
    
    # API Service
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Multi-Sensor FastAPI Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=$PROJECT_DIR/venv/bin
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Tunnel Service
    sudo tee /etc/systemd/system/${TUNNEL_SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target ${SERVICE_NAME}.service
Requires=${SERVICE_NAME}.service

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/cloudflared tunnel --config $HOME/.cloudflared/config.yml run $TUNNEL_NAME
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Enable services
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service
    sudo systemctl enable ${TUNNEL_SERVICE_NAME}.service
    
    print_success "Services created and enabled"
}

create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Get tunnel URL script
    cat > "$PROJECT_DIR/get_url.sh" << 'EOF'
#!/bin/bash

echo "🔍 Getting Cloudflare tunnel URL..."

# Check if services are running
if ! sudo systemctl is-active --quiet cloudflared-tunnel; then
    echo "❌ Tunnel service not running"
    echo "Start with: sudo systemctl start cloudflared-tunnel"
    exit 1
fi

echo "✅ Tunnel service is running"

# Method 1: Check recent logs for URL
echo "📋 Checking service logs..."
TUNNEL_URL=$(sudo journalctl -u cloudflared-tunnel --since "10 minutes ago" --no-pager -q | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -1)

# Method 2: Get from all available logs
if [ -z "$TUNNEL_URL" ]; then
    echo "📋 Checking all tunnel logs..."
    TUNNEL_URL=$(sudo journalctl -u cloudflared-tunnel --no-pager -q | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -1)
fi

# Method 3: Use the tunnel name to construct URL or get from API
if [ -z "$TUNNEL_URL" ]; then
    echo "🔄 Starting temporary quick tunnel to get URL..."
    # Kill any existing temporary tunnels
    pkill -f "cloudflared.*--url" 2>/dev/null || true
    sleep 2
    
    # Start temporary tunnel in background and capture output
    TEMP_OUTPUT=$(mktemp)
    timeout 20 cloudflared tunnel --url http://localhost:8000 > "$TEMP_OUTPUT" 2>&1 &
    TEMP_PID=$!
    
    # Wait for URL to appear
    for i in {1..15}; do
        if grep -q "trycloudflare.com" "$TEMP_OUTPUT" 2>/dev/null; then
            TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$TEMP_OUTPUT" | head -1)
            break
        fi
        sleep 1
    done
    
    # Clean up
    kill $TEMP_PID 2>/dev/null || true
    rm -f "$TEMP_OUTPUT"
fi

# Method 4: Show what we can find in logs for debugging
if [ -z "$TUNNEL_URL" ]; then
    echo "🔍 Debug - Recent tunnel log entries:"
    sudo journalctl -u cloudflared-tunnel --since "5 minutes ago" --no-pager | tail -10
    echo
    echo "🔍 Looking for any cloudflare URLs in logs:"
    sudo journalctl -u cloudflared-tunnel --no-pager | grep -i "cloudflare\|tunnel\|https" | tail -5
fi

if [ -n "$TUNNEL_URL" ]; then
    echo "✅ Tunnel URL found!"
    echo "🌐 External URL: $TUNNEL_URL"
    echo
    echo "📡 API Endpoints:"
    echo "   $TUNNEL_URL/ (Homepage)"
    echo "   $TUNNEL_URL/docs (Swagger UI)"  
    echo "   $TUNNEL_URL/sensors (All sensors)"
    echo "   $TUNNEL_URL/health (Health check)"
    echo
    echo "$TUNNEL_URL" > /tmp/current_tunnel_url
    
    # Test the URL
    echo "🧪 Testing tunnel connection..."
    if curl -s --connect-timeout 10 "$TUNNEL_URL/health" >/dev/null 2>&1; then
        echo "✅ Tunnel is working correctly!"
    else
        echo "⚠️  Tunnel URL found but API might not be responding"
        echo "   Check if local API is running: curl http://localhost:8000/health"
    fi
else
    echo "❌ Could not get tunnel URL"
    echo
    echo "🔧 Troubleshooting steps:"
    echo "1. Check if API is running locally:"
    echo "   curl http://localhost:8000/health"
    echo
    echo "2. Check tunnel service status:"
    echo "   sudo systemctl status cloudflared-tunnel"
    echo
    echo "3. Try restarting services:"
    echo "   ./manage.sh restart"
    echo
    echo "4. Check logs for errors:"
    echo "   sudo journalctl -u cloudflared-tunnel -f"
fi
EOF
    chmod +x "$PROJECT_DIR/get_url.sh"

    # Main management script
    cat > "$PROJECT_DIR/manage.sh" << EOF
#!/bin/bash

case "\$1" in
    start)
        echo "Starting services..."
        sudo systemctl start $SERVICE_NAME
        sleep 3
        sudo systemctl start $TUNNEL_SERVICE_NAME
        sleep 5
        $PROJECT_DIR/get_url.sh
        ;;
    stop)
        echo "Stopping services..."
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl stop $TUNNEL_SERVICE_NAME
        echo "Services stopped"
        ;;
    restart)
        echo "Restarting services..."
        sudo systemctl restart $SERVICE_NAME
        sleep 3
        sudo systemctl restart $TUNNEL_SERVICE_NAME
        sleep 5
        $PROJECT_DIR/get_url.sh
        ;;
    status)
        echo "=== API Service Status ==="
        sudo systemctl status $SERVICE_NAME --no-pager -l
        echo
        echo "=== Tunnel Service Status ==="
        sudo systemctl status $TUNNEL_SERVICE_NAME --no-pager -l
        ;;
    logs)
        echo "Recent API logs:"
        sudo journalctl -u $SERVICE_NAME -n 20 --no-pager
        echo
        echo "Recent Tunnel logs:"
        sudo journalctl -u $TUNNEL_SERVICE_NAME -n 20 --no-pager
        ;;
    url)
        $PROJECT_DIR/get_url.sh
        ;;
    quick-url)
        # Quick method - start temporary tunnel
        echo "🚀 Starting quick tunnel (30 seconds)..."
        timeout 30 cloudflared tunnel --url http://localhost:8000 2>&1 | grep -o 'https://.*\.trycloudflare\.com' | head -1
        ;;
    test)
        echo "Testing local API..."
        curl -s http://localhost:8000/health || echo "API not responding locally"
        ;;
    debug)
        echo "=== Debug Information ==="
        echo "API Service Status:"
        sudo systemctl is-active $SERVICE_NAME
        echo
        echo "Tunnel Service Status:"
        sudo systemctl is-active $TUNNEL_SERVICE_NAME
        echo
        echo "Local API Test:"
        curl -s http://localhost:8000/health 2>/dev/null && echo "✅ API responding" || echo "❌ API not responding"
        echo
        echo "Tunnel Configuration:"
        cat $HOME/.cloudflared/config.yml 2>/dev/null || echo "Config not found"
        echo
        echo "Recent Tunnel Logs:"
        sudo journalctl -u $TUNNEL_SERVICE_NAME -n 10 --no-pager
        echo
        echo "Looking for trycloudflare URLs in logs:"
        sudo journalctl -u $TUNNEL_SERVICE_NAME --no-pager | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -3
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|url|quick-url|test|debug}"
        echo
        echo "Commands:"
        echo "  start      - Start both services"
        echo "  stop       - Stop both services"
        echo "  restart    - Restart both services"
        echo "  status     - Show service status"
        echo "  logs       - Show recent logs"
        echo "  url        - Get tunnel URL"
        echo "  quick-url  - Get URL with temporary tunnel"
        echo "  test       - Test local API"
        echo "  debug      - Show debug information"
        ;;
esac
EOF
    chmod +x "$PROJECT_DIR/manage.sh"
    
    print_success "Management scripts created"
}

display_final_info() {
    local IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    
    echo
    print_success "🎉 Setup completed successfully!"
    echo
    echo "📁 Project Directory: $PROJECT_DIR"
    echo "🏠 Local API: http://$IP:8000"
    echo "📚 Local Docs: http://$IP:8000/docs"
    echo "🌐 External Access: Run ./manage.sh url to get tunnel URL"
    echo
    echo "🚀 Quick Commands:"
    echo "  cd $PROJECT_DIR"
    echo "  ./manage.sh start     # Start everything"
    echo "  ./manage.sh url       # Get public URL"
    echo "  ./manage.sh status    # Check status"
    echo "  ./manage.sh logs      # View logs"
    echo
    echo "📡 API Endpoints:"
    echo "  /                    - Homepage"
    echo "  /docs               - Interactive API docs"
    echo "  /sensors            - All sensor readings"
    echo "  /sensors/ultrasonic - Distance reading"
    echo "  /sensors/mq135      - Air quality"
    echo "  /sensors/dht11      - Temperature/humidity"
    echo "  /health             - Health check"
    echo
    echo "📋 Sensor Wiring:"
    echo "  HC-SR04: Trig→GPIO18, Echo→GPIO24, VCC→5V, GND→GND"
    echo "  DHT11: Data→GPIO22, VCC→3.3V, GND→GND"
    echo "  MQ-135: A0→MCP3008→SPI, VCC→5V, GND→GND"
}

# Main execution
main() {
    echo "🚀 Multi-Sensor API Setup (Fixed Version)"
    echo "=========================================="
    
    check_root
    check_cloudflare_auth
    cleanup_existing
    install_dependencies
    setup_project
    create_tunnel
    create_services
    create_management_scripts
    
    display_final_info
    
    echo
    read -p "Start services now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$PROJECT_DIR"
        ./manage.sh start
    else
        echo "To start later, run: cd $PROJECT_DIR && ./manage.sh start"
    fi
    
    print_success "Setup complete! 🎉"
}

# Run the main function
main "$@"