# Note: based on https://build.opensuse.org/package/show/devel:openQA/openQA_container_webUI
FROM quay.io/fedora/fedora
LABEL title="openqa_webui"

RUN dnf install -y openqa

# Pull request #5463 "assets-via-npm" requires that we now get these packages locally
RUN dnf install -y nodejs && \
	npm install -g npm@10.5.0 && \
	cd /usr/share/openqa/ && \
	npm init -y && \
	npm install --save anser@^2.1.1 bootstrap@^4.6.1 chosen-js@^1.8.7 codemirror@^5.58.2 d3@^4.13.0 \
	dagre-d3@^0.6.4 datatables@^1.10.18 datatables.net-bs4@^1.13.8 fork-awesome@^1.2.0 jquery@^3.7.1 \
	jquery-ujs@^1.2.3 shepherd.js@^11.2.0 timeago@^1.6.7

# do not force fixes as the specific version are required and will break otherwise
RUN npm audit fix || true

RUN dnf install -y openqa-local-db \
	openqa-httpd mod_ssl mod_proxy_html mod_session \
	perl-Mojolicious perl-Mojolicious-Plugin-AssetPack \
	ruby-devel 'rubygem(sass)' fedora-messaging python3-jsonschema wget

# get packages needed by fedora_openqa
RUN dnf install -y fedfind python3-pip && \
	pip install resultsdb_api openqa_client typing_extensions mwclient resultsdb_conventions wikitcms

RUN ln -s /etc/httpd/conf.modules.d/00-base.conf /etc/httpd/conf.modules.d/00-base.load
RUN ln -s /etc/httpd/conf.modules.d/00-ssl.conf /etc/httpd/conf.modules.d/00-ssl.load
RUN /usr/libexec/httpd-ssl-gencerts

# fix all ownership/permissions
RUN chown -R geekotest /usr/share/openqa /var/lib/openqa && \
	chmod ug+rw /usr/share/openqa /var/lib/openqa && \
	find /usr/share/openqa /var/lib/openqa -type d -exec chmod ug+x {} \;

EXPOSE 80 443
ENTRYPOINT ["/init_openqa_web.sh"]
