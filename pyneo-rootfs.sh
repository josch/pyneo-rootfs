#!/bin/sh

ROOTDIR="pyneo-chroot"
DIST="sid"
EFL=true
PYNEO=true
XFCE=false
XORG=true
ALSA=true

KERNEL_VER="2.6.31"

if [ -d $ROOTDIR ]; then
	echo "$ROOTDIR exists"
	exit 1
fi

for APP in "cdebootstrap" "curl" "chroot"; do
	if [ -z "`which $APP`" ]; then
		echo "you need $APP"
		exit 1
	fi
done

# cdebotstrap
DEPS_SYSTEM="locales,udev,module-init-tools,sysklogd,klogd,psmisc,mtd-utils,ntpdate,debconf-english"
DEPS_CONSOLE="screen,less,vim-tiny,console-tools,conspy,console-setup-mini,man-db,fbset,input-utils"
#DEPS_WLAN="wpasupplicant"
#DEPS_BT="bluez,bluez-utils,bluez-alsa,bluez-gstreamer"
DEPS_NETMGMT="netbase,iputils-ping"
DEPS_NETAPPS="curl,wget,openssh-server,vpnc,rsync"
cdebootstrap --include $DEPS_SYSTEM,$DEPS_CONSOLE,$DEPS_NETMGMT,$DEPS_NETAPPS --flavour=minimal $DIST $ROOTDIR http://ftp.debian.org/debian

if [ $? -ne 0 ]; then
	echo "cdebootstrap failed"
	exit 1
fi

# /etc/syslog.conf
echo "*.* @host" > $ROOTDIR/etc/syslog.conf
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
cat > $ROOTDIR/etc/modules << __END__
s3c2410_ts
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
# locales
#echo LANG="C" > $ROOTDIR/etc/default/locale
echo LANG="en_US.UTF-8" > $ROOTDIR/etc/default/locale
echo en_US.UTF-8 UTF-8 > $ROOTDIR/etc/locale.gen
chroot $ROOTDIR locale-gen
#
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

# add pyneo repository
if $PYNEO; then
	echo deb http://pyneo.org/debian/ / >> $ROOTDIR/etc/apt/sources.list
	curl http://pyneo.org/downloads/debian/pyneo-repository-pubkey.gpg | chroot $ROOTDIR apt-key add -
fi

chroot $ROOTDIR apt-get update -qq

# install enlightenment
if $EFL; then
	chroot $ROOTDIR apt-get install libevas-svn-06-engines-core libevas-svn-06-engines-x python-ecore python-evas python-edje python-elementary python-edbus libedje-bin -qq
fi

# install xorg
if $XORG; then
	chroot $ROOTDIR apt-get install xserver-xorg-video-glamo -qq
	chroot $ROOTDIR apt-get install xorg xserver-xorg-input-evdev nodm matchbox-window-manager -qq
	# /etc/X11/xorg.conf
	cat > $ROOTDIR/etc/X11/xorg.conf << __END__
Section "Device"
       Identifier      "Configured Video Device"
       Driver          "fbdev"
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
	mkdir -p $ROOTDIR/etc/X11/xorg.conf.d
fi

# install pyneo
if $PYNEO; then
	chroot $ROOTDIR apt-get install pyneo-pyneod pyneo-pybankd python-pyneo gsm0710muxd python-ijon pyneo-resolvconf -qq --download-only
	# an existing resolv.conf will prompt the user wether to overwrite it or not so delete it
	rm $ROOTDIR/etc/resolv.conf
	chroot $ROOTDIR apt-get install pyneo-pyneod pyneo-pybankd python-pyneo gsm0710muxd python-ijon pyneo-resolvconf -qq --no-download

	# configure dnsmasq
	cat > $ROOTDIR/etc/dnsmasq.d/pyneo << __END__
no-resolv
no-poll
enable-dbus
log-queries
clear-on-reload
domain-needed
__END__

	cat > $ROOTDIR/etc/dhcpcd.conf << __END__
hostname

option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes

option ntp_servers

option interface_mtu

require dhcp_server_identifier

nohook lookup-hostname

interface usb0
	static ip_address=192.168.0.202/24
	static routers=192.168.0.200
	static domain_name_servers=192.168.0.200
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
	chroot $ROOTDIR apt-get install alsa-base alsa-utils gstreamer0.10-alsa gstreamer0.10-plugins-good gstreamer0.10-plugins-bad gstreamer0.10-plugins-ugly gstreamer-tools -qq
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
echo KERNEL==\"s3c2410_serial[0-9]\",  SYMLINK=\"ttySAC%n\" > $ROOTDIR/etc/udev/rules.d/51-calypso.rules
# kernel
curl http://pyneo.org/downloads/gta0x/zImage-$KERNEL_VER-pyneo.bin > $ROOTDIR/boot/zImage-$KERNEL_VER-pyneo.bin
ln -s zImage-$KERNEL_VER-pyneo.bin $ROOTDIR/boot/uImage-GTA01.bin
ln -s zImage-$KERNEL_VER-pyneo.bin $ROOTDIR/boot/uImage-GTA02.bin
echo "console=tty0 rootdelay=3 " > $ROOTDIR/boot/append-GTA01
echo "console=tty0 rootdelay=3 " > $ROOTDIR/boot/append-GTA02
# modules
curl http://pyneo.org/downloads/gta0x/modules-$KERNEL_VER-pyneo.tar.lzma | tar --lzma -xf - -C $ROOTDIR

if $PYNEO; then
	# /etc/resolv.conf
	echo "nameserver localhost" > $ROOTDIR/etc/resolv.conf
fi

# firstboot script
cat > $ROOTDIR/etc/init.d/firstboot << __END__
#!/bin/sh -e
### BEGIN INIT INFO
# Provides:          firstboot
# Required-Start:    \$all
# Required-Stop:     
# Default-Start:     S
# Default-Stop:
# X-Interactive:     true

### END INIT INFO

update-rc.d -f firstboot remove

[ -d /home/persistent ] || mkdir /home/persistent

print_exit_status () {
	cols=\`tput cols\`
	lines=\`tput lines\`
	cols=\`expr \$cols - 8\`
	if [ \$1 -ne 0 ]; then
		tput cup \$lines \$cols
		echo "\\033[1;31m[failed]\\033[0m"
	else
		tput cup \$lines \$cols
		echo "\\033[1;32m[ done ]\\033[0m"
	fi
}

print_yellow () {
	echo "\\033[1;33m\$1\\033[0m"
}

print_yellow "a/ aaQQaa/  a/      _a _a aajQaa     _aaQQaa       /_aQaaa  "
print_yellow "Q6P?    ?Q6 )W/    _Qf ]QQ?   )46   jP?    ?Qa    ' ]f   )?/"
print_yellow "QP        Q6 )W/   QP  ]Q'     )W/ jQaaaaaaajQf _'  ]6]Q'  )"
print_yellow "Qf        jQ  4Q/ jP   ]Q       Qf QQ?????????' ]  aQQQ6aaa "
print_yellow "QQ/      _Q'   46jP    ]Q       Qf )W/      _a  Q4?QQ?    ]P"
print_yellow "QP?6aaaaWP'     4Q'    ]Q       Qf  )46aaaajP'    ?j6/ _aj? "
print_yellow "Qf   ??'       _Q'                     )??'        )'???    "
print_yellow "Qf            _Q'                                           "

echo
print_yellow "Running automatic first boot tasks..."

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
	echo -n "Generating ssh rsa host key pairs..."
	/usr/bin/ssh-keygen -q -t rsa -f /home/persistent/ssh_host_rsa_key -C '' -N ''
	print_exit_status \$?
	echo -n "Generating ssh dsa host key pairs..."
	/usr/bin/ssh-keygen -q -t dsa -f /home/persistent/ssh_host_dsa_key -C '' -N ''
	print_exit_status \$?
fi
echo -n "Copying ssh host keys into place..."
cp /home/persistent/ssh_host_rsa_key /home/persistent/ssh_host_rsa_key.pub /home/persistent/ssh_host_dsa_key /home/persistent/ssh_host_dsa_key.pub /etc/ssh/
print_exit_status \$?

if [ -f /home/persistent/pyneo.ini ]; then
	echo -n "Copying pyneo.ini into place..."
	cp /home/persistent/pyneo.ini /etc/
	print_exit_status \$?
fi

DEVICE="\`awk '/^Hardware/ {print \$3}' < /proc/cpuinfo | tr \"[:upper:]\" \"[:lower:]\"\`"
print_yellow "Running on \$DEVICE."

echo -n "Calibrating Touchscreen."
if [ \$DEVICE = "gta01" ]; then
	cat > /etc/X11/xorg.conf.d/s3c2410.conf << __XORG__
Section "InputClass"
	Identifier	"s3c2410 TouchScreen"
	MatchProduct	"s3c2410 TouchScreen"
	Option	"Calibration"	"69, 922, 950, 65"
	Option	"SwapAxes"	"1"
EndSection
__XORG__
	print_exit_status \$?

	echo -n "Appending MAC address to kernel boot parameters."
	if [ ! -f /home/persistent/mac ]; then
		echo \`ifconfig -a | awk '/^usb0/{print \$5}'\` > /home/persistent/mac
	fi
	echo "console=tty0 g_ether.host_addr=\`head -n 1 /home/persistent/mac\`" > /boot/append-GTA01
	print_exit_status \$?

	echo -n "Appending sound module."
	echo "snd-soc-neo1973-wm8753" >> /etc/modules
	print_exit_status \$?

	echo -n "Configuring host alias."
	cat >> /etc/hosts << __HOSTS__
127.0.0.1 gta01
192.168.0.199 host01 host
192.168.0.200 host02
192.168.0.201 gta01 neo
192.168.0.202 gta02
__HOSTS__
	print_exit_status \$?

	echo -n "Adjusting /etc/fstab."
	echo "/dev/mtdblock4  /media/nand     jffs2   defaults,noatime                   0      0" >> /etc/fstab
	print_exit_status \$?
else
	cat > /etc/X11/xorg.conf.d/s3c2410.conf << __XORG__
Section "InputClass"
	Identifier	"s3c2410 TouchScreen"
	MatchProduct	"s3c2410 TouchScreen"
	Option	"Calibration"	"110 922 924 96"
	Option	"SwapAxes"	"1"
EndSection
__XORG__
	print_exit_status \$?

	echo -n "Configuring glamo into xorg.conf."
	sed -i 's/\(Driver          \)"fbdev"/\1"glamo"/' /etc/X11/xorg.conf
	print_exit_status \$?

	echo -n "Appending sound module."
	echo "snd-soc-neo1973-gta02-wm8753" >> /etc/modules
	print_exit_status \$?

	echo -n "Configuring host alias."
	cat >> /etc/hosts << __HOSTS__
127.0.0.1 gta02
192.168.0.199 host01
192.168.0.200 host02 host
192.168.0.201 gta01
192.168.0.202 gta02 neo
__HOSTS__
	print_exit_status \$?

	echo -n "Adjusting /etc/fstab."
	echo "/dev/mtdblock6  /media/nand     jffs2   defaults,noatime                   0      0" >> /etc/fstab
	print_exit_status \$?
fi

echo -n "Creating new user"
if [ -d /home/user ]; then
	useradd user -p //plGAV7Hp3Zo -s /bin/bash
else
	useradd user -p //plGAV7Hp3Zo -s /bin/bash --create-home
fi
print_exit_status \$?

echo -n "Mounting NAND."
mount /media/nand
print_exit_status \$?

echo -n "Setting hostname to \$DEVICE."
echo "\$DEVICE" > /etc/hostname
hostname "\$DEVICE"
print_exit_status \$?

print_yellow "finished running firstboot tasks!"
print_yellow "resuming normal boot..."
sleep 3
__END__
chmod +x $ROOTDIR/etc/init.d/firstboot
chroot $ROOTDIR update-rc.d firstboot start 99 S

# cleanup
chroot $ROOTDIR apt-get remove cdebootstrap-helper-rc.d xserver-xorg-input-synaptics xserver-xorg-input-wacom -qq
chroot $ROOTDIR apt-get clean -qq
rm -f $ROOTDIR/etc/ssh/ssh_host_*
rm -f $ROOTDIR/var/lib/apt/lists/*
rm -f $ROOTDIR/var/cache/apt/*
rm -f $ROOTDIR/var/log/*
rm -f $ROOTDIR/var/log/*/*

# tar cv -C pyneo-chroot/ . | ssh josch@192.168.0.199 "lzma -c > pyneo-rootfs-debian-sid-`date +%F`.tar.lzma"

