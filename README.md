# nut-upsd

This is a **nut-upsd** Docker image, implementing the UPS drivers and the upsd daemon from https://networkupstools.org/.

The idea behind this implementation is to have a generic container, which supports monitoring multiple UPS devices from the same container.
This is different from other implementations, which are intended to support one (1) container per one (1) UPS.

The drawback of this implementation is that the container can't be easily driven by environment variables, since it can support any valid NUT config, rather than being limited to a subset of drivers (e.g. support for only USB or serial is common to see with other NUT images).

So instead, traditional config files have to be slipped into the container by use of a config volume mount.

> [!NOTE]
> This repository builds on the great work of [Gianpaolo Del Matto](https://github.com/gpdm). Thank you.

## How to Use

Pull as usual:

```sh
docker pull ghcr.io/tigattack/nut-upsd[:<tag>]
```

See [ghcr.io/tigattack/nut-upsd](https://github.com/users/tigattack/packages/container/package/nut-upsd) for a list of valid tags.

Then run it as follows:

```sh
docker run -d \
   -p 3493:3493 \
   -v /path/to/nut-config:/etc/nut:ro \
   [ -e NUT_UID=... ] \
   [ -e NUT_GID=... ] \
   [ --privileged | --device ... ] \
   ghcr.io/tigattack/nut-upsd[:<tag>]
```

### Environment Variables

* `NUT_UID`: NUT user ID. NUT drops privileges to this user after starting as described in [upsd(8)](https://networkupstools.org/docs/man/upsd.html). While this env var has no default, the default NUT user ID is `100` in this image.
* `NUT_GID`: NUT group ID. While this env var has no default, the default NUT group ID is `101` in this image.

## Configuration

### Main Config for upsd

As this image runs only the UPS drivers and the upsd daemon itself, you only need these configuration files:

* [ups.conf](https://networkupstools.org/docs/man/nut.conf.html)
* [upsd.conf](https://networkupstools.org/docs/man/upsd.conf.html)
* [upsd.users](https://networkupstools.org/docs/man/upsd.users.html)

This Docker image cannot be configured through environment variables. You have to use a config volume as shown:

1. Create the *ups.conf*, *upsd.conf* and *upsd.users* config files with your favourite editor
2. Store them into a permanent config directory, e.g. `/opt/nut-upsd`
3. Apply proper file permissions and ownership.  
   `<UID>` should be the value you gave to the `NUT_UID` env var, or `100` if unspecified.  
   `<GID>` should be the value you gave to the `NUT_GID` env var, or `101` if unspecified.
   ```sh
   cd /opt/nut-upsd
   chmod 0640 ups.conf upsd.conf upsd.users
   chown <UID>:<GID> ups.conf upsd.conf upsd.users
   # Example: chown 100:101 ups.conf upsd.conf upsd.users
   ```
4. When running the container, point it mount the config directory as a volume, e.g.
   `-v /opt/nut-upsd:/etc/nut:ro`

> [!TIP]
> The container will fail to start when no volume is mounted, or not all needed files are present!

Some sample config files are provided for your conventience in the [example_confs/etc/nut](example_confs/etc/nut) directory. You may use them as a starting point, however I recommend having an in-depth look at the official [Network UPS Tools](https://networkupstools.org/) documentation.

You can find example udev rules for USB UPS's in [example_confs/etc/udev/rules.d/62-nut-usbups.rules](example_confs/etc/udev/rules.d/62-nut-usbups.rules).

## Device Mapping

In order for the UPS monitoring to work, you have to map your device tree into the Docker container.

### Privileged Mode

Just pass this option to the container at startup: `--privileged`

> [!WARNING]
> This is the least secure approach, as it grants the container an excessive amount of privileges on the host system.

### Device Mode

A better choice than privileged mode is to pass just the individual devices into the container.

This can be done by passing `--device` and `--device-cgroup-rule` commands to Docker.

First, identify the `device-id`, i.e. by running `lsusb`:

```sh
$ lsusb
Bus 007 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 004 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 008 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 006 Device 002: ID 0665:5161 Cypress Semiconductor USB to serial # << generic UPS on USB
Bus 006 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 005 Device 002: ID 051d:0002 American Power Conversion Uninterruptible Power Supply # << APC UPS on USB
Bus 005 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
```

The example above reveals two UPS's attached, one to Bus 6, as device #2, the other on Bus 5, as device #2.
This translates to the following device paths:

```
/dev/bus/usb/005/002
/dev/bus/usb/006/002
```

Get the device major and minor device number like this:

```sh
$ ls -l  /dev/bus/usb/005/002 /dev/bus/usb/006/002
crwxrwxrwx 1 root root 189, 513 Oct  8 22:06 /dev/bus/usb/005/002
crwxrwxrwx 1 root root 189, 641 Oct  8 22:06 /dev/bus/usb/006/002
```

The values we're looking for is in columns 5 and 6 respectively.

To map these devices now into the container, the devices have to be passed in, together with a control group rule each, matching the major and minor device number.

```sh
docker run [ ... ] \
  --device /dev/bus/usb/005/002 --device-cgroup-rule='c 189:513 rw'
  --device /dev/bus/usb/006/002 --device-cgroup-rule='c 189:641 rw'
  [ ... ]
```

If you see "access denied" or "insufficient permissions" errors and your container's cgroup rules are correct, you may need to configure udev rules on your host (see example: [example_confs/etc/udev/rules.d/62-nut-usbups.rules](example_confs/etc/udev/rules.d/62-nut-usbups.rules)).

### Persistent Device Name

When restarting or reconnecting the UPS over USB, the bus ID can change. This renders the device mapping into the container useless as it will be mapping a non-existent or other device into your container.

To fix this, we need to set a udev rule to symlink the device to another name. We will set this in `/etc/udev/rules.d/62-nut-usbups.rules` that we created on setup, and will use our vendor and product attributes for our UPS.

This example is using a Eaton UPS with a vendor ID of `0463` and product ID of `ffff`, and I am mapping this to group `1000`, with a symlink set to `ups` which will result in our device being symlinked to `/dev/ups`.

```sh
$ cat /etc/udev/rules.d/62-nut-usbups.rules
ACTION=="remove", GOTO="nut-usbups_rules_end"
SUBSYSTEM=="usb_device", GOTO="nut-usbups_rules_real"
SUBSYSTEM=="usb", GOTO="nut-usbups_rules_real"
GOTO="nut-usbups_rules_end"

LABEL="nut-usbups_rules_real"
ATTR{idVendor}=="0463", ATTR{idProduct}=="ffff", MODE="664", GROUP="1000", SYMLINK+="ups"

LABEL="nut-usbups_rules_end"
```

Next, either run the following two commands to reload and trigger the udev rules (or restart the device):

```sh
$ sudo udevadm control -R && sudo udevadm trigger
```

We can then check if this is working with `ls -l /dev/ups`

```sh
$ ls -l /dev/ups
lrwxrwxrwx 1 root root 15 Feb 27 21:39 /dev/ups -> bus/usb/001/006
```

### Handling Device Reconnection

When the USB device is replugged, the container will in some cases not rebind the device.

This can be fixed by restarting the container, however we would preferably want to automate this process, so we don't have to connect to the machine to restart NUT.

To automate this, we can append a `RUN` parameter to our udev rule. The `RUN` parameter will run a command when the device is connected. This is recommended to be used in conjunction with the persistent device symlink as above:

```sh
$ cat /etc/udev/rules.d/62-nut-usbups.rules 
ACTION=="remove", GOTO="nut-usbups_rules_end"
SUBSYSTEM=="usb_device", GOTO="nut-usbups_rules_real"
SUBSYSTEM=="usb", GOTO="nut-usbups_rules_real"
GOTO="nut-usbups_rules_end"

LABEL="nut-usbups_rules_real"
ATTR{idVendor}=="0463", ATTR{idProduct}=="ffff", MODE="664", GROUP="1000", SYMLINK+="ups", RUN+="/bin/bash /home/user/nut/run.sh"

LABEL="nut-usbups_rules_end"
```

In this example, this will run `/bin/bash /home/user/nut/run.sh`, which contains the commands to stop, remove, and run the container.
