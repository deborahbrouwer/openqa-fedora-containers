#!/bin/bash
# Note: this is a modification of upstream openqa/container/worker/run_openqa_worker.sh
set -ex

function cleanup() {
  echo "Return ownership of bound directories back to container host."
  chown -R root:root /var/lib/openqa/ /usr/share/openqa/
  exit
}
trap cleanup SIGTERM SIGINT

# update the openqa package
dnf -y upgrade --enablerepo=updates-testing --refresh --advisory=FEDORA-2024-b44061e715

if [[ -z $OPENQA_WORKER_INSTANCE ]]; then
  OPENQA_WORKER_INSTANCE=1
fi

mkdir -p "/var/lib/openqa/pool/${OPENQA_WORKER_INSTANCE}/"
chown -R _openqa-worker /var/lib/openqa/pool/

if [[ -z $qemu_no_kvm ]] || [[ $qemu_no_kvm -eq 0 ]]; then
  if [ -c "/dev/kvm" ] && getent group kvm > /dev/null && lsmod | grep '\<kvm\>' > /dev/null; then
    # Simplified kvm-mknod.sh from https://build.opensuse.org/package/view_file/devel:openQA/openQA_container_worker
    group=$(ls -lhn /dev/kvm | cut -d ' ' -f 4)
    groupmod -g "$group" --non-unique kvm
    usermod -a -G kvm _openqa-worker
  else
    echo "Warning: /dev/kvm doesn't exist or the module isn't loaded. If you want to use KVM, run the container with --device=/dev/kvm"
  fi
fi

# For tests that have NICTYPE=tap, (i.e. tests that have to run in parallel with other tests)
# this creates the tap devices, brings them up, and disables the dbus calls that would normally be
# made in a non-containerized environment using openvswitch.
# For this to work, the podman run command must include: --device=/dev/net/tun --privileged --network=bridge
if [ -c "/dev/net/tun" ]  && lsmod | grep '\<tun\>' > /dev/null; then
  tunctl -u _openqa-worker -p -t tap$(($OPENQA_WORKER_INSTANCE - 1))
  ip link set tap$(($OPENQA_WORKER_INSTANCE - 1)) up
  perl -i -pe 'BEGIN{undef $/;} s/(sub start_qemu \(\$self\) {\s*\n\s*my \$vars = \\\%bmwqemu::vars;)/$1\n    \$vars->{QEMU_NON_FATAL_DBUS_CALL} = 1;/smg' /usr/lib/os-autoinst/backend/qemu.pm
else
  echo "Warning: /dev/net/tun doesn't exist or the module isn't loaded."
fi

chown -R _openqa-worker /var/lib/openqa && \
	chmod -R a+rw /var/lib/openqa

# Get or update any changes to the fedora tests
test_dir='/var/lib/openqa/share/tests/fedora'
if [ ! -d "$test_dir" ]; then
  su _openqa-worker -c "\
    export dist_name=fedora; \
    export dist=fedora; \
    export giturl='https://pagure.io/fedora-qa/os-autoinst-distri-fedora'; \
    export branch=main; \
    export username='openQA fedora'; \
    export needles_separate=0; \
    export needles_giturl='https://pagure.io/fedora-qa/os-autoinst-distri-fedora'; \
    export needles_branch=main;
    /usr/share/openqa/script/fetchneedles;"
    git config --global --add safe.directory /var/lib/openqa/share/tests/fedora
else
  su _openqa-worker -c "git -C '$test_dir' pull" || true
fi

qemu-system-x86_64 -S &
kill $!

su _openqa-worker -c "/usr/share/openqa/script/openqa-workercache-daemon" &
su _openqa-worker -c "/usr/share/openqa/script/openqa-worker-cacheservice-minion" &
su _openqa-worker -c "/usr/share/openqa/script/worker --verbose --instance \"$OPENQA_WORKER_INSTANCE\""

cleanup