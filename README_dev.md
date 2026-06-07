# Introduction

If you prefer not to use the preconfigured Raspberry Pi ISO image, follow this step-by-step guide to set up your Pi manually.

Manual setup is only necessary if you plan to make custom adjustments or modifications. For most users, the preconfigured ISO image is the recommended and easier option. If you make improvements during this process, please consider sharing your contributions with the BroodSense community.

# 1. Install Operating System Using rpi-imager

Install the operating system using the Raspberry Pi Imager: https://github.com/raspberrypi/rpi-imager

**Recommended Settings:**
- **OS:** Raspberry Pi OS 64-bit Lite (current version as of writing: 01.10.2025)
- **Hostname:** broodsense.local
- **Username:** controller
- **Password:** broodsense
- **SSH:** Enable SSH and configure with broodsense.pubkey
- **WiFi:** Configure WiFi credentials during imaging process

# 2. Initialize New Install

## Update Software

```bash
sudo apt update
sudo apt upgrade
```

## Configure WiFi (If Not Set During Imaging)

If WiFi was not configured during the imaging process, you can set it up using `nmcli`:

```bash
sudo nmcli device wifi connect "YOUR_NETWORK_NAME" password "YOUR_NETWORK_PASSWORD"
```

Disable WiFi Power Save for more stable connections:

```bash
sudo raspi_config # -> Advanced Options -> WLAN Power Save -> No
```

Replace `YOUR_NETWORK_NAME` and `YOUR_NETWORK_PASSWORD` with your actual WiFi credentials.
# 3. Set Up BroodSense Repository

First, install Git if it's not already available:
```bash
sudo apt install git
```

Then clone the BroodSense controller software:
```bash
cd /home/controller/
git clone https://github.com/Broodsense/controller.git
```

# 4. Configure Automatic USB Mounting for Headless Operation

## 4.1. Install Required Packages

Update the package list and install the USB device management utility:

```bash
sudo apt update
sudo apt install -y udevil
```

## 4.2. Prepare Mounting Directories

Create and configure the USB mounting directory:

```bash
sudo mkdir -p /media/usb
sudo chown controller:controller /media/usb
sudo chmod 755 /media/usb
```
## 4.3. Configure System Logging

Set up dedicated logging for BroodSense by creating the configuration file `/etc/rsyslog.d/broodsense.conf`:

```bash
if ($programname == "broodsense") then {
    action(type="omfile" file="/var/log/broodsense/broodsense.log")
    stop
}
```

This configuration directs all BroodSense-related logs to a dedicated log file at `/var/log/broodsense/broodsense.log`.

### Configure Log Rotation

To prevent log files from growing too large, create `/etc/logrotate.d/broodsense` with the following configuration:

```bash
/var/log/broodsense/broodsense.log {
    daily
    rotate 7
    missingok
    notifempty
    size 256k
    copytruncate
}
```

This configuration rotates logs daily, keeps 7 days of history, and limits individual log files to 256KB.

## 4.4. Configure udevil
Edit the configuration file:
```bash
sudo nano /etc/udevil/udevil.conf
```

Update these lines as needed:
```bash
# Where USB drives may be mounted
allowed_media_dirs = /media/usb

# Allow only removable and safe block devices
allowed_devices = /dev/sd*, /dev/mmcblk*, /dev/mapper/*

# Forbid system/internal devices
forbidden_devices = /dev/mmcblk0, /dev/zram*, /dev/loop*, /dev/ram*, /dev/dm-*
```

## 4.5. Create a System Service for Devmon
Create the service file:
```bash
sudo nano /etc/systemd/system/devmon.service
```

Paste the following content:
```bash
[Unit]
Description=Devmon USB Automounter
After=local-fs.target

[Service]
ExecStart=/usr/bin/devmon --no-gui --mount-options "nosuid,nodev,noexec"
User=controller
Restart=on-failure
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

[Install]
WantedBy=multi-user.target
```

If the controller user has a different UID (check with `id controller`), update `/run/user/1000` to match the correct UID.

## 4.6. Enable and Start the Service
Reload systemd and enable the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable devmon.service
sudo systemctl start devmon.service
```

## 4.7. Test the Configuration

Verify that USB devices are properly mounted:

```bash
lsblk
ls /media/usb
```

**Expected result:** Your USB device (identified by its label or UUID) should appear under `/media/usb/<device_label>`. When you unplug the USB device, its mount point should disappear automatically.

# 5. Install WittyPi 4 Power Management

WittyPi 4 is a power management HAT for the Raspberry Pi that provides several key features:
- Scheduled power on/off cycles
- Real-time clock that maintains time during power loss
- Support for 6–30V power input, ideal for larger battery setups

To install WittyPi 4:

Download the installer:
```bash
wget https://www.uugear.com/repo/WittyPi4/install.sh
```

Run the installation script:
```bash
sudo sh install.sh
```

Clean up the installer file:
```bash
rm install.sh
```

Look for first occurence of `wittypi_home=...` and change to `wittypi_home="/home/controller/wittypi"` This allows us to source the file and re-use the utilities in our own broodsense scripts.

# 6. Disable Bluetooth to Conserve Energy

Disabling Bluetooth helps reduce power consumption, which is important for battery-operated deployments.

To disable Bluetooth:

1. Open the boot configuration file:
   ```bash
   sudo nano /boot/firmware/config.txt
   ```

2. Add the following line in the "Additional overlays" section:
   ```
   dtoverlay=disable-bt
   ```

**Note:** The following additional steps are typically not necessary for most setups, but may be required in some cases:
```bash
echo "blacklist btusb" | sudo tee -a /etc/modprobe.d/blacklist.conf
echo "blacklist hciuart" | sudo tee -a /etc/modprobe.d/blacklist.conf
```

# 7. Install Scanner Utilities

Install the SANE (Scanner Access Now Easy) utilities required for scanner functionality:

```bash
sudo apt update
sudo apt install sane-utils
```

# 8. Install Upload Dependencies

The upload script requires `curl`, `jq`, and `wireless-tools`:

```bash
sudo apt install curl jq wireless-tools
```

# 8. Install Development Utilities

Install helpful development tools for system administration and debugging:

```bash
sudo apt install tmux
```

Tmux is a terminal multiplexer that allows you to run multiple terminal sessions within a single SSH connection.

# 9. Optional: Setup reverse SSH tunnel

For developers it might be useful to connect via SSH to controllers in the field that have (mobile) internet available. For this, a cloud server must be available where your controller can connect to.

## Cloud server setup for accepting reverse SSH tunnels

1. Generate a key pair on the Raspberry Pi `ssh-keygen -t ed25519 -N "" -f ~/.ssh/reverse_tunnel_key`
2. Copy the key to your cloud server `ssh-copy-id -i ~/.ssh/reverse_tunnel_key` user@cloud_server_ip
3. Test if the login works (Pi -> cloud server): `ssh user@cloud_server_ip`
4. Configure cloud server keep-alives `sudo nano /etc/ssh/sshd_config` and add these lines (allowing the pi to refresh connection in case of errors):

```
ClientAliveInterval 30
ClientAliveCountMax 3
```

5. Restart ssh on cloud server `sudo systemctl restart ssh`

## Controller setup for establishing reverse SSH tunnels

Install dependencies (autossh automatically monitors, manages, and restarts SSH connections or tunnels if they drop. Watchdog restarts the system in case of failures).

```bash
sudo apt install autossh watchdog
```

Create systemd service file
```bash
sudo nano /etc/systemd/system/reverse-ssh.service
```

Paste the following configuration (replace `user` and `cloud_server_ip`. A SSH connection on port 2222 on the cloud server will result in a connection on port 22 on the controller.):

```ini
[Unit]
Description=AutoSSH Reverse Tunnel to Cloud Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Environment="AUTOSSH_GATETIME=0"
Environment="AUTOSSH_POLL=60"
ExecStart=/usr/bin/autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -o "ExitOnForwardFailure=yes" -N -R 2222:localhost:22 user@cloud_server_ip -i /home/controller/.ssh/reverse_tunnel_key

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and restart the service so it runs automatically at boot:

```bash
sudo systemctl daemon-reload
sudo systemctl enable reverse-ssh.service
sudo systemctl start reverse-ssh.service
```

As an additional safety measure we can enable the hardware watchdogs which restarts the pi in case of kernel panics / frozen system. Open the boot config

```bash
sudo nano /boot/firmware/config.txt
```

and add this line at the bottom of the hardware timer (end of file):

```bash
dtparam=watchdog=on
```

Open the watchdog config `sudo nano /etc/watchdog.conf`:

```bash
watchdog-device = /dev/watchdog
watchdog-timeout = 15
```

Enable and start the watchdog service:

```bash
sudo systemctl enable watchdog
sudo systemctl start watchdog
```


# 10. Prepare Image for Release

Before creating a release image, log into your Raspberry Pi and perform the following cleanup steps to ensure no private or unnecessary data is included:

## Remove Private Logs from Testing

```bash
# Check if there are any logs that need removal
sudo journalctl --disk-usage

# Clear all journal logs immediately
sudo journalctl --rotate
sudo journalctl --vacuum-size=1

sudo find /var/log/ -type f -name "*.log" -exec truncate -s 0 {} \;
sudo find /var/log/ -type f -name "*.gz" -exec rm -f {} \;
sudo find /var/log/ -type f -name "*.1" -exec rm -f {} \;
sudo rm -r /var/log/broodsense/
```

There are also logs created by WittyPi that don't need to be included in a release.

```bash
truncate -s 0 ~/wittypi/wittyPi.log
```

Clean dev WiFi networks:

```bash
sudo rm /etc/NetworkManager/system-connections/*
```

## Remove old mount points

```bash
sudo rm -rf /media/usb/*
```

## Remove SSH Keys and Known Hosts

Remove any personal or dev SSH keys, authorized keys, and known hosts entries:

```bash
# Remove known hosts (contains fingerprints of servers you connected to during dev)
rm ~/.ssh/known_hosts

# Remove reverse tunnel key (contains private key to your cloud server)
rm -f ~/.ssh/reverse_tunnel_key ~/.ssh/reverse_tunnel_key.pub

# Remove any authorized_keys added during dev (re-add only the intended release key)
# Review first: cat ~/.ssh/authorized_keys
nano ~/.ssh/authorized_keys
```

## Disable or Remove the Reverse SSH Tunnel Service

If the reverse SSH tunnel was set up during development but is not intended for end users, disable and remove it:

```bash
sudo systemctl disable reverse-ssh.service
sudo systemctl stop reverse-ssh.service
sudo rm /etc/systemd/system/reverse-ssh.service
sudo systemctl daemon-reload
```

## Disable or Enable SSH Password Authentication
If you want to disable password authentication for SSH (recommended for security), edit the SSH server configuration:

```bash
sudo nano /etc/ssh/sshd_config  # PasswordAuthentication no and PubkeyAuthentication yes
```

## Remove Any Active Cron Jobs

Dev runs may have left behind a `scan.sh` cron entry under the controller user:

```bash
crontab -r
```


## Regenerate SSH Host Keys on First Boot

SSH host keys uniquely identify a machine. If all released images share the same keys, any device can be impersonated. Remove them now so that new unique keys are generated automatically on first boot:

```bash
sudo rm /etc/ssh/ssh_host_*
sudo tee /etc/rc.local > /dev/null <<'EOF'
#!/bin/bash
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    dpkg-reconfigure openssh-server
fi
exit 0
EOF
sudo chmod +x /etc/rc.local
```

## Remove /tmp Contents

Clear the `/tmp` directory to remove any temporary files created during development. Also clear the bash history to avoid leaving behind any command history:

```bash
sudo rm -rf /tmp/*
rm ~/.bash_history
history -c
```

## Create the Final Image

Remove the SD card from your Pi and insert it into your computer. Use the `lsblk` command to identify the device name before and after inserting the card.

Assuming your SD card appears as `/dev/sda`, create the image as follows:

```bash
sudo dd if=/dev/sda of=/somewhere/output.img status=progress bs=1M
```

 **Warning:** Double-check that you have the correct device names. Do not mix up the `if` (input/source SD card path) and `of` (output/destination file path) parameters, as this could result in data loss.

## Shrink the Image for Distribution

Since your image will be the same size as your SD card, it's not practical for distribution. [PiShrink](https://github.com/Drewsif/PiShrink) is a convenient tool that removes all empty storage from your image file.

Additionally, PiShrink configures the image so that on first boot, the Raspberry Pi will automatically expand the filesystem to utilize the full capacity of whatever SD card it's written to.
