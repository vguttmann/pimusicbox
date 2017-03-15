PIMUSICBOX_FILES=/tmp/filechanges
PIMUSICBOX_VERSION=0.7
SHAIRPORT_VERSION=3.0
#APT_PROXY=localhost:3142

echo "Acquire::http { Proxy \"http://$APT_PROXY\"; };" > \
    /etc/apt/apt.conf.d/01proxy

cd /tmp

# Update system time to avoid SSL errors later.
ntpdate-debian
service fake-hwclock stop

# dpkg: warning: unable to delete old directory '/lib/modules/3.18.7+/kernel/drivers/net/wireless': Directory not empty
rm /lib/modules/3.18.7+/kernel/drivers/net/wireless/8188eu.ko
# Prevent upgraded services from trying to start inside chroot.
echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
export DEBIAN_FRONTEND=noninteractive
# Remove Mopidy APT repo details, using pip version to avoid Wheezy induced dependency hell.
rm /etc/apt/sources.list.d/mopidy.list

wget -q -O - http://www.lesbonscomptes.com/key/jf@dockes.org.gpg.key | apt-key add -
cat << EOF > /etc/apt/sources.list.d/upmpdcli.list
deb http://www.lesbonscomptes.com/upmpdcli/downloads/raspbian-wheezy/ unstable main
deb-src http://www.lesbonscomptes.com/upmpdcli/downloads/raspbian-wheezy/ unstable main
EOF

apt-get update
apt-get remove --yes --purge python-pykka python-pylast

# Upgrade!
apt-get dist-upgrade --yes -o Dpkg::Options::="--force-confnew"

# https://github.com/pimusicbox/pimusicbox/issues/316
apt-get remove --yes --purge linux-wlan-ng
# https://github.com/pimusicbox/pimusicbox/issues/371
pip uninstall --yes mopidy-local-whoosh

# Build and install latest version of shairport-sync
SHAIRPORT_BUILD_DEPS="build-essential xmltoman autoconf automake libtool libdaemon-dev libasound2-dev libpopt-dev libconfig-dev avahi-daemon libavahi-client-dev libssl-dev"
SHAIRPORT_RUN_DEPS="libc6 libconfig9 libdaemon0 libasound2 libpopt0 libavahi-common3 avahi-daemon libavahi-client3 libssl1.0.0"
apt-get install --yes $SHAIRPORT_BUILD_DEPS $SHAIRPORT_RUN_DEPS
wget https://github.com/mikebrady/shairport-sync/archive/${SHAIRPORT_VERSION}.zip
unzip ${SHAIRPORT_VERSION}.zip && rm ${SHAIRPORT_VERSION}.zip
cd shairport-sync-${SHAIRPORT_VERSION}
autoreconf -i -f
./configure --sysconfdir=/etc --with-alsa --with-avahi --with-ssl=openssl --with-metadata --with-systemv
make && make install
cd ../
rm -rf shairport-sync*

# Need these to rebuild python dependencies
PYTHON_BUILD_DEPS="build-essential python-dev libffi-dev libssl-dev"
apt-get install --yes $PYTHON_BUILD_DEPS

rm -rf /tmp/pip_build_root
python -m pip install -U pip
# Upgrade some dependencies.
pip install requests[security] backports.ssl-match-hostname backports-abc tornado gmusicapi pykka pylast pafy youtube-dl --upgrade
# The lastest versions that are still supported in Wheezy (Gstreamer 0.10).
pip install mopidy==1.1.2
pip install mopidy-musicbox-webclient==2.4.0
pip install mopidy-websettings==0.1.5
pip install mopidy-mopify==1.6.0
pip install mopidy-mobile==1.8.0
pip install mopidy-youtube==2.0.2
pip install mopidy-gmusic==2.0.0
pip install mopidy-spotify-web==0.3.0
pip install mopidy-spotify==1.4.0
pip install mopidy-tunein==0.4.1
pip install mopidy-local-sqlite==1.0.0
pip install mopidy-scrobbler==1.1.1
pip install mopidy-soundcloud==1.2.5
pip install mopidy-dirble==1.3.0

# Check everything except python and gstreamer is coming from pip.
mopidy --version
mopidy deps | grep "/usr/lib" | grep -v -e "GStreamer: 0.10" -e "Python: CPython" | wc -l

# A bunch of reckless hacks:
# Force Spotify playlists to appear:
sed -i '182s/^/#/' /usr/local/lib/python2.7/dist-packages/mopidy_spotify/session_manager.py
# This should fix MPDroid trying to use MPD commands unsupported by Mopidy. But MPDroid still isn't working properly.
#sed -i 's/0.19.0/0.18.0/' /usr/local/lib/python2.7/dist-packages/mopidy/mpd/protocol/__init__.py
# Speedup MPD connections.
sed -i '/try:/i \
        # Horrible hack here:\
        core.library\
        core.history\
        core.mixer\
        core.playback\
        core.playlists\
        core.tracklist' /usr/local/lib/python2.7/dist-packages/mopidy/mpd/actor.py
# Force YouTube to favour m4a streams as gstreamer0.10's webm support is bad/non-existent:
sed -i '/getbestaudio(/getbestaudio(preftype="m4a"/' /usr/local/lib/python2.7/dist-packages/mopidy_youtube/backend.py

# Copy updated files.
if [ ! -d $PIMUSICBOX_FILES ]; then
    wget https://github.com/pimusicbox/pimusicbox/archive/${PIMUSICBOX_VERSION}.zip
    unzip ${PIMUSICBOX_VERSION}.zip && rm ${PIMUSICBOX_VERSION}.zip 
    PIMUSICBOX_FILES=pimusicbox-${PIMUSICBOX_VERSION}/filechanges
fi
cp -R $PIMUSICBOX_FILES/* /

chown -R mopidy:audio /music/playlists/

MUSICBOX_SERVICES="ssh dropbear upmpdcli shairport-sync"
for service in $MUSICBOX_SERVICES
do
    update-rc.d $service disable
done

# Clean up.
apt-get remove --yes --purge $PYTHON_BUILD_DEPS $SHAIRPORT_BUILD_DEPS
apt-get autoremove --yes
apt-get clean
apt-get autoclean

rm -rf /etc/apt/apt.conf.d/01proxy /usr/sbin/policy-rc.d
