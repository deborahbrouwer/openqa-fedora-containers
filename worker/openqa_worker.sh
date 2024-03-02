#!/bin/bash
set -e
REPOSITORY=opensuse_worker
WORKER_CLASS=qemu_x86_64

usage() {
	echo -e "\nUsage: $0 \
			  -n NUMBER_OF_WORKERS\n \
			  [-b|-h] \
			  [-c <WORKER_CLASS>]\n \
			  [-d <openQA_debug_path>]\n \
			  [-f <os-autoinst-distri-fedora>]\n \
			  [-g <os-autoinst_debug_path>]\n"
	echo -e "\nOptions:"
	echo "	-b	Build the worker container image."
	echo "	-c	set WORKER_CLASS; default is 'qemu_x86_64'; e.g. -c qemu_x86_64,tap2"
	echo "	-h	Show this help message"
	echo "	-d	For debugging: specify a local path to openQA repository"
	echo "	-f	For debugging: specify a local path to os-autoinst-distri-fedora"
	echo "	-g	For debugging: specify a local path to os-autoinst repository"
	echo "	-n	Number of openqa_worker containers to run."
	echo -e "\nStop all worker containers gracefully with '-n 0'"
	exit 1
}

get_openqa_worker_image_id() {
	OPENQA_WORKER_IMAGE_ID=$(podman images --filter "reference=${REPOSITORY}" --format "{{.Repository}} {{.Tag}} {{.ID}}" | awk '$2 == "latest" {print $3}')
}

build_openqa_worker_image() {
	CHANGES=$(git diff --name-only HEAD -- | grep -Ev "(client.conf|workers.ini)$") || true
	if [ -n "$CHANGES" ]; then
		echo "Stash or commit changes before building image. Exiting."
		exit 1
	fi

	# Keep the previous image and retag it as "old" and delete any older images
	while IFS= read -r line; do
		echo "$line"
		image_id=$(echo "$line" | awk '{print $3}')
		tag=$(echo "$line" | awk '{print $2}')
		if [ "$tag" == "latest" ]; then
				podman tag "${REPOSITORY}:latest" "${REPOSITORY}:old"
		else
				podman rmi $image_id || true
		fi
	done < <(podman images --filter "reference=${REPOSITORY}" --format "{{.Repository}} {{.Tag}} {{.ID}} {{.CreatedAt}}")

	podman build --no-cache -t $REPOSITORY .
}

cd $(dirname "$0")

while getopts ":bc:hd:f:g:n:" opt; do
	case ${opt} in
		b )
			build_openqa_worker_image
			exit
			;;
		c )
			WORKER_CLASS=$OPTARG
			;;
		h )
			usage
			;;
		d )
			openQA_debug_path=$OPTARG
			;;
		f )
			test_debug_path=$OPTARG
			;;
		g )
			osauto_debug_path=$OPTARG
			;;
		n )
			number_of_workers=$OPTARG
			;;
		\? )
			echo "Invalid option: $OPTARG" 1>&2
			usage
			;;
		: )
			echo "Invalid option: $OPTARG requires an argument" 1>&2
			usage
			;;
	esac
done

if [ $(($# - ${OPTIND:-0} + 1)) -gt 0 ]; then
	echo "Unsupported arguments. Exiting."
	usage
	exit 1
fi

if [ -z "$number_of_workers" ]; then
	echo "Error: Specify the number of openqa_worker containers to start."
	usage
fi

get_openqa_worker_image_id
if [ -z "$OPENQA_WORKER_IMAGE_ID" ]; then
	echo "There is no 'openqa_worker' container image available."
	echo "Run 'openqa_worker.sh -b' to build the image before running it."
	exit 1
fi

# Find all the existing openqa_worker containers on this machine
mapfile -t worker_container_ids < <(podman ps -q --format "{{.Image}} {{.ID}}" | grep "$REPOSITORY" | awk '{print $2}')

# Stop all the workers gracefully, by giving them the opportunity to tell the scheduler
# that they are going offline. Otherwise scheduler will keep trying to send tests to non-existent workers.
if [ $number_of_workers -le 0 ]; then
	for container_id in "${worker_container_ids[@]}"; do
		process_id=$(podman exec "$container_id" pgrep -f 'perl /usr/share/openqa/script/worker' | head -n 1)
		podman exec -it $container_id sh -c "kill $process_id"
		echo "killed $container_id"
	done
	exit
fi

if [ -n "$openQA_debug_path"  ]; then
	if [[ $openQA_debug_path == */ ]]; then
			openQA_debug_path=${openQA_debug_path%/}
	fi
	openqa_debug_arg="-v $openQA_debug_path/script/:/usr/share/openqa/script/:z \
		-v $openQA_debug_path/lib/OpenQA/:/usr/share/openqa/lib/OpenQA/:z \
		-v $openQA_debug_path/assets/:/usr/share/openqa/assets/:z "
fi

if [ -n "$osauto_debug_path" ]; then
	if [[ $osauto_debug_path == */ ]]; then
		osauto_debug_path=${osauto_debug_path%/}
	fi
	# Upstream os-autoinst is quite different from fedora os-autoinst package
	# so do not bind in the entire directory when debugging or it will break.
	osauto_debug_arg="-v $osauto_debug_path/backend/:/usr/lib/os-autoinst/backend/:z"
fi

# https://pagure.io/fedora-qa/os-autoinst-distri-fedora
if [ -n "$test_debug_path" ]; then
	if [[ $test_debug_path == */ ]]; then
		test_debug_path=${test_debug_path%/}
	fi
	test_arg="-v $test_debug_path/:/var/lib/openqa/share/tests/fedora/:z "
else
	if [ ! -d "$PWD/tests" ] && [ ! -L "$PWD/tests" ]; then
		mkdir "$PWD/tests"
	fi
	test_arg="-v $PWD/tests:/var/lib/openqa/share/tests:z "
fi

sed -i "/^WORKER_CLASS/c\WORKER_CLASS=$WORKER_CLASS" workers.ini
echo "set 'WORKER_CLASS = $WORKER_CLASS'"


dns=$(/usr/bin/resolvectl status | grep Servers | tail -1 | cut -d: -f2-)
if [ -z $dns ]; then
	dns=8.8.8.8
fi
dns_arg="--dns $dns "

if echo "$WORKER_CLASS" | grep -q "tap";  then
	if ! lsmod | grep -q openvswitch; then
		echo "Warning: 'modprobe openvswitch' is required to run tap-class worker."
		exit 1
	fi
	if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
		echo "Warning: IP forwarding is disabled. Add net.ipv4.ip_forward=1: to /etc/sysctl.conf and reload with sysctl -p"
		exit 1
	fi
	# Note podman will provide /dev/net/tun automatically, don't need to add --device=/dev/net/tun
	# tap_arg="--network=my_fed --privileged "
	tap_arg="--privileged -v /tmp/run/openqa:/run/openqa -v /tmp:/tmp "


	# Adds new function to discover dynamic ip of container when it holds the server test
	# tap_arg+=" -v $PWD/dynamic_server.pm:/usr/share/openqa/lib/OpenQA/Worker/Engines/dynamic_server.pm:z "
fi

OPENQA_WORKER_INSTANCE=1
for i in $(seq 1 $number_of_workers); do

	# Make sure that the new OPENQA_WORKER_INSTANCE will be unique
	# by checking all the running containers if any
	while true; do
		available=true
		for container_id in "${worker_container_ids[@]}"; do
			in_use=$(podman exec "$container_id" printenv OPENQA_WORKER_INSTANCE 2>/dev/null)
			if [ "$OPENQA_WORKER_INSTANCE" -eq "$in_use" ]; then
				available=false
				((OPENQA_WORKER_INSTANCE++))
				break;
			fi
		done
		if [ $available = true ]; then
			break
		fi
	done

	DEVELOPER_MODE_PORT=$((OPENQA_WORKER_INSTANCE * 10 + 20003))
	VNC_PORT=$((OPENQA_WORKER_INSTANCE + 5990))
	# Run all the workers detached except the last one
	detached_arg="-d "
	if [ $i -eq $number_of_workers ]; then
		detached_arg="";
	fi

	podman run \
	--init \
	--security-opt label=disable \
	--device=/dev/kvm \
	--pids-limit=-1 \
	${dns_arg} \
	${tap_arg} \
	${detached_arg} \
	-e OPENQA_WORKER_INSTANCE=$OPENQA_WORKER_INSTANCE \
	-e WORKER_CLASS=$WORKER_CLASS \
	-p $DEVELOPER_MODE_PORT:$DEVELOPER_MODE_PORT \
	-p $VNC_PORT:$VNC_PORT \
	-v $PWD/workers.ini:/etc/openqa/workers.ini:z \
	-v $PWD/client.conf:/etc/openqa/client.conf:z \
	-v $PWD/init_openqa_worker.sh:/init_openqa_worker.sh:z \
	${test_arg} \
	${openqa_debug_arg} \
	${osauto_debug_arg} \
	--rm -it $OPENQA_WORKER_IMAGE_ID

	((OPENQA_WORKER_INSTANCE++))
done

