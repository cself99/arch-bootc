FROM docker.io/archlinux/archlinux:latest

# Move everything from `/var` to `/usr/lib/sysimage` so behavior around pacman remains the same on `bootc usroverlay`'d systems
RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf

RUN pacman -Syu --noconfirm

RUN pacman -Sy --noconfirm base dracut linux linux-firmware ostree btrfs-progs e2fsprogs xfsprogs dosfstools skopeo dbus sudo dbus-glib glib2 ostree shadow && pacman -S --clean --noconfirm


RUN pacman -Sy --noconfirm --needed git base-devel wget whois && \
    # aur is very questionable
    wget https://builds.garudalinux.org/repos/chaotic-aur/x86_64/aura-4.2.0-1-x86_64.pkg.tar.zst && pacman -U --noconfirm aura-4.2.0-1-x86_64.pkg.tar.zst && \
    aura --noconfirm -A sway-scroll-git dms-shell-bin gpu-screen-recorder-ui zen-browser-bin && \
    pacman -Sy --noconfirm gdm xdg-desktop-portal-wlr ghostty restic grim slurp mpv flatpak helix dhcpcd pipewire pipewire-alsa pipewire-pulse mesa vulkan-radeon networkmanager bluez bluez-utils distrobox  && \
    #flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak -y install com.discordapp.Discord && \
    systemctl enable gdm && pacman-key --init && \
    curl -s https://repo.cider.sh/ARCH-GPG-KEY | pacman-key --add - && pacman-key --lsign-key A0CD6B993438E22634450CDD2A236C3F42A61682 && \
    tee -a /etc/pacman.conf << 'EOF'

# Cider Collective Repository
[cidercollective]
SigLevel = Required TrustedOnly
Server = https://repo.cider.sh/arch
EOF

RUN pacman -Sy --noconfirm && pacman -S --noconfirm cider
 

# https://github.com/bootc-dev/bootc/issues/1801
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    pacman -S --noconfirm make git rust go-md2man && \
    git clone "https://github.com/bootc-dev/bootc.git" /tmp/bootc && \
    make -C /tmp/bootc bin install-all && \
    printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" | tee /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf && \
    printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" ostree bootc "' | tee "/usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf" && \
    dracut --force "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)/initramfs.img" && \
    pacman -S --clean --noconfirm

RUN mkdir /tmp/opt && cp -R /opt/ /tmp/opt/

# Necessary for general behavior expected by image-based systems
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    rm -rf /boot /home /root /usr/local /srv /opt /mnt /var /usr/lib/sysimage/log /usr/lib/sysimage/cache/pacman/pkg && \
    mkdir -p /sysroot /boot /usr/lib/ostree /var && \
    ln -sT sysroot/ostree /ostree && ln -sT var/roothome /root && ln -sT var/srv /srv && ln -sT var/opt /opt && ln -sT var/mnt /mnt && ln -sT var/home /home && ln -sT ../var/usrlocal /usr/local && \
    echo "$(for dir in opt home srv mnt usrlocal ; do echo "d /var/$dir 0755 root root -" ; done)" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf "d /var/roothome 0700 root root -\nd /run/media 0755 root root -" | tee -a "/usr/lib/tmpfiles.d/bootc-base-dirs.conf" && \
    printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' | tee "/usr/lib/ostree/prepare-root.conf"

RUN cp -R /tmp/opt/opt/ /var/opt/ && rm -rf /tmp/opt
   
RUN usermod -p "$(echo "changeme" | mkpasswd -s)" root && echo 'ALL ALL=(ALL:ALL) ALL' >> /etc/sudoers && \
    rm /etc/scroll/config && wget -O /etc/scroll/config https://raw.githubusercontent.com/cself99/arch-bootc/refs/heads/main/scroll-config && \
    systemctl enable dhcpcd && systemctl enable systemd-homed

# https://bootc-dev.github.io/bootc/bootc-images.html#standard-metadata-for-bootc-compatible-images
LABEL containers.bootc 1

RUN bootc container lint
