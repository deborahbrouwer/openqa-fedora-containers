
## web UI container  

1. Configure the web UI:  

    `client.conf`  
    * change the first line `[172.31.1.1:8080]` to your web server.  
      > To schedule the tests `fedora-openqa.py` will take authorization from the first entry in `client.conf` or you can pass the host name directly to `fedora-openqa.py` with `--openqa-hostname 172.31.1.1`    

2. Start the web UI container:

    `./openqa_web.sh`  

    > If needed, the script will build the web UI image, create assets, pull tests etc.  
    > See usage with `./openqa_web.sh -h`  

3. Login as `Demo` through the web UI
   > It's only necessary to login the first time that the PostgreSQL database is initialized.
   > To force the database to reinitialize, just delete the `data` directory.  

4. Load the fedora tests:  
`podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c 'cd /var/lib/openqa/share/tests/fedora/; ./fifloader.py --load  templates.fif.json templates-updates.fif.json'`
   
5. Schedule some fedora tests 

    Here are some examples, update the BUILDURL from `https://openqa.fedoraproject.org/`:   

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py fcosbuild -f   	https://builds.coreos.fedoraproject.org/prod/streams/testing-devel/builds/39.20240205.20.2/x86_64'`  

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f   	https://kojipkgs.fedoraproject.org/compose/cloud/Fedora-Cloud-39-20240207.0/compose'`  

    `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f --flavors Cloud_Base-qcow2-qcow2  https://kojipkgs.fedoraproject.org/compose/rawhide/Fedora-Rawhide-20240207.n.0/compose'`

   `podman exec $(podman ps -aq --filter label=title=openqa_webui) sh -c '/fedora_openqa/fedora-openqa.py compose -f  --flavors Server-dvd-iso 	 	https://kojipkgs.fedoraproject.org/compose/branched/Fedora-40-20240216.n.0/compose'`  


## worker containers

1. Configure the worker:  
  `client.conf`  
     * change `[172.31.1.1]` to the web UI host  

    `workers.ini`  
      * change `HOST = http://172.31.1.1:8080` to the web UI host  
      * change `WORKER_HOSTNAME = 172.31.1.1` to the location where the web UI host can send commands to the worker for developer mode.  Setting the `WORKER_HOSTNAME` is crucial if the worker is running in a container because otherwise the worker will (falsely) advertise its container id as the best location to reach the worker.  

2. Run some workers  
e.g. this command runs three workers:  
`./openqa_worker.sh -n 3` 

    > If needed, the script will build the worker image, pull tests etc.  
    > See usage with `./openqa_worker.sh -h`  

3. Refresh your browser. Sometimes it will take a minute or two for the web and workers to start talking.  

4. If necessary, stop the workers gracefully with:  
`./openqa_worker.sh -n 0`
    > The workers need to tell the web UI that they are stopping and will no longer be available to accept tests.  If the workers are not stopped gracefully, the web UI will slow down substantially as it continues to send tests to unavailable workers.  

