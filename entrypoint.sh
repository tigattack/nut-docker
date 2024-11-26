#!/bin/sh
#
#  Provided to you under the terms of the Simplified BSD License.
#
#  Copyright (c) 2019. Gianpaolo Del Matto, https://github.com/gpdm, <delmatto _ at _ phunsites _ dot _ net>
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
#  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
#  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Hack to print udev rules
if [ "$1" = "dump-udev-rules" ]; then
    upsd -V | sed 's/upsd //'
    cat /lib/udev/rules.d/62-nut-usbups.rules
    exit 0
fi

nutCfgVolume="/etc/nut"
nutCfgFiles="ups.conf upsd.conf upsd.users"
nutUser="nut"
nutUid=`id -u nut`
nutGid=`id -g nut`

echo "*** NUT upsd pre-start checks ***"

# Check if NUT_UID and NUT_GID are set; if so, modify the existing nut user and group
if [ -n "$NUT_UID" ] && [ -n "$NUT_GID" ]; then
    echo "NUT_UID and NUT_GID provided: NUT_UID=$NUT_UID, NUT_GID=$NUT_GID"

    # Update the nut group ID
    if [ "$nutGid" != "$NUT_GID" ]; then
        echo "Updating GID of group '$nutUser' from $nutGid to $NUT_GID"
        groupmod -g "$NUT_GID" $nutUser || { echo "ERROR: Failed to modify group ID"; exit 1; }
        nutGid=$NUT_GID
    fi

    # Update the nut user ID
    if [ "$nutUid" != "$NUT_UID" ]; then
        echo "Updating UID of user '$nutUser' from $nutUid to $NUT_UID"
        usermod -u "$NUT_UID" -g "$NUT_GID" $nutUser || { echo "ERROR: Failed to modify user ID"; exit 1; }
        nutUid=$NUT_UID
    fi

    # Fix ownership of files and directories associated with the updated user/group
    echo "Updating ownership of /var/run/nut"
    chown -Rv "$NUT_UID:$NUT_GID" /var/run/nut || { echo "ERROR: Failed to update ownership of /var/run/nut"; exit 1; }

else
    echo "NUT_UID and NUT_GID not provided. Using default user (UID=$nutUid, GID=$nutGid)."
fi

# Sanity check: Ensure the config volume is mounted
if grep ${nutCfgVolume} /proc/mounts >/dev/null; then
    echo "Config volume is mounted at ${nutCfgVolume}."
else
    echo "ERROR: A config volume must be mounted at ${nutCfgVolume}. Have a look at the README for instructions."
    exit 1
fi

# More sanity: Make sure config files exist and have correct permissions
for cfgFile in ${nutCfgFiles}; do
    if [ -f ${nutCfgVolume}/${cfgFile} ]; then
        # Warn if permissions and ownership are incorrect or too permissive
        stat -c '%a' ${nutCfgVolume}/${cfgFile} | fold -w1 | {
            read user
            read group
            read other
            if [ "$user" -gt 6 ] || [ "$group" -gt 4 ] || [ "$other" -gt 0 ]; then
                echo -e "************** WARNING **************"
                echo "'${nutCfgVolume}/${cfgFile}' mode is too permissive."
                echo -e "\tRecommended permissions: 640"
                echo -e "\tCurrent permissions: $(stat -c '%a' ${nutCfgVolume}/${cfgFile})"
                echo "************************************"
            fi
        }
        if [ "$(stat -c '%u' ${nutCfgVolume}/${cfgFile})" != "$nutUid" ]; then
            echo "ERROR: Config file '${nutCfgVolume}/${cfgFile}' has incorrect owner."
            echo -e "\tCurrent owner: $(stat -c '%U' ${nutCfgVolume}/${cfgFile}) (UID=$(stat -c '%u' ${nutCfgVolume}/${cfgFile}))"
            echo -e "\tRecommended owner: $nutUser (UID=$nutUid)"
            exit 1
        fi
    else
        echo "ERROR: Config file '${nutCfgVolume}/${cfgFile}' does not exist. You should create one, have a look at the README."
        exit 1
    fi
done

# Clear stale PID files
for i in `find /var/run/nut/ -type f -name '*.pid'`; do
    echo "Clearing stale PID from $i"
    pid=`cat $i`
    if [ -d /proc/$pid ]; then
        echo "Found PID $pid still running. Killing it before starting."
        kill $pid
        while ps -p $pid >/dev/null; do echo "Waiting for PID $pid to die"; sleep 1; done
        echo "Killed PID $pid"
    fi
    rm -f $i
done

echo "*** NUT upsd startup ***"

# Initialise UPS driver with the specified user
echo "Starting UPS drivers ..."
/usr/sbin/upsdrvctl -u $nutUser start || {
    echo -e "ERROR on driver startup.\nIf using a USB device, make sure the container's device cgroup rules, the host's udev rules,\nor device file ownership and permissions allow the NUT user/group R/W access to the device."
    exit 1
}

# Run the ups daemon with the specified user
echo "Starting UPS daemon ..."
exec /usr/sbin/upsd -D -u $nutUser $* || {
    echo "ERROR on daemon startup."
    exit 1
}
