# BroodSense Controller
This repository contains the software for operating a BroodSense monitoring device, along with 3D models for printing a suitable casing for Dadant hives.

![BroodSense Scanner Assembly](./broodsense_3d_models/BroodSense%20Scanner%20step%209.png)


# Releases
See [broodsense.com/downloads](broodsense.com/downloads) for all available software releases. A guide for installing the SD card image can be found [here](broodsense.com/diy#software).

# Configure Pi
## Write Configuration
1. Insert an empty USB device into the controller.
2. Power on the controller by pressing the WittyPi start button.
3. The controller copies a config template to the USB device and then powers off automatically.
4. Remove the USB device, connect it to a computer, and edit the `config.env` file as needed.
5. Reinsert the USB device (with the updated `config.env`) into the controller.
6. Power on the controller manually (button) and wait for the first cycle to complete.
7. Subsequent cycles will be managed automatically by the WittyPi scheduler.


## Available Settings in `config.env`

- **current_time**: Manually set the device time in ISO format (`YYYY-MM-DDTHH:MM:SS`). The controller syncs to this time on first start. Without a coin cell battery, the device loses time when powered off; with one, time is retained for years.
- **study_start**: Scan start time (ISO format).
- **study_end**: Scan end time (ISO format).
- **scan_resolution**: Scan resolution in dpi. Options: 300, 600, 1200, 2400. Recommended: 1200.
- **scan_interval**: Interval between scans (minutes).
- **scan_area**: Scan area. Options: `A4`, `A5-left`, `A5-right`.
- **DEBUG**: Set to `1` to disable automatic poweroff for debugging.
- **UPDATE**: Set to `1` to enable code updates from online or USB sources.

# Good to Know
- When the voltage drop is too low to start or survive boot, the controller will not recover. Connect with fresh battery and trigger a first cycle manually.


# Software Cycle

1. The device is triggered manually (button) or automatically waken up by the WittyPi
2. The wake up reason is logged. All logs can be found in `/var/logs/broodsense/broodsense.log`. If a USB device is connected, logs are copied there, too.
3. If no USB device is found, the device is shutdown.
4. The settings are read from the USB device. If no settings are found, the default settings are copied to the USB device and the controller is shut down.
5. If a config file was found, the wittyPi scheduler is configured to reflect the config (e.g. next startup time). If debug flag is set in the config, the Pi will not end this cycle but has to be powered off manually.
6. If in debug mode, the wifi will be powered on and will connect to known WiFi networks (a wifi network (e.g. mobile hotspot) with SSID "broodsense" and password "broodsense" is hard coded and will be found).
7. If in debug mode, the controller will try to pull the broodsense controller repository. If possible, it will try to clone from https://github.com/Broodsense/controller.git, otherwise it will try to clone from USB/.broodsense (which is a bare copy of the online git repo which can be placed on the USB using an external computer and `git clone --bare URL`).
8. If the current cycle was started automatically or is in debug mode, a scan is performed with the settings from the USB device.
9. The device is powered off, unless it's in debug mode.
10. Logs can be found on the controller in `/var/logs/broodsense/broodsense.log` and, if possible, on the USB device in `USB/broodsense.log`.

# Update

## Update from Internet
1. Create a WiFi network with SSID `broodsense` and password `broodsense` (e.g., mobile hotspot).
2. Set `UPDATE=1` in your `config.env` file.
3. Power on the controller.

The controller will automatically connect to the WiFi network and update the software from the online repository.

## Store Bare Repository on USB

If no WiFi connection is available, you can provide updates via USB:

1. On an external computer with the USB device connected, run:
   ```bash
   git clone --bare https://github.com/Broodsense/controller.git USB/controller.git
   ```
2. Set `UPDATE=1` in your `config.env` file.
3. The controller will detect and use the bare repository for updates.

# Develop
There is a second README for developers that want to add some customization [here](./README_dev.md)

# Good to Know

## 3D Models
If you’re looking for printable casing components, the STL files are available in .[./broodsense_3d_models](./broodsense_3d_models/). For custom designs, refer to the Canon LiDe 300 model as a basis. You will need four M4 brass inserts, four 40 mm M4 screws, and several 10 mm wood screws. Further guidance on assembling a device is provided at broodsense.com/diy](broodsense.com/diy).

## Energy Consumption
- 300dpi
  - 28s (script execution)
  - 10mAh / 52 mWh (power consumption, incl. power on/off)
- 600dpi
  - 40s (script execution)
  - 15mAh / 74 mWh (power consumption, incl. power on/off)
- 1200dpi
  - 125s (script execution)
  - 31mAh / 157 mWh (power consumption, incl. power on/off)
- 2400dpi
  - 509s (script execution)
  - 111mAh / 556 mWh (power consumption, incl. power on/off)

- time to boot: 33s
- time to poweroff: 10s

## Shortest Scan Intervals
- 300dpi: 2min
- 600dpi: 2min
- 1200dpi: 3min
- 2400dpi: 10min
