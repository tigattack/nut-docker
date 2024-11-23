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

nutCfgVolume="/etc/nut"
nutCfgFiles="ups.conf upsd.conf upsd.users"

echo "*** NUT upsd startup ***"

# bail out if the config volume is not mounted
grep ${nutCfgVolume} /proc/mounts >/dev/null ||
	{ printf "ERROR: It does not look like the config volume is mounted to %s. Have a look at the README for instructions.\n" ${nutCfgVolume}; exit; }

# more sanity: make sure our config files stick around
for cfgFile in ${nutCfgFiles}; do
	if [ -f ${nutCfgVolume}/${cfgFile} ]; then
		# bail out if users file is too permissive
		if [ "`stat -c '%a' ${nutCfgVolume}/${cfgFile}`" != "440" -o "`stat -c '%u' ${nutCfgVolume}/${cfgFile}`" != "`id -u nut`" ]; then
			printf "ERROR: '%s/%s' mode is too permissive.\n" ${nutCfgVolume} ${cfgFile}
			printf "\trecommended permissions: 0440\n"
			printf "\trecommended owner:"
			id nut
			printf "\n\ncurrent permissions:\n"
			stat ${nutCfgVolume}/upsd.users
			exit
		fi

		continue
	fi

	printf "ERROR: config file '%s/%s' does not exist. You should create one, have a look at the README.\n" ${nutCfgVolume} ${cfgFile}
	exit
done

# Clear stale PID files
for i in `find /var/run/nut/ -type f -name '*.pid'`; do
	echo "Clearing stale PID from $i"
	pid=`cat $i`
	if [ -d /proc/$pid ]; then
		echo "Found PID $pid still running. Killing it before starting."
		kill $pid
		while ps -p $pid; do echo "Waiting for PID $pid to die"; sleep 1; done
		echo "Killed PID $pid"
	fi
	rm -f $i
done

# Initialise UPS driver
printf "Starting UPS drivers ...\n"
/usr/sbin/upsdrvctl start || { printf "ERROR on driver startup.\n"; exit; }

# Run the ups daemon
printf "Starting UPS daemon ...\n"
exec /usr/sbin/upsd -D $* || { printf "ERROR on daemon startup.\n"; exit; }
