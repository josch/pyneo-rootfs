#!/bin/sh

ROOTDIR="pyneo-chroot"
DIST="sid"
EFL=false
PYNEO=true
XFCE=false
XORG=true
ALSA=true

GTA01KERNEL="2.6.29-rc3"
GTA02KERNEL="2.6.30.4"

if [ -d $ROOTDIR ]; then
	echo "$ROOTDIR exists"
	exit 1
fi

for APP in "cdebootstrap" "curl"; do
	if [ -z "`which $APP`" ]; then
		echo "you need $APP"
		exit 1
	fi
done

for PROC in "hald" "dbus-daemon" "gsm0710muxd" "pyneod"; do
	if [ -n "`pidof $PROC`" ]; then
		echo "stop $PROC before running this script"
		exit 1
	fi
done

# cdebotstrap
DEPS_SYSTEM="udev,module-init-tools,sysklogd,klogd,psmisc,mtd-utils,ntpdate,debconf-english"
DEPS_CONSOLE="screen,less,vim-tiny,console-tools,conspy,console-setup-mini"
DEPS_WLAN="wireless-tools,wpasupplicant"
DEPS_BT="bluez,bluez-utils,bluez-alsa,bluez-gstreamer"
DEPS_NETMGMT="ifupdown,netbase,iputils-ping,dhcp3-client"
DEPS_NETAPPS="curl,wget,openssh-server,vpnc,rsync"
cdebootstrap --include $DEPS_SYSTEM,$DEPS_CONSOLE,$DEPS_WLAN,$DEPS_BT,$DEPS_NETMGMT,$DEPS_NETAPPS --flavour=minimal $DIST $ROOTDIR http://ftp.debian.org/debian

if [ $? -ne 0 ]; then
	echo "cdebootstrap failed"
	exit 1
fi

# mount
mount -t none -o bind /dev $ROOTDIR/dev
mount -t none -o bind /proc $ROOTDIR/proc
mount -t none -o bind /sys $ROOTDIR/sys
mount -t none -o bind /tmp $ROOTDIR/tmp
# /etc/hosts
echo "127.0.0.1 localhost" > $ROOTDIR/etc/hosts
# /etc/resolv.conf
# while building use host's resolv.conf
cp /etc/resolv.conf $ROOTDIR/etc/resolv.conf
# /etc/network/interfaces
cat > $ROOTDIR/etc/network/interfaces << __END__
auto lo
iface lo inet loopback
auto usb0
iface usb0 inet static
    address neo
    netmask 255.255.255.0
    network 192.168.0.0
    gateway host
    dns-nameservers host
__END__
# /etc/fstab
cat > $ROOTDIR/etc/fstab << __END__
# <file system> <mount point>   <type>  <options>                          <dump> <pass>
rootfs          /               auto    defaults,errors=remount-ro,noatime 0      1
/dev/mmcblk0p2  /home           auto    defaults,errors=remount-ro,noatime 0      2
proc            /proc           proc    defaults                           0      0
tmpfs           /tmp            tmpfs   defaults,noatime                   0      0
tmpfs           /var/lock       tmpfs   defaults,noatime                   0      0
tmpfs           /var/run        tmpfs   defaults,noatime                   0      0
__END__
# nand mount
mkdir -p $ROOTDIR/media/nand
# no-install-recommends
echo 'APT::Install-Recommends "0";' > $ROOTDIR/etc/apt/apt.conf.d/99no-install-recommends
# no pdiffs
# rather download more than suffer from slow cpu
echo 'Acquire::PDiffs "0";' > $ROOTDIR/etc/apt/apt.conf.d/99no-pdiffs
# empty password
sed -i 's/\(PermitEmptyPasswords\) no/\1 yes/' $ROOTDIR/etc/ssh/sshd_config
sed -i 's/\(root:\)[^:]*\(:\)/\1\/\/plGAV7Hp3Zo\2/' $ROOTDIR/etc/shadow
#
echo LANG=C > $ROOTDIR/etc/default/locale
echo set debconf/frontend Teletype | chroot $ROOTDIR debconf-communicate
# disable startup message of screen
echo startup_message off >> $ROOTDIR/etc/screenrc
# let vim be vim
echo "set nocp" >> $ROOTDIR/etc/vim/vimrc
# disable console blanking
sed -i 's/\(BLANK_TIME\)=30/\1=0/' $ROOTDIR/etc/console-tools/config
# disable getty for 2-6
sed -i "s/\([2-6]:23:respawn:\/sbin\/getty 38400 tty[2-6]\)/#\1/" $ROOTDIR/etc/inittab
# enable fs fixes
sed -i "s/\(FSCKFIX=\)no/\1yes/" $ROOTDIR/etc/default/rcS

# add enlightenment repository
if $EFL; then
	echo deb http://packages.enlightenment.org/debian lenny main extras >> $ROOTDIR/etc/apt/sources.list
	cat > $ROOTDIR/etc/apt/preferences << __END__
Package: *
Pin: origin packages.enlightenment.org 
Pin-Priority: 1001
__END__
	curl http://packages.enlightenment.org/repo.key | chroot $ROOTDIR apt-key add -
fi

# add pyneo repository
if $PYNEO; then
	echo deb http://pyneo.org/debian/ / >> $ROOTDIR/etc/apt/sources.list
fi

chroot $ROOTDIR apt-get update -qq

# install enlightenment
if $EFL; then
	chroot $ROOTDIR apt-get install python-evas python-edje python-elementary python-emotion python-edbus libedje-bin -qq
fi

# install xorg
if $XORG; then
	chroot $ROOTDIR apt-get install xorg xserver-xorg-input-tslib xserver-xorg-video-glamo nodm matchbox-window-manager -qq
	# /etc/X11/xorg.conf
	cat > $ROOTDIR/etc/X11/xorg.conf << __END__
Section "Device"
       Identifier      "Configured Video Device"
       Driver          "fbdev"
EndSection
Section "InputDevice"
        Identifier      "Configured Touchscreen"
        Driver          "tslib"
        Option          "CorePointer"           "true"
        Option          "SendCoreEvents"        "true"
        Option          "Device"                "/dev/input/event1"
        Option          "Protocol"              "Auto"
EndSection
__END__
	cat > $ROOTDIR/etc/skel/.xsession << __END__
#!/bin/sh
exec matchbox-window-manager -use_titlebar no -use_cursor no
__END__
	chmod +x $ROOTDIR/etc/skel/.xsession
	# configure nodm
	cat > $ROOTDIR/etc/default/nodm << __END__
NODM_ENABLED=true
NODM_USER=user
NODM_XINIT=/usr/bin/xinit
NODM_FIRST_VT=0
NODM_XSESSION=/etc/X11/Xsession
NODM_X_OPTIONS='-nolisten tcp'
NODM_MIN_SESSION_TIME=60
__END__
	echo allowed_users=anybody > $ROOTDIR/etc/X11/Xwrapper.config
fi

# install pyneo
if $PYNEO; then
	rm $ROOTDIR/etc/resolv.conf
	chroot $ROOTDIR apt-get install pyneod python-pyneo gsm0710muxd python-ijon pyneo-resolvconf dnsmasq netplug -qq --force-yes

	# let netplugd manage usb0
	echo usb0 >> $ROOTDIR/etc/netplug/netplugd.conf
	# configure dnsmasq
	cat > $ROOTDIR/etc/dnsmasq.d/pyneo << __END__
no-resolv
no-poll
enable-dbus
log-queries
clear-on-reload
domain-needed
__END__
	# pyneo-resolvconf installs new resolv.conf - revert that change
	cp /etc/resolv.conf $ROOTDIR/etc/resolv.conf
fi

# install xfce
if $XFCE; then
	chroot $ROOTDIR apt-get install gdm xfce4 xvkbd -qq
	sed -i "s/\(exit 0\)/sleep 20 \&\& \/usr\/bin\/xvkbd -xdm -compact -geometry 480x210+0+0 \&\n\1/" $ROOTDIR/etc/gdm/Init/Default
	curl http://rabenfrost.net/debian/debian-blueish-wallpaper-480x640.png > $ROOTDIR/usr/share/images/desktop-base/desktop-background
fi

# install audio
if $ALSA; then
	chroot $ROOTDIR apt-get install alsa-base alsa-utils gstreamer0.10-alsa gstreamer0.10-plugins-good gstreamer0.10-plugins-bad gstreamer0.10-plugins-ugly -qq
	# /etc/asound.conf
	cat > $ROOTDIR/etc/asound.conf << __END__
pcm.!default {
    type plug
    slave.pcm "dmixer"
}
pcm.dmixer  {
    type dmix
    ipc_key 1024
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
        rate 44100
    }
    bindings {
        0 0
        1 1
    }
}
ctl.dmixer {
    type hw
    card 0
}
__END__
fi

# modem
echo KERNEL==\"s3c2410_serial[0-9]\",  NAME=\"ttySAC%n\" > $ROOTDIR/etc/udev/rules.d/51-calypso.rules
# kernel
curl http://pyneo.org/downloads/gta01/zImage-$GTA01KERNEL-pyneo-gta01.bin > $ROOTDIR/boot/zImage-$GTA01KERNEL-pyneo-gta01.bin
curl http://pyneo.org/downloads/gta02/zImage-$GTA02KERNEL-pyneo-gta02.bin > $ROOTDIR/boot/zImage-$GTA02KERNEL-pyneo-gta02.bin
ln -s zImage-$GTA01KERNEL-pyneo-gta01.bin $ROOTDIR/boot/uImage-GTA01.bin
ln -s zImage-$GTA02KERNEL-pyneo-gta02.bin $ROOTDIR/boot/uImage-GTA02.bin
echo -n "console=tty0 loglevel=8" > $ROOTDIR/boot/append-GTA01
echo -n "console=tty0 loglevel=8" > $ROOTDIR/boot/append-GTA02
# modules
curl http://pyneo.org/downloads/gta01/modules-$GTA01KERNEL-pyneo-gta01.tar.gz | tar xzf - -C $ROOTDIR
curl http://pyneo.org/downloads/gta02/modules-$GTA02KERNEL-pyneo-gta02.tar.gz | tar xzf - -C $ROOTDIR

if $PYNEO; then
	# /etc/resolv.conf
	echo "nameserver localhost" > $ROOTDIR/etc/resolv.conf
fi

# firstboot script
cat > $ROOTDIR/usr/sbin/firstboot.sh << __END__
#!/bin/sh
rm -f /etc/rcS.d/S99firstboot
[ -d /home/persistent ] || mkdir /home/persistent

echo "Running automatic first boot tasks."

# generat new ssh host keys if one of the files is not in place
if [ ! -f /home/persistent/ssh_host_rsa_key ] ||
   [ ! -f /home/persistent/ssh_host_rsa_key.pub ] ||
   [ ! -f /home/persistent/ssh_host_dsa_key ] ||
   [ ! -f /home/persistent/ssh_host_dsa_key.pub ]; then
	# make sure none of the files still exists
	[ ! -f /home/persistent/ssh_host_rsa_key ] || rm /home/persistent/ssh_host_rsa_key
	[ ! -f /home/persistent/ssh_host_rsa_key.pub ] || rm /home/persistent/ssh_host_rsa_key
	[ ! -f /home/persistent/ssh_host_dsa_key ] || rm /home/persistent/ssh_host_dsa_key
	[ ! -f /home/persistent/ssh_host_dsa_key.pub ] || rm /home/persistent/ssh_host_dsa_key.pub
	echo -n "Generating ssh host key pairs:"
	echo -n " rsa..."; /usr/bin/ssh-keygen -q -t rsa -f /home/persistent/ssh_host_rsa_key -C '' -N ''
	echo -n " dsa..."; /usr/bin/ssh-keygen -q -t dsa -f /home/persistent/ssh_host_dsa_key -C '' -N ''
	echo "done."
fi
echo "Copying ssh host keys into place."
cp /home/persistent/ssh_host_rsa_key /home/persistent/ssh_host_rsa_key.pub /home/persistent/ssh_host_dsa_key /home/persistent/ssh_host_dsa_key.pub /etc/ssh/

DEVICE="\`awk '/^Hardware/ {print \$3}' < /proc/cpuinfo | tr \"[:upper:]\" \"[:lower:]\"\`"
echo "Running on \$DEVICE."

echo "Calibrating Touchscreen."
if [ \$DEVICE = "gta01" ]; then
	echo -67 36365 -2733100 -48253 -310 45219816 65536 > /etc/pointercal
	echo "Appending MAC address to kernel boot parameters."
	if [ ! -f /home/persistent/mac ]; then
		echo \`ifconfig -a | awk '/^usb0/{print \$5}'\` > /home/persistent/mac
	fi
	echo -n " g_ether.host_addr=\`head -n 1 /home/persistent/mac\`" >> /boot/append-GTA01
	echo "Appending sound module."
	echo "snd-soc-neo1973-wm8753" > /etc/modules
	echo "Configuring host alias."
	cat >> /etc/hosts << __HOSTS__
127.0.0.1 gta01
192.168.0.199 host01 host
192.168.0.200 host02
192.168.0.201 gta01 neo
192.168.0.202 gta02
__HOSTS__
	echo "Adjusting /etc/fstab."
	echo "/dev/mtdblock4  /media/nand     jffs2   defaults,noatime                   0      0" >> /etc/fstab
else
	echo -67 38667 -4954632 -51172 121 46965312 65536 > /etc/pointercal
	echo "Configuring glamo into xorg.conf."
	sed -i 's/\(Driver          \)"fbdev"/\1"glamo"/' /etc/X11/xorg.conf
	echo "Appending sound module."	
	echo "snd-soc-neo1973-gta02-wm8753" > /etc/modules
	echo "Configuring host alias."
	cat >> /etc/hosts << __HOSTS__
127.0.0.1 gta02
192.168.0.199 host01
192.168.0.200 host02 host
192.168.0.201 gta01
192.168.0.202 gta02 neo
__HOSTS__
	echo "Adjusting /etc/fstab."
	echo "/dev/mtdblock6  /media/nand     jffs2   defaults,noatime                   0      0" >> /etc/fstab
fi

echo "Creating new user"
useradd user -p //plGAV7Hp3Zo -s /bin/bash --create-home

echo "Mounting NAND."
mount /media/nand

echo "Setting hostname to \$DEVICE."
echo "\$DEVICE" > /etc/hostname
hostname "\$DEVICE"

echo "Bringing up usb networking."
ifup usb0

echo "Updating datetime."
ntpdate-debian

echo -n "Updating package index..."
apt-get update -qq
echo "done."
__END__
chmod +x $ROOTDIR/usr/sbin/firstboot.sh
ln -sf /usr/sbin/firstboot.sh $ROOTDIR/etc/rcS.d/S99firstboot

# cleanup
rm -f $ROOTDIR/etc/ssh/ssh_host_*
rm -f $ROOTDIR/var/lib/apt/lists/*
rm -f $ROOTDIR/var/cache/apt/*
rm -f $ROOTDIR/var/log/*
rm -f $ROOTDIR/var/log/*/*
chroot $ROOTDIR apt-get clean -qq
# stop services
if $PYNEO; then
	chroot $ROOTDIR /etc/init.d/pyneod stop
	chroot $ROOTDIR /etc/init.d/gsm0710muxd stop
fi
if $PYNEO || $XORG || $XFCE || $EFL; then
	chroot $ROOTDIR /etc/init.d/hal stop
	chroot $ROOTDIR /etc/init.d/dbus stop
fi
# umount
umount $ROOTDIR/dev
umount $ROOTDIR/proc
umount $ROOTDIR/sys
umount $ROOTDIR/tmp

# tar cv -C sid-chroot/ . | ssh josch@192.168.0.199 "lzma -c > pyneo-rootfs-debian-sid.tar.lzma"

