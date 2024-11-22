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
   -v /path/to/nut-config:/etc/nut \
   [ --privileged | --device ... ] \
   ghcr.io/tigattack/nut-upsd[:<tag>]
```


## Configuration

### Main Config for upsd

As this image runs only the UPS drivers and the upsd daemon itself, you only need these configuration files:

* [ups.conf](https://networkupstools.org/docs/man/nut.conf.html)
* [upsd.conf](https://networkupstools.org/docs/man/upsd.conf.html)
* [upsd.users](https://networkupstools.org/docs/man/upsd.users.html)

This Docker image cannot be configured through environment variables. You have to use a config volume as shown:

1. Create the *ups.conf*, *upsd.conf* and *upsd.users* config files with your favourite editor
2. Store them into a permanent config directory, e.g. `/data/dockers/nut-upsd/config`
3. Apply proper file permissions and ownership
 ```sh
  cd /data/dockers/nut-upsd/config
  chmod 0440 ups.conf upsd.conf upsd.users
  chown 100:101 ups.conf upsd.conf upsd.users
 ```
4. When running the container, point it mount the config directory as a volume, e.g.
   `-v /data/dockers/nut-upsd/config:/etc/nut`

**The container will fail to start when no volume is mounted, or not all needed files are present!**

Some sample config files are provided for your conventience in the [example_confs/etc/nut](example_confs/etc/nut) directory. You may use them as a starting point, however I recommend having an in-depth look at the official [Network UPS Tools](https://networkupstools.org/) documentation.

## Device Mapping

In order for the UPS monitoring to work, you have to map your device tree into the docker container.

### Privileged Mode

Just pass this option to the container at startup: `--privileged`

> [!WARNING]
> This is the least secure approach, as it grants the container an excessive amount of privileges on the host system.

### Device Mode

A batter choice than privileged mode is to pass just the individual devices into the container.

This can be done by passing `--device` and `--device-cgroup-rule` commands to docker.

First, identify the `device-id`, i.e. by running `lsusb`:

```sh
$ lsusb
Bus 007 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 004 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 003 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 008 Device 002: ID 0bc2:331a Seagate RSS LLC
Bus 008 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 006 Device 002: ID 0665:5161 Cypress Semiconductor USB to serial                    # << generic UPS on USB
Bus 006 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 005 Device 002: ID 051d:0002 American Power Conversion Uninterruptible Power Supply # << APC UPS on USB
Bus 005 Device 001: ID 1d6b:0001 Linux Foundation 1.1 root hub
Bus 002 Device 002: ID f400:f400
Bus 002 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

The example above reveals two UPS's attached, one to Bus 5, as device #2, the other on Bus 6, as device #2.
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
