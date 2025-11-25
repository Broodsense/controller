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

If WiFi was not configured during the imaging process, you can set it up manually:

Edit the WiFi configuration file:

```bash
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

Add your network configuration:

```bash
network={
    ssid="YOUR_NETWORK_NAME"
    psk="YOUR_NETWORK_PASSWORD"
    key_mgmt=WPA-PSK
}
```

Replace `YOUR_NETWORK_NAME` and `YOUR_NETWORK_PASSWORD` with your actual WiFi credentials.
Start your Pi.
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

# 8. Install Development Utilities

Install helpful development tools for system administration and debugging:

```bash
sudo apt install tmux
```

Tmux is a terminal multiplexer that allows you to run multiple terminal sessions within a single SSH connection.


# 9. Prepare Image for Release

Before creating a release image, log into your Raspberry Pi and perform the following cleanup steps to ensure no private or unnecessary data is included:

## Remove Private Logs from Testing

```bash
# Check if there are any logs that need removal
sudo journalctl --disk-usage

# Clear all journal logs immediately
sudo journalctl --vacuum-size=0M

sudo find /var/log/ -type f -name "*.log" -exec truncate -s 0 {} \;
sudo find /var/log/ -type f -name "*.gz" -exec rm -f {} \;
sudo find /var/log/ -type f -name "*.1" -exec rm -f {} \;
```

There are also logs created by WittyPi that don't need to be included in a release.

```bash
truncate -s 0 ~/wittypi/wittyPi.log
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