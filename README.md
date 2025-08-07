# softether-vpn-deb

Pre-built SoftEther VPN deb packages for Ubuntu, with enabled "Enterprise Functions":
 - RADIUS / NT Domain user authentication
 - RSA certificate authentication
 - Deep-inspect packet logging
 - Source IP address control list
 - syslog transfer
 - Classless Static Route support (DHCP option 121)

Script to download and install SoftEther VPN components from GitHub repository

Downloads via jsDelivr CDN with GitHub raw as backup

Dynamically detects .deb package names with version numbers (e.g., softether-common\_5.2.5187\_amd64.deb) using bash regex

Automatically installs common and vpncmd, allows user to select vpnclient, vpnserver, vpnclient+vpnserver, or vpnbridge

Installs common first, uninstalls it last to respect dependencies

Displays version numbers in the menu

Supports uninstalling all components and services

Sets up and starts corresponding systemd services for installations

## Usage:

```bash
curl -sL https://raw.githubusercontent.com/parkycai/softether-vpn-deb/main/install_softether.sh | sudo bash
```

## Or use jsdelivr:

```bash
curl -sL https://cdn.jsdelivr.net/gh/parkycai/softether-vpn-deb@latest/install_softether.sh | sudo bash
```

## Thanks

SoftEther VPN, Grok
