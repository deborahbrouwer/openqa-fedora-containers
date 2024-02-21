
## Table of Contents

- [About](#about)
- [The web UI container](#The-web-UI-container)
    - [CLI usage](#cli-usage)
    - [Configuration](#configuration)
    - [Login](#login)
    - [Loading Tests](#loading-tests)
    - [Scheduling Tests](#scheduling-tests)
- [The worker container](#The-worker-container)

# About  
This repository contains scripts to build and run a containerized deployment of [openQA](https://github.com/os-autoinst).  The containers are specifically designed to leverage cloud resources and are customized to support [Fedora](https://fedoraproject.org/wiki/OpenQA) release and update testing. 

# The web UI container  

The web UI container runs an apache web server on port 8080.  It displays the live test results in a web browser and is also responsible for scheduling tests and the workers to run them; communicating with workers via REST API calls; and enabling interactive editing of tests and needles through the livehandler. The web UI acts a reverse proxy so that all communications with workers are routed to it through a single port.  

Several directories are kept on the host and are bound into the web UI container when it runs. This allows data to persist beyond the container's lifetime.  
* `tests/`: the full [os-autoinst-distri-fedora](https://pagure.io/fedora-qa/os-autoinst-distri-fedora) repository where all the Fedora tests and needles reside.  The container scripts will pull the full directory or just update it so that the tests are always up-to-date.
* `data/`: the PostgreSQL database where login information as well as test scheduling and results are stored
* `hdd/`: holds OS images for testing.  Sometimes the images will be downloaded by the test from  `fedoraproject.org` but, in other cases, the images need to be generated on the host using Fedora's [createhdds](https://pagure.io/fedora-qa/createhdds).  If the host machine isn't itself running Fedora, then `createhdds` can't be run and some, but not all, of the tests will fail to execute.
* `iso/`: holds iso files for testing.
  
Delete any of these directories to force their reinitialization by the container scripts.

### CLI usage  
```bash
./openqa_web.sh -h

Usage: ./openqa_web.sh [-b|-c|-h][-d <openQA_debug_path>]

Run the webUI container with './openqa_web.sh'
Options:
	-b	Build the web UI container image.
	-c	Get and run createhdds to provide images unavailable through fedoraproject.org.
	-h	Show this help message.
	-d	For debugging: specify a local path to openQA repository.
```

### Configuration    

`client.conf`  
The application [fedora_openqa](https://pagure.io/fedora-qa/fedora_openqa) can be used to schedule tests on the web UI.  To authorize `fedora-openqa.py` to access the web UI, change the first line of client.conf `[172.31.1.1:8080]` to your web server address.  
>Note: If running it locally, don't just use `localhost` in this configuration because it will be interpreted as the container's localhost not the host's localhost
>Alternatively pass the host name directly to `fedora-openqa.py` with `--openqa-hostname 172.31.1.1`    


### Login
Login as `Demo` through the web UI

### Loading Tests  
`podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c 'cd /var/lib/openqa/share/tests/fedora/; ./fifloader.py --load  templates.fif.json templates-updates.fif.json'`
   
### Scheduling Tests

Here are some examples, update the BUILDURL from `https://openqa.fedoraproject.org/`:   

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py fcosbuild -f   	https://builds.coreos.fedoraproject.org/prod/streams/testing-devel/builds/39.20240205.20.2/x86_64'`  

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f   	https://kojipkgs.fedoraproject.org/compose/cloud/Fedora-Cloud-39-20240207.0/compose'`  

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f --flavors Cloud_Base-qcow2-qcow2  https://kojipkgs.fedoraproject.org/compose/rawhide/Fedora-Rawhide-20240207.n.0/compose'`

   `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f  --flavors Server-dvd-iso 	 	https://kojipkgs.fedoraproject.org/compose/branched/Fedora-40-20240216.n.0/compose'`  


# The worker container

### CLI usage  
```bash
```

### Configuration    
  `client.conf`  
     * change `[172.31.1.1]` to the web UI host  

    `workers.ini`  
      * change `HOST = http://172.31.1.1:8080` to the web UI host  
      * change `WORKER_HOSTNAME = 172.31.1.1` to the location where the web UI host can send commands to the worker for developer mode.  Setting the `WORKER_HOSTNAME` is crucial if the worker is running in a container because otherwise the worker will (falsely) advertise its container id as the best location to reach the worker.  

### Run workers     
e.g. this command runs three workers:  
`./openqa_worker.sh -n 3` 

    > If needed, the script will build the worker image, pull tests etc.  
    > See usage with `./openqa_worker.sh -h`  

Refresh your browser. Sometimes it will take a minute or two for the web and workers to start talking.  

### Stopping workers     
`./openqa_worker.sh -n 0`
    > The workers need to tell the web UI that they are stopping and will no longer be available to accept tests.  If the workers are not stopped gracefully, the web UI will slow down substantially as it continues to send tests to unavailable workers.  

