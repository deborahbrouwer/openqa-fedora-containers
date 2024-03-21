#!/bin/bash
# Note: this is a modification of upstream openqa/container/webui/run_openqa.sh
set -e

function cleanup() {
  echo "Return ownership of bound directories back to container host."
  chown -R root:root /var/lib/pgsql /var/lib/openqa/ /usr/share/openqa/
  exit
}
trap cleanup SIGTERM SIGINT

function upgradedb() {
  echo "Waiting for DB creation"
  while ! su geekotest -c 'PGPASSWORD=openqa psql -h db -U openqa --list | grep -qe openqa'; do sleep .1; done
  su geekotest -c '/usr/share/openqa/script/upgradedb --upgrade_database'
}

function start_services() {
  su geekotest -c /usr/share/openqa/script/openqa-scheduler-daemon &
  su geekotest -c /usr/share/openqa/script/openqa-websockets-daemon &
  su geekotest -c /usr/share/openqa/script/openqa-gru &
  su geekotest -c /usr/share/openqa/script/openqa-livehandler-daemon &
  httpd -DSSL
  su geekotest -c /usr/share/openqa/script/openqa-webui-daemon
}

function start_database() {
  mkdir -p /var/run/postgresql
  chown -R postgres:postgres /var/lib/pgsql /var/run/postgresql && \
    find /var/lib/pgsql/data -type d -exec chmod 750 {} + && \
    find /var/lib/pgsql/data -type f -exec chmod 750 {} +

  chmod ug+r /var/lib/pgsql/data

  DATADIR="/var/lib/pgsql/data/"

  if [ -z "$(ls -A $DATADIR)" ]; then
    echo "Initializing PostgreSQL"
    su postgres -c "bash -c '/usr/bin/initdb ${DATADIR}'"
    if [ $? -ne 0 ]; then
      echo "Initialization failed."
      exit 1
    fi
  fi
  su postgres -c "bash -c '/usr/bin/pg_ctl -s -D ${DATADIR} start'"
  su postgres -c '/usr/bin/openqa-setup-db'

  # TODO: use upgradedb script here if necessary for real data
}

function add_cert() {
  # The default crt/key pairs are set in /etc/httpd/conf.d/ssl.conf
  # Adding /etc/httpd/conf.d/openqa-ssl.conf will override the defaults
  # openqa-ssl.conf names the crt/keys to use

  # Use defaults until ready to bind in real cert and keys with
  # -v $PWD/openqa.crt:/etc/pki/tls/certs/openqa.crt:z \
  # -v $PWD/openqa.key:/etc/pki/tls/private/openqa.key:z \
    local mojo_resources=$(perl -e 'use Mojolicious; print(Mojolicious->new->home->child("Mojo/IOLoop/resources"))')
    cp "$mojo_resources"/server.crt /etc/pki/tls/certs/openqa.crt
    cp "$mojo_resources"/server.key /etc/pki/tls/private/openqa.key
    cp "$mojo_resources"/server.crt /etc/pki/tls/certs/ca.crt
}

usermod --shell /bin/sh geekotest

# TODO when quay.io/fedora/fedora images starts using Fedora 40, this can be removed
dnf -y upgrade --enablerepo=updates-testing --refresh --advisory=FEDORA-2024-b44061e715

chown -R geekotest /usr/share/openqa /var/lib/openqa && \
	chmod -R a+rw /usr/share/openqa /var/lib/openqa

# temporarily for development purposes just use scheme='http'
schedule_path="/fedora_openqa/src/fedora_openqa/schedule.py"
if [ -f "$schedule_path" ]; then
  sed -i 's/client = OpenQA_Client(openqa_hostname)/client = OpenQA_Client(openqa_hostname, scheme='"'"'http'"'"')/' $schedule_path
fi

# Replace bullet character with unicode since it sometimes interferes with the webpage display
sed -i 's/content: "•";/content: "\\2022";/' /usr/share/openqa/assets/stylesheets/overview.scss

# Get or update any changes to the fedora tests
test_dir='/var/lib/openqa/share/tests/fedora'
if [ ! -d "$test_dir" ]; then
  su geekotest -c "\
    export dist_name=fedora; \
    export dist=fedora; \
    export giturl='https://pagure.io/fedora-qa/os-autoinst-distri-fedora'; \
    export branch=main; \
    export username='openQA fedora'; \
    export needles_separate=0; \
    export needles_giturl='https://pagure.io/fedora-qa/os-autoinst-distri-fedora'; \
    export needles_branch=main;
    /usr/share/openqa/script/fetchneedles; \
    git config --global --add safe.directory /var/lib/openqa/share/tests/fedora"
else
  su geekotest -c "git -C '$test_dir' pull" || true
fi

# Update any changes to the fedora tests scheduler if available
git -C /fedora_openqa pull || true

chown -R geekotest /usr/share/openqa /var/lib/openqa && \
	chmod -R a+rw /usr/share/openqa /var/lib/openqa

add_cert
start_database
start_services

cleanup
