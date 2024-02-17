#!/bin/bash
set -e
REPOSITORY=openqa_worker

usage() {
	echo "Usage: $0 -n NUMBER_OF_WORKERS [-b|-h] [-c <WORKER_CLASS>] [-d <openQA_path>] [-g <os-autoinst_path>]"
	echo "Options:"
	echo "	-b	Build the worker container image."
	echo "	-c	set WORKER_CLASS; default is 'qemu_x86_64,tap,tap2'"
	echo "	-h	Show this help message"
	echo "	-d	For debugging: specify a local path to openQA repository"
	echo "	-g	For debugging: specify a local path to os-autoinst repository"
	echo "	-n	Number of openqa_worker containers to run."
	echo "Stop all worker containers gracefully with '-n 0'"
	exit 1
}

get_openqa_worker_image_id() {
	OPENQA_WORKER_IMAGE_ID=$(podman images --filter "reference=${REPOSITORY}" --format "{{.Repository}} {{.Tag}} {{.ID}}" | awk '$2 == "latest" {print $3}')
}

build_openqa_worker_image() {
	CHANGES=$(git diff --name-only HEAD -- | grep -Ev "^(client.conf|workers.ini)$") || true
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

# Parse options
while getopts ":bc:hd:g:n:" opt; do
	case ${opt} in
		b )
			build_openqa_worker_image
			exit
			;;
		c )
			WORKER_CLASS=$OPTARG
			sed -i "/^WORKER_CLASS/c\WORKER_CLASS=$WORKER_CLASS" workers.ini
			echo "set 'WORKER_CLASS = $WORKER_CLASS'"
			;;
		h )
			usage
			;;
		d )
			openqa_path=$OPTARG
			;;
		g )
			osauto_path=$OPTARG
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

if [ -n "$openqa_path"  ]; then
	if [[ $openqa_path == */ ]]; then
			openqa_path=${openqa_path%/}
	fi
	openqa_debug_arg="-v $openqa_path/script/:/usr/share/openqa/script/:z \
		-v $openqa_path/lib/OpenQA/:/usr/share/openqa/lib/OpenQA/:z \
		-v $openqa_path/assets/:/usr/share/openqa/assets/:z "
fi

if [ -n "$osauto_path" ]; then
	if [[ $osauto_path == */ ]]; then
		osauto_path=${osauto_path%/}
	fi
	# Upstream os-autoinst is quite different from fedora os-autoinst package
	# so do not bind in the entire directory when debugging or it will break.
	osauto_debug_arg="-v $osauto_path/backend/:/usr/lib/os-autoinst/backend/:z"
fi

if [ ! -d "$PWD/tests" ] && [ ! -L "$PWD/tests" ]; then
	mkdir "$PWD/tests"
fi

get_openqa_worker_image_id
if [ -z "$OPENQA_WORKER_IMAGE_ID" ]; then
	echo "Building 'openqa_worker' image."
	build_openqa_worker_image
	get_openqa_worker_image_id
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
	--device=/dev/kvm \
	--pids-limit=-1 \
	--device=/dev/net/tun \
	--privileged \
	--network=bridge \
	${detached_arg} \
	-e OPENQA_WORKER_INSTANCE=$OPENQA_WORKER_INSTANCE \
	-p $DEVELOPER_MODE_PORT:$DEVELOPER_MODE_PORT \
	-p $VNC_PORT:$VNC_PORT \
	-v $PWD/tests/:/var/lib/openqa/share/tests/:z \
	-v $PWD/workers.ini:/etc/openqa/workers.ini:z \
	-v $PWD/client.conf:/etc/openqa/client.conf:z \
	-v $PWD/init_openqa_worker.sh:/init_openqa_worker.sh:z \
	${openqa_debug_arg} \
	${osauto_debug_arg} \
	--rm -it $OPENQA_WORKER_IMAGE_ID

	((OPENQA_WORKER_INSTANCE++))
done
