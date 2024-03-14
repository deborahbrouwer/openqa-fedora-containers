
## Table of Contents

- [About](#about)
- [The web UI container](#The-web-UI-container)
    - [Web Configuration](#web-configuration)
    - [Login](#login)
    - [Loading Tests](#loading-tests)
    - [Scheduling Tests](#scheduling-tests)
- [The worker container](#The-worker-container)
    - [Worker Configuration](#worker-configuration)
    - [Running workers](#running-workers)
    - [Stopping workers](#stopping-workers)

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

### Web Configuration    

|                           client.conf    |    |
|----------------------------------------------------------------|---------------------------------|
| `[172.31.1.1]`                              | Authorize `fedora-openqa.py` to schedule tests. It's wrong to use `localhost` since this is the container's localhost.      |

### Login
Login as `Demo` through the web UI

### Loading Tests  
```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c 'cd /var/lib/openqa/share/tests/fedora/;
./fifloader.py --load  templates.fif.json templates-updates.fif.json'
```
   
### Scheduling Tests

>Note tests can't be scheduled if `client.conf` is not configured.  And it must be configured __before__ the web server starts.

Here are some examples.
The BUILDURLs are frequently updated so find the latest from [https://openqa.fedoraproject.org/](https://openqa.fedoraproject.org/):   

```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py \
fcosbuild -f https://builds.coreos.fedoraproject.org/prod/streams/rawhide/builds/41.20240305.91.0/x86_64'
```
```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py \
fcosbuild -f  	https://builds.coreos.fedoraproject.org/prod/streams/rawhide/builds/41.20240302.91.0/x86_64'
```

```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py \
compose -f https://kojipkgs.fedoraproject.org/compose/cloud/Fedora-Cloud-39-20240306.0/compose'
```

```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py \
compose -f --flavors Server-dvd-iso \
https://kojipkgs.fedoraproject.org/compose/rawhide/Fedora-Rawhide-20240305.n.0/compose'
```

```bash
podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py \
compose -f --flavors Server-dvd-iso \
https://kojipkgs.fedoraproject.org/compose/branched/Fedora-40-20240306.n.0/compose'
```

Alternatively, tests can be run with `openqa-cli`.
Using this tool requires a manual check of the variables expected by the tests as set out in `os-autoinst-distri-fedora/templates.fif.jsontemplates.fif.json`.  
For example, these commands schedule two tests that must be run in parallel:  

```bash
openqa-cli api -X POST isos \
ARCH=x86_64 \
BUILD=Fedora-Rawhide-20240206.n.0 \
UP1REL=39 \
DISTRI=fedora \
FLAVOR=universal \
TEST=upgrade_server_domain_controller \
VERSION=Rawhide

openqa-cli api -X POST isos \
ARCH=x86_64 \
BUILD=Fedora-Rawhide-20240206.n.0 \
UP1REL=39 \
DISTRI=fedora \
FLAVOR=universal \
TEST=upgrade_realmd_client \
VERSION=Rawhide
```

To cancel jobs:  
`for JOB_ID in {226..342}; do openqa-cli api -X POST jobs/$JOB_ID/cancel; done`


# The worker container

### Worker Configuration    
|                           client.conf    |    |
|----------------------------------------------------------------|---------------------------------|
|`[172.31.1.1]`                                | The web UI host. Authorizes workers to carry out tests.      |

|                            workers.ini    |    |
|----------------------------------------------------------------|---------------------------------|
| `HOST = http://172.31.1.1:8080`                                | The web UI host. It's wrong to use `localhost` since this is the container's localhost.       |
| `WORKER_HOSTNAME = 172.31.1.1`                                 | For developer mode: the worker's location for receiving livelog. |
| `AUTOINST_URL_HOSTNAME = 172.31.1.1`                           | For logging: the worker's location for receiving qemu logs.   |


### Running workers     
For example, this command runs three workers:  
`./openqa_worker.sh -n 3` 

If a test needs a specific `WORKER_CLASS` set the worker class like this:  
`./openqa_worker.sh -n2 -c qemu_x86_64,vde_Fedora-CoreOS-41.20240302.91.0`  

There are options for using local repositories for debugging, e.g.:  
`./openqa_worker.sh -n2 -c qemu_x86_64,vde_Fedora-CoreOS-41.20240305.91.0 -g ../../os-autoinst`  

### Stopping workers     
`./openqa_worker.sh -n 0`  
>The workers need to tell the web UI that they are stopping and will no longer be available to accept tests.  If the workers are not stopped gracefully, the web UI will slow down substantially as it continues to send tests to unavailable workers.  


