#!/bin/bash
# Note: this is a modification of upstream openqa/container/worker/run_openqa_worker.sh
set -e

function cleanup() {
	echo "Return ownership of bound directories back to container host."
	chown -R root:root /var/lib/openqa/ /usr/share/openqa/ /run/openqa
	exit
}
trap cleanup SIGTERM SIGINT

# update the openqa package

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

chown -R _openqa-worker /var/lib/openqa && \
	chmod -R a+rw /var/lib/openqa

chown -R _openqa-worker /usr/share/openqa/ && \
	chmod -R a+rw /usr/share/openqa/

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

if echo "$WORKER_CLASS" | grep -q "tap"; then
	# --> os-autoinst-:There is no systemd in the container so ignore the dbus failures
	perl -i -pe 'BEGIN{undef $/;} s/(sub start_qemu \(\$self\) {\s*\n\s*my \$vars = \\\%bmwqemu::vars;)/$1\n		\$vars->{QEMU_NON_FATAL_DBUS_CALL} = 1;/smg' /usr/lib/os-autoinst/backend/qemu.pm


	chown -R _openqa-worker /run/openqa && \
	chmod -R a+rw /run/openqa
	# dnf install -y iputils iptables nmap
	# dnf install -y openvswitch iputils iptables nmap
	# /usr/share/openvswitch/scripts/openvswitch.init start
	# ovs-vsctl add-br br0;
	# ip addr add 172.16.2.2/24 dev br0;
	# ip link set br0 up;
	# ovs-vsctl add-port br0 tap$(($OPENQA_WORKER_INSTANCE - 1));
	# tunctl -u _openqa-worker -p -t tap$(($OPENQA_WORKER_INSTANCE - 1));
	# ip link set tap$(($OPENQA_WORKER_INSTANCE - 1)) up;
	# ip link set br0 up;
	# ip link set ovs-system up;

	# All traffic from qemu vm is masked so that it looks like it's coming from the container

	iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
	iptables -t nat -L --line-numbers -n -v

	# make sure ip forwarding is enabled
	echo 1 > /proc/sys/net/ipv4/ip_forward

	# Depending on what test this worker receives, it will need to dynamically adjust its iptables; give it that authority
	# echo "_openqa-worker ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/_openqa-worker
	# chmod 440 /etc/sudoers.d/_openqa-worker

	# --> openQA: add new function to dynamically find the server's ip after the tests are scheduled
	# lib_path="/usr/share/openqa/lib/OpenQA/Worker/Engines/isotovideo.pm"
	# dynamic_server_path="/usr/share/openqa/lib/OpenQA/Worker/Engines/dynamic_server.pm"
	# awk -v file="$dynamic_server_path" '
    # /my \$workerpid;/ {
    #     print;
    #     while (getline < file > 0) {
    #         print;
    #     }
    #     next;
    # }
    # { print }
	# ' "$lib_path" > temp && mv temp "$lib_path"

	# --> openQA: add a new variable to pass the dynamic server ip to the qemu vm
	# sed -i '/my %vars = (/a \        TEST_SERVER => get_dynamic_server_ip($job_info->{test}),' /usr/share/openqa/lib/OpenQA/Worker/Engines/isotovideo.pm

	# --> os-autoinst-distri-fedora: change dns resolver inside qemu vm
	# test_path="/var/lib/openqa/share/tests/fedora/tests/"
	# perl -i -pe 'BEGIN{undef $/;} s/\(tty => 3\);/$&\n  type_string "rm \/etc\/resolv.conf\\necho \x27nameserver 8.8.8.8\x27 > \/etc\/resolv.conf\\n";/smg' "${test_path}podman.pm"
	# perl -i -pe 'BEGIN{undef $/;} s/\(tty => 3\);/$&\n  type_string "rm \/etc\/resolv.conf\\necho \x27nameserver 8.8.8.8\x27 > \/etc\/resolv.conf\\n";/smg' "${test_path}_podman_client.pm"

	# --> os-autoinst-distri-fedora: add ip routing inside the qemu vm using dynamic test server ip
	# perl -i -pe 'BEGIN{undef $/;} s/\(tty => 3\);/$&\n    type_string "rm \/etc\/resolv.conf\\necho \x27nameserver 8.8.8.8\x27 > \/etc\/resolv.conf\\n";\n    my \$test_server = get_var("TEST_SERVER");\n    type_string "iptables -t nat -A OUTPUT -d 172.16.2.114 -j DNAT --to-destination \$test_server\\n";/smg' "${test_path}_podman_client.pm"

fi

qemu-system-x86_64 -S &
kill $!

su _openqa-worker -c "/usr/share/openqa/script/openqa-workercache-daemon" &
su _openqa-worker -c "/usr/share/openqa/script/openqa-worker-cacheservice-minion" &
su _openqa-worker -c "/usr/share/openqa/script/worker --verbose --instance \"$OPENQA_WORKER_INSTANCE\""

cleanup