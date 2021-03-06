FROM alpine:latest as rootfs-stage

# environment
ARG TAG=groovy
ENV REL=${TAG}

# install packages
RUN set -xe && \
	apk add --no-cache \
		bash \
		curl \
		tzdata \
		xz

# grab base tarball
RUN set -xe && \
	mkdir /root-out && \
	if [ "$(arch)" = "x86_64" ]; then \
		ARCH="amd64"; \
	elif [ "$(arch)" = "armv7l" ]; then \
		ARCH="armhf"; \
	elif [ "$(arch)" = "aarch64" ]; then \
		ARCH="arm64"; \
	else \
		exit 1; \
	fi && \
	curl -o \
		/rootfs.tar.gz -L \
		"https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz" && \
	tar xf \
		/rootfs.tar.gz -C \
		/root-out

# Runtime stage
FROM scratch

COPY --from=rootfs-stage /root-out/ /

# set version for s6 overlay
ARG OVERLAY_VERSION="v2.2.0.3"

# set environment variables
ENV HOME="/root" \
	LANGUAGE="en_US.UTF-8" \
	LANG="en_US.UTF-8" \
	TERM="xterm" \
	DEBIAN_FRONTEND="noninteractive"

RUN set -xe && \
	echo "**** Ripped from Ubuntu Docker Logic ****" && \
	echo '#!/bin/sh' \
		>/usr/sbin/policy-rc.d && \
	echo 'exit 101' \
		>>/usr/sbin/policy-rc.d && \
	chmod +x \
		/usr/sbin/policy-rc.d && \
	dpkg-divert --local --rename --add /sbin/initctl && \
	cp -a \
		/usr/sbin/policy-rc.d \
		/sbin/initctl && \
	sed -i \
		's/^exit.*/exit 0/' \
		/sbin/initctl && \
	echo 'force-unsafe-io' \
		>/etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
	echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
		>/etc/apt/apt.conf.d/docker-clean && \
	echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
		>>/etc/apt/apt.conf.d/docker-clean && \
	echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
		>>/etc/apt/apt.conf.d/docker-clean && \
	echo 'Acquire::Languages "none";' \
		>/etc/apt/apt.conf.d/docker-no-languages && \
	echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
		>/etc/apt/apt.conf.d/docker-gzip-indexes && \
	echo 'Apt::AutoRemove::SuggestsImportant "false";' \
		>/etc/apt/apt.conf.d/docker-autoremove-suggests && \
	mkdir -p /run/systemd && \
	echo 'docker' \
		>/run/systemd/container && \
	echo "**** install apt-utils and locales ****" && \
	apt-get update && \
	apt-get install -y \
		apt-utils \
		locales && \
	echo "**** install packages ****" && \
	apt-get install -y \
		curl \
		gnupg \
		patch \
		tzdata && \
	echo "**** install s6-overlay ****" && \
	if [ "$(arch)" = "x86_64" ]; then \
		OVERLAY_ARCH="amd64"; \
	elif echo "$(arch)" | grep -E -q "armv7l|aarch64"; then \
		OVERLAY_ARCH="arm"; \
	fi && \
	curl -o \
		/tmp/s6-overlay-installer -L \
		"https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}-installer" && \
	chmod +x /tmp/s6-overlay-installer && \
	/tmp/s6-overlay-installer "/" && \
	echo "**** patch s6-overlay ****" && \
	curl -o \
		/tmp/init-stage2.patch -L \
		"https://raw.githubusercontent.com/hydazz/docker-utils/main/patches/init-stage2.patch" && \
	echo "**** generate locale ****" && \
	locale-gen en_US.UTF-8 && \
	echo "**** create abc user and make our folders ****" && \
	useradd -u 911 -U -d /config -s /bin/false abc && \
	usermod -G users abc && \
	mkdir -p \
		/app \
		/config \
		/defaults && \
	mv /usr/bin/with-contenv /usr/bin/with-contenvb && \
	patch -u /etc/s6/init/init-stage2 -i /tmp/init-stage2.patch && \
	echo "**** cleanup ****" && \
	apt-get remove -y patch && \
	apt-get autoremove && \
	apt-get clean && \
	rm -rf \
		/tmp/* \
		/var/lib/apt/lists/* \
		/var/tmp/*

# add local files
COPY root/ /

ENTRYPOINT ["/init"]
