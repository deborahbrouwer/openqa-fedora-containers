#!/bin/bash
set -e
REPOSITORY=openqa_webui

usage() {
		echo "Usage: $0 [-b|-c|-h][-d <openQA_path>]"
		echo "To start the webUI container, just run this script without any options."
		echo "Options:"
		echo "	-b	Build the web UI container image."
		echo "	-c	Get and run createhdds to provide images unavailable through fedoraproject.org."
		echo "	-h	Show this help message."
		echo "	-d	For debugging: specify a local path to openQA repository."
		exit 1
}

get_openqa_webui_image_id() {
	OPENQA_WEBUI_IMAGE_ID=$(podman images --filter "reference=${REPOSITORY}" --format "{{.Repository}} {{.Tag}} {{.ID}}" | awk '$2 == "latest" {print $3}')
}

build_openqa_webui_image() {
	CHANGES=$(git diff --name-only HEAD -- | grep -Ev "(client.conf|openqa.ini)$") || true
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

run_createhdds() {
	if [ ! -d "$PWD/hdd" ] && [ ! -L "$PWD/hdd" ]; then
		mkdir "$PWD/hdd"
	fi
	if [ ! -d "$PWD/createhdds" ] && [ ! -L "$PWD/createhdds" ]; then
		git clone https://pagure.io/fedora-qa/createhdds
	fi

	cd createhdds
	./createhdds.py all -c > temp.log 2>&1 &
	PID=$!

	# while createhdds is running, check if it is hanging and if so, then
	# copy the temp file, force it to stop, and then start it again
	while kill -0 $PID 2>/dev/null; do
		FILE_NAME=$(grep "qcow2" temp.log | head -n 1 | sed -n 's/.*\(disk_[^ ]*.qcow2\).*/\1/p')
		sleep 5
		if [[ -f "$FILE_NAME.tmp" ]]; then
			echo "copying $FILE_NAME.tmp"
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
			cp "$file" ../hdd/
			chcon system_u:object_r:container_file_t:s0 ../hdd/$file;
			chmod a+rw ../hdd/$file;
		fi
	done
	cd ..
}

# Parse options
while getopts ":bchd:" opt; do
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
			openQA_path=$OPTARG
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

if [[ -n "$openQA_path" ]]; then
	if [[ $openQA_path == */ ]]; then
			openQA_path=${openQA_path%/}
	fi

	debug_arg="-v $openQA_path/script/:/usr/share/openqa/script/:z \
		-v $openQA_path/lib/OpenQA/:/usr/share/openqa/lib/OpenQA/:z \
		-v $openQA_path/assets/:/usr/share/openqa/assets/:z \
		-v $openQA_path/templates/:/usr/share/openqa/templates/:z "
fi

if [ ! -d "$PWD/hdd" ] && [ ! -L "$PWD/hdd" ]; then
	mkdir "$PWD/hdd"
	run_createhdds
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
if [ ! -d "$PWD/tests" ] && [ ! -L "$PWD/tests" ]; then
	mkdir "$PWD/tests"
fi

get_openqa_webui_image_id
if [ -z "$OPENQA_WEBUI_IMAGE_ID" ]; then
	echo "Building 'openqa_webui' image."
	build_openqa_webui_image
	get_openqa_webui_image_id
fi

podman run -p 8080:80 \
-v $PWD/hdd:/var/lib/openqa/share/factory/hdd:z \
-v $PWD/iso:/var/lib/openqa/share/factory/iso:z \
-v $PWD/data:/var/lib/pgsql/data/:z \
-v $PWD/tests:/var/lib/openqa/share/tests/:z \
-v $PWD/client.conf:/etc/openqa/client.conf:z \
-v $PWD/openqa.ini:/etc/openqa/openqa.ini:z \
-v $PWD/init_openqa_web.sh:/init_openqa_web.sh:z \
${debug_arg} \
--rm -it $OPENQA_WEBUI_IMAGE_ID