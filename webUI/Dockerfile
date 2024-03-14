# Note: based on https://build.opensuse.org/package/show/devel:openQA/openQA_container_webUI
FROM quay.io/fedora/fedora
LABEL title="openqa_webui"

RUN dnf install -y openqa openqa-local-db \
	openqa-httpd mod_ssl mod_proxy_html mod_session \
	perl-Mojolicious perl-Mojolicious-Plugin-AssetPack \
	ruby-devel 'rubygem(sass)' fedora-messaging python3-jsonschema wget

# get test scheduler, fedora_openqa, and packages that it needs
RUN dnf install -y fedfind python3-pip && \
	pip install resultsdb_api openqa_client typing_extensions mwclient resultsdb_conventions wikitcms && \
	git clone https://pagure.io/fedora-qa/fedora_openqa.git && \
	git config --global --add safe.directory /fedora_openqa

RUN ln -s /etc/httpd/conf.modules.d/00-base.conf /etc/httpd/conf.modules.d/00-base.load
RUN ln -s /etc/httpd/conf.modules.d/00-ssl.conf /etc/httpd/conf.modules.d/00-ssl.load
RUN cp /etc/httpd/conf.d/openqa-ssl.conf.template /etc/httpd/conf.d/openqa-ssl.conf
RUN cp /etc/httpd/conf.d/openqa.conf.template /etc/httpd/conf.d/openqa.conf
RUN /usr/libexec/httpd-ssl-gencerts

# fix all ownership/permissions
RUN chown -R geekotest /usr/share/openqa /var/lib/openqa && \
	chmod ug+rw /usr/share/openqa /var/lib/openqa && \
	find /usr/share/openqa /var/lib/openqa -type d -exec chmod ug+x {} \;

EXPOSE 80 443
ENTRYPOINT ["/init_openqa_web.sh"]
