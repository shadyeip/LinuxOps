# LinuxOps
Helpful Linux tools

## VPN Manager Script

A Bash script for managing OpenVPN and WireGuard VPN connections on Linux systems. This script provides a unified interface for handling multiple VPN configurations, making it easy to switch between different VPN connections and manage their configurations.

### Features

- Supports both OpenVPN and WireGuard VPN protocols
- Automatic VPN type detection
- Seamless switching between VPN connections
- Configuration installation with proper permissions
- Detailed status monitoring and logging
- Color-coded output for better readability

### Prerequisites

- Root privileges
- OpenVPN and/or WireGuard installed on your system
- Systemd-based Linux distribution

### Installation

1. Copy the script to a location in your PATH (e.g., `/usr/local/bin/`):
```bash
sudo cp vpn-switcher.sh /usr/local/bin/vpn
sudo chmod +x /usr/local/bin/vpn
```

2. Ensure the required directories exist:
```bash
sudo mkdir -p /etc/openvpn/client
sudo mkdir -p /etc/wireguard
```

### Usage

#### Basic Commands

```bash
vpn {command} [options]
```

#### Available Commands

- `start [config]` - Start a VPN connection
- `stop` - Stop active VPN connection
- `list` - List available VPN configurations
- `status` - Show VPN status
- `install <file> <name>` - Install a VPN configuration file

#### Examples

```bash
# List available configurations
vpn list

# Start VPN using 'work' configuration
vpn start work

# Stop active VPN connection
vpn stop

# Show current VPN status
vpn status

# Install a new configuration
vpn install ~/work.conf work
```

### Configuration Files

- OpenVPN configurations should be placed in `/etc/openvpn/client/`
- WireGuard configurations should be placed in `/etc/wireguard/`
- All configuration files should have `.conf` extension

### Security Features

- Automatic permission setting for configuration files (600)
- Root-only access enforcement
- Secure handling of configuration files
- Proper ownership settings (root:root)

### Logging

The script logs all operations to `/var/log/vpn-switcher.log`, including:
- Connection attempts
- Configuration changes
- Error messages
- Status changes

### Troubleshooting

1. If a VPN fails to connect:
   - Check the logs at `/var/log/vpn-switcher.log`
   - Verify configuration file permissions
   - Ensure the VPN service is properly installed

2. If configuration installation fails:
   - Verify you have root privileges
   - Check if the source configuration file exists
   - Ensure the target directories are writable

### Notes

- Only one VPN connection can be active at a time
- The script automatically handles switching between different VPN connections
- Configuration files are automatically detected as OpenVPN or WireGuard based on their content
- Associated files (certificates, keys) are automatically installed with OpenVPN configurations

### Error Codes

The script returns the following exit codes:
- 0: Success
- 1: General error (wrong permissions, missing files, etc.)
