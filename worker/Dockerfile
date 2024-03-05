FROM opensuse/tumbleweed
LABEL title="opensuse_worker"

# RUN dnf install -y openqa openqa-worker python3-jsonschema \
#     perl-REST-Client procps-ng os-autoinst tunctl iproute

RUN zypper in -yl openQA-worker os-autoinst-s390-deps os-autoinst-ipmi-deps && \
    zypper in -yl qemu-arm qemu-ppc qemu-x86 qemu-tools && \
    zypper in -yl qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-pci qemu-hw-display-virtio-vga && \
    zypper in -yl kmod && \
    zypper in -yl qemu-ovmf-x86_64 && \
    zypper in -yl qemu-uefi-aarch64  && \
    zypper in -yl vde2 vde2-slirp && \
    zypper in -yl python3 python3-jsonschema gcc make curl perl-App-cpanminus e2fsprogs ovmf \
        perl-SemVer perl-DateTime perl-NetAddr-IP perl-Test-Assert perl-JSON && \
    zypper clean && \
    mkdir -p /root/qemu

RUN cpanm REST::Client

# fix all ownership/permissions
RUN chown -R _openqa-worker /usr/share/openqa /var/lib/openqa && \
	chmod ug+rw /usr/share/openqa /var/lib/openqa && \
	find /usr/share/openqa /var/lib/openqa -type d -exec chmod ug+x {} \;

EXPOSE 80 443

ENTRYPOINT ["/init_openqa_worker.sh"]
