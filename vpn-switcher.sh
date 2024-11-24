#!/bin/bash

# Configuration paths
OPENVPN_CONFIG_DIR="/etc/openvpn/client"
WIREGUARD_CONFIG_DIR="/etc/wireguard"
LOG_FILE="/var/log/vpn-manager.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function for logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root${NC}"
        exit 1
    fi
}

# Function to find VPN type from config name
get_vpn_type() {
    local config_name="$1"
    local vpn_type=""
    
    if [ -f "${OPENVPN_CONFIG_DIR}/${config_name}.conf" ]; then
        vpn_type="openvpn"
    elif [ -f "${WIREGUARD_CONFIG_DIR}/${config_name}.conf" ]; then
        vpn_type="wireguard"
    fi
    
    log_message "Detecting VPN type for config: $config_name (Type: $vpn_type)"
    printf "%s" "$vpn_type"
}

# Function to check if any VPN is active
check_active_vpn() {
    # Check OpenVPN
    if systemctl is-active --quiet openvpn-client@*; then
        local active_ovpn=$(systemctl list-units --plain "openvpn-client@*.service" | grep "running" | head -n1 | cut -d"@" -f2 | cut -d"." -f1)
        echo "${active_ovpn}:openvpn"
        return 0
    fi

    # Check WireGuard
    if [ -n "$(wg show interfaces 2>/dev/null)" ]; then
        local active_wg=$(wg show interfaces)
        echo "${active_wg}:wireguard"
        return 0
    fi

    return 1
}

# Function to start a VPN connection
start_vpn() {
    local config_name="$1"
    local vpn_type
    
    vpn_type=$(get_vpn_type "$config_name")
    
    log_message "Starting VPN with config: $config_name (Type: $vpn_type)"
    
    if [ -z "$vpn_type" ]; then
        echo -e "${RED}Error: Configuration '${config_name}' not found${NC}"
        log_message "Error: Configuration not found"
        echo "Available configurations:"
        list_configs
        exit 1
    fi
    
    local active_vpn=$(check_active_vpn)
    if [ -n "$active_vpn" ]; then
        local current_config=${active_vpn%:*}
        
        if [ "$current_config" = "$config_name" ]; then
            echo -e "${YELLOW}VPN '${config_name}' is already active${NC}"
            log_message "VPN already active"
            exit 0
        else
            echo -e "${BLUE}Stopping active VPN: ${current_config}${NC}"
            log_message "Stopping active VPN: $current_config"
            stop_vpn
        fi
    fi
    
    # Start VPN connection
    local vpn_interface=""
    case "$vpn_type" in
        openvpn)
            vpn_interface="tun0"
            log_message "Starting OpenVPN connection"
            systemctl start "openvpn-client@${config_name}"
            ;;
        wireguard)
            vpn_interface="$config_name"
            log_message "Starting WireGuard connection"
            wg-quick up "$config_name"
            ;;
    esac
    
    # Wait for interface and connection
    echo -n "Waiting for VPN interface to come up"
    log_message "Waiting for interface $vpn_interface to come up"
    for i in {1..10}; do
        if ip link show "$vpn_interface" &>/dev/null; then
            if [ "$vpn_type" = "wireguard" ]; then
                if wg show "$vpn_interface" &>/dev/null; then
                    echo -e "\n${GREEN}WireGuard interface $vpn_interface is up and configured${NC}"
                    log_message "WireGuard interface is up"
                    break
                fi
            elif [ "$vpn_type" = "openvpn" ]; then
                if systemctl status "openvpn-client@${config_name}" | grep -q "Initialization Sequence Completed"; then
                    echo -e "\n${GREEN}OpenVPN interface $vpn_interface is up${NC}"
                    log_message "OpenVPN interface is up"
                    break
                fi
            fi
        fi
        echo -n "."
        sleep 1
        if [ "$i" -eq 10 ]; then
            echo -e "\n${RED}Error: VPN interface failed to come up${NC}"
            log_message "Error: Interface failed to come up"
            stop_vpn
            exit 1
        fi
    done
    
    echo -e "${GREEN}Started ${vpn_type} connection: ${config_name}${NC}"
    log_message "VPN started successfully"
}

# Function to stop VPN connections
stop_vpn() {
    local active_vpn=$(check_active_vpn)
    
    if [ -n "$active_vpn" ]; then
        local config=${active_vpn%:*}
        local type=${active_vpn#*:}
        
        case "$type" in
            openvpn)
                systemctl stop "openvpn-client@${config}"
                echo -e "${GREEN}Stopped OpenVPN connection: ${config}${NC}"
                ;;
            wireguard)
                wg-quick down "$config"
                echo -e "${GREEN}Stopped WireGuard connection: ${config}${NC}"
                ;;
        esac
    else
        echo -e "${YELLOW}No active VPN connections found${NC}"
    fi
}

# Function to list available configurations
list_configs() {
    local active_vpn=$(check_active_vpn)
    local active_config=""
    if [ -n "$active_vpn" ]; then
        active_config=${active_vpn%:*}
    fi

    echo -e "${BLUE}Available VPN configurations:${NC}"
    
    # List OpenVPN configs
    for conf in "${OPENVPN_CONFIG_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local config_name=$(basename "$conf" .conf)
        if [ "$active_config" = "$config_name" ]; then
            echo -e "  ${GREEN}${config_name} (active - OpenVPN)${NC}"
        else
            echo "  ${config_name} (OpenVPN)"
        fi
    done
    
    # List WireGuard configs
    for conf in "${WIREGUARD_CONFIG_DIR}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local config_name=$(basename "$conf" .conf)
        if [ "$active_config" = "$config_name" ]; then
            echo -e "  ${GREEN}${config_name} (active - WireGuard)${NC}"
        else
            echo "  ${config_name} (WireGuard)"
        fi
    done
}

# Function to install VPN configuration
install_config() {
    local source_file="$1"
    local config_name="$2"
    
    # Detect VPN type
    if grep -q "^\[Interface\]" "$source_file"; then
        vpn_type="wireguard"
        target_dir="$WIREGUARD_CONFIG_DIR"
    elif grep -q "^client$\|^remote \|^dev tun" "$source_file"; then
        vpn_type="openvpn"
        target_dir="$OPENVPN_CONFIG_DIR"
    else
        echo -e "${RED}Error: Unable to determine VPN type${NC}"
        exit 1
    fi
    
    # Create target directory if it doesn't exist
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
        chmod 755 "$target_dir"
        chown root:root "$target_dir"
    fi
    
    local target_file="${target_dir}/${config_name}.conf"
    
    # Check if config already exists
    if [ -f "$target_file" ]; then
        echo -e "${YELLOW}Warning: Configuration '$config_name' already exists.${NC}"
        read -p "Do you want to overwrite it? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Installation aborted.${NC}"
            exit 1
        fi
    fi
    
    # Copy and secure the configuration
    cp "$source_file" "$target_file"
    chown root:root "$target_file"
    chmod 600 "$target_file"
    
    echo -e "${GREEN}Successfully installed ${vpn_type} configuration: ${config_name}${NC}"
    
    # Additional checks for OpenVPN related files
    if [ "$vpn_type" = "openvpn" ]; then
        local dir=$(dirname "$source_file")
        local base=$(basename "$source_file" .conf)
        
        # Check for common associated files
        for ext in crt key pem ovpn; do
            local related_file="${dir}/${base}.${ext}"
            if [ -f "$related_file" ]; then
                local target_related="${target_dir}/${config_name}.${ext}"
                cp "$related_file" "$target_related"
                chown root:root "$target_related"
                chmod 600 "$target_related"
                echo -e "${GREEN}Installed related file: ${config_name}.${ext}${NC}"
            fi
        done
    fi
}

# Function to show VPN status
status_vpn() {
    local active_vpn=$(check_active_vpn)
    
    if [ -n "$active_vpn" ]; then
        local config=${active_vpn%:*}
        local type=${active_vpn#*:}
        
        echo -e "${GREEN}Active VPN: ${config} (${type})${NC}"
        
        case "$type" in
            openvpn)
                systemctl status "openvpn-client@${config}" --no-pager
                ;;
            wireguard)
                wg show "$config"
                ;;
        esac
    else
        echo -e "${YELLOW}No active VPN connections${NC}"
    fi
}

# Print usage
print_usage() {
    echo "Usage: vpn {command} [options]"
    echo
    echo "Commands:"
    echo "  start [config]              Start a VPN connection (lists configs if none specified)"
    echo "  stop                        Stop active VPN connection"
    echo "  list                        List available VPN configurations"
    echo "  status                      Show VPN status"
    echo "  install <file> <name>       Install a VPN configuration file"
    echo
    echo "Examples:"
    echo "  vpn start                   Show available configurations"
    echo "  vpn start work              Start VPN using 'work' configuration"
    echo "  vpn stop                    Stop active VPN connection"
    echo "  vpn list                    List all available configurations"
    echo "  vpn status                  Show VPN status"
    echo "  vpn install ~/work.conf work Install configuration as 'work'"
}

# Main command processing
check_root

case "$1" in
    start)
        if [ -z "$2" ]; then
            echo -e "${BLUE}Please select a configuration to start:${NC}"
            list_configs
            exit 0
        fi
        start_vpn "$2"
        ;;
    stop)
        stop_vpn
        ;;
    list)
        list_configs
        ;;
    status)
        status_vpn
        ;;
    install)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Both source file and configuration name are required${NC}"
            echo "Usage: vpn install <source_file> <config_name>"
            exit 1
        fi
        install_config "$2" "$3"
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
