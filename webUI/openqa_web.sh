#!/bin/bash
set -e
REPOSITORY=openqa_webui

usage() {
		echo -e "\nUsage: $0 [Options]\n"
		echo "Options:"
		echo "	-b	Build the web UI container image."
		echo "	-c	Get and run createhdds to provide images unavailable through fedoraproject.org."
		echo "	-h	Show this help message."
		echo "	-d	For debugging: specify a local path to openQA repository."
		echo "	-f	For debugging: specify a local path to os-autoinst-distri-fedora"
		echo "	-s	For debugging: specify a local path to fedora_openqa"
		exit 1
}

get_openqa_webui_image_id() {
	OPENQA_WEBUI_IMAGE_ID=$(podman images --filter "reference=${REPOSITORY}" --format "{{.Repository}} {{.Tag}} {{.ID}}" | awk '$2 == "latest" {print $3}')
}

build_openqa_webui_image() {
	CHANGES=$(git diff --name-only HEAD -- | grep -Ev "(client.conf|openqa.ini)$") || true
	if [ -n "$CHANGES" ]; then
		echo "Stash or commit changes before building image."
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

run_createhdds() {
	if [ ! -d "$PWD/hdd" ] && [ ! -L "$PWD/hdd" ]; then
		mkdir "$PWD/hdd"
	fi
	if [ ! -d "$PWD/createhdds" ] && [ ! -L "$PWD/createhdds" ]; then
		git clone https://pagure.io/fedora-qa/createhdds
	fi

	cd createhdds
	# createhdds must run in the background so that it can be interrupted by this shell script
	./createhdds.py all -c > temp.log 2>&1 &

	# Exit if there are any errors e.g. missing dependencies preventing createhdds from running.
	sleep 1
	if grep -q "Traceback" temp.log; then
		cat temp.log
		exit 1;
	fi
	PID=$!

	# While createhdds is running, check if it is hanging and if so, then
	# copy the temp file, force createhdds to stop, and then restart it
	while kill -0 $PID 2>/dev/null; do
		FILE_NAME=$(grep "qcow2" temp.log | head -n 1 | sed -n 's/.*\(disk_[^ ]*.qcow2\).*/\1/p')
		sleep 5
		if [[ -f "$FILE_NAME.tmp" ]]; then
			echo "-->copying $FILE_NAME.tmp"
			cp "$FILE_NAME.tmp" $FILE_NAME
			kill -SIGINT $PID
			rm temp.log
			./createhdds.py all -c > temp.log 2>&1 &
			PID=$!
		fi
	done
	rm temp.log

	# then move the file to hdd/
	# then change the SELinux context (ls -lZ) so that the image can be accessed in the container
	for file in *; do
		if [[ "$file" == *.qcow2 ]] || [[ "$file" == *.img ]]; then
			if [ ! -f "../hdd/$file" ]; then
				cp "$file" ../hdd/
				chcon system_u:object_r:container_file_t:s0 ../hdd/$file;
				chmod a+rw ../hdd/$file;
				files_copied=1
			fi
		fi
	done
	cd ..

	if [ "$files_copied" ] && [ "$(podman ps -q --format "{{.Image}} {{.ID}}" | grep "$REPOSITORY")" ]; then
		echo -e "\n--> Warning images were copied to hdd/ while the web UI container is running."
		echo "--> Restart the web UI container to access these images."
	fi

}

# For all options, make sure that this script is running from inside the webUI directory.
# The webUI directory is the context directory for the Dockerfile and is also
# where the container expects to find assets and files that will be bound in to the container.
cd $(dirname "$0")

while getopts ":bchd:f:s:" opt; do
	case ${opt} in
		b )
			build_openqa_webui_image
			exit
			;;
		c )
			run_createhdds
			exit
			;;
		h )
			usage
			;;
		d )
			openQA_debug_path=$OPTARG
			;;
		f )
			os_autoinst_distri_fedora_path=$OPTARG
			;;
		s )
			fedora_openqa_debug_path=$OPTARG
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

get_openqa_webui_image_id
if [ -z "$OPENQA_WEBUI_IMAGE_ID" ]; then
	echo "There is no 'openqa_webui' container image available."
	echo "Run 'openqa_web.sh -b' to build the image before running it."
	exit 1
fi

if [ ! -d "$PWD/hdd" ] && [ ! -L "$PWD/hdd" ]; then
	mkdir "$PWD/hdd"
	echo -e "\nCreating new hdd asset directory."
	echo "--> Warning: Some tests need images that must be built locally with createhdds."
	echo -e "--> Run 'openqa_web.sh -c' to get and run createhdds.\n"
fi

if [ ! -d "$PWD/iso" ] && [ ! -L "$PWD/iso" ]; then
	mkdir "$PWD/iso"
	# TODO find a way to get any changes to cloudinit. E.g.
	# wget "https://openqa.fedoraproject.org/tests/2389341/asset/iso/cloudinit.iso" -P "$PWD/iso"
	cp "$PWD/cloudinit.iso" "$PWD/iso"
fi
if [ ! -d "$PWD/data" ] && [ ! -L "$PWD/data" ]; then
	mkdir "$PWD/data"
fi

# https://github.com/os-autoinst/openQA.git
if [ -n "$openQA_debug_path"  ]; then
	if [[ $openQA_debug_path == */ ]]; then
			openQA_debug_path=${openQA_debug_path%/}
	fi
	openqa_debug_arg="-v $openQA_debug_path/script/:/usr/share/openqa/script/:z \
		-v $openQA_debug_path/lib/OpenQA/:/usr/share/openqa/lib/OpenQA/:z \
		-v $openQA_debug_path/assets/:/usr/share/openqa/assets/:z "
fi

# https://pagure.io/fedora-qa/os-autoinst-distri-fedora
if [ -n "$os_autoinst_distri_fedora_path" ]; then
	if [[ $os_autoinst_distri_fedora_path == */ ]]; then
		os_autoinst_distri_fedora_path=${os_autoinst_distri_fedora_path%/}
	fi
	os_autoinst_distri_fedora_arg="-v $os_autoinst_distri_fedora_path/:/var/lib/openqa/share/tests/fedora/:z "
else
	if [ ! -d "$PWD/tests" ] && [ ! -L "$PWD/tests" ]; then
		mkdir "$PWD/tests"
	fi
	os_autoinst_distri_fedora_arg="-v $PWD/tests:/var/lib/openqa/share/tests:z "
fi

# https://pagure.io/fedora-qa/fedora_openqa.git
if [ -n "$fedora_openqa_debug_path" ]; then
	if [[ $fedora_openqa_debug_path == */ ]]; then
		fedora_openqa_debug_path=${fedora_openqa_debug_path%/}
	fi
	fedora_openqa_debug_arg="-v $fedora_openqa_debug_path/:/fedora_openqa:z "
fi

podman run -p 8080:80 \
--network=slirp4netns \
-v $PWD/hdd:/var/lib/openqa/share/factory/hdd:z \
-v $PWD/iso:/var/lib/openqa/share/factory/iso:z \
-v $PWD/data:/var/lib/pgsql/data/:z \
-v $PWD/client.conf:/etc/openqa/client.conf:z \
-v $PWD/openqa.ini:/etc/openqa/openqa.ini:z \
-v $PWD/init_openqa_web.sh:/init_openqa_web.sh:z \
${os_autoinst_distri_fedora_arg} \
${openqa_debug_arg} \
${fedora_openqa_debug_arg} \
--rm -it $OPENQA_WEBUI_IMAGE_ID
