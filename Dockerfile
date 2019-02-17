FROM	alpine:latest
LABEL	maintainer="Steven Bass"

RUN	apk --no-cache add	\
		bind	\
		bash	\
		curl	\
		jq

COPY	overlay/ /

RUN	mkdir -p /var/cache/bind /var/log/named /etc/bind/cache	\
	&& chmod 755 /scripts/*	\
	&& chown named:named /var/cache/bind /var/log/named /etc/bind/cache

EXPOSE	53/udp

WORKDIR	/scripts

CMD	["bash", "/scripts/bootstrap.sh"]
