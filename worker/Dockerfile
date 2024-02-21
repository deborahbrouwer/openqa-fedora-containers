FROM quay.io/fedora/fedora
LABEL title="openqa_worker"

RUN dnf install -y openqa openqa-worker python3-jsonschema \
    perl-REST-Client procps-ng os-autoinst tunctl iproute

# fix all ownership/permissions
RUN chown -R _openqa-worker /usr/share/openqa /var/lib/openqa && \
	chmod ug+rw /usr/share/openqa /var/lib/openqa && \
	find /usr/share/openqa /var/lib/openqa -type d -exec chmod ug+x {} \;

EXPOSE 80 443

ENTRYPOINT ["/init_openqa_worker.sh"]
