# -----------------------------------------------------------------------------
# Dockerfile for 'NodeNomicon'
#
# Kaleb - 2022-08-06
# -----------------------------------------------------------------------------
FROM debian:11

# ---- Docker image info
MAINTAINER Kaleb
LABEL com.github.nodenomicon="NodeNomicon Docker"
LABEL version="0.1.2.3"
LABEL datetime="2022-08-06T16:00:00Z"
LABEL author="Dex0r & Kaleb @ OpenBASH"
LABEL description="Distributed multi-cloud NMAP scanner by OpenBASH."


# ---- Config & args
ARG NMAP_VERSION=nmap-7.92


# ---- Docker image setup
SHELL ["/bin/bash", "-c"]

WORKDIR /nodenomicon

# Copy nodenomicon source files
ADD nodenomicon/src/nodenomicon /nodenomicon

# Install general dependencies
RUN apt update -y ;\
	apt install ca-certificates curl jq nano mc openssh-client python3 python3-lxml rsync screen ssh tor -y --no-install-recommends ;\
# Install nmap dependencies
	apt install bzip2 openssl libssl-dev libssh2-1-dev libssh2-1 gcc g++ make cmake libpcap-dev -y --no-install-recommends ;\
# Setup TOR
	sed -r -i 's/#ControlPort 9051/ControlPort 9051/g' /etc/tor/torrc ;\
	sed -r -i 's/#CookieAuthentication 1/CookieAuthentication 0/g' /etc/tor/torrc ;\
	/etc/init.d/tor restart ;\
# Install NMAP
	mkdir /nmap_install ;\
	cd /nmap_install ;\
	curl https://nmap.org/dist/$NMAP_VERSION.tar.bz2 -O ;\
	bzip2 -cd $NMAP_VERSION.tar.bz2 | tar xvf - ;\
	cd $NMAP_VERSION ;\
	./configure ;\
	make ;\
	make install ;\
# Setup file permissions
	chmod +x /nodenomicon/nodenomicon.sh ;\
	chmod +x /nodenomicon/nodenomicon_ow.sh ;\
	chmod +x /nodenomicon/nodenomicon_sw.sh ;\
	chmod +x /nodenomicon/external/nMap_Merger/nMapMerge.py ;\
	chmod +x /nodenomicon/nm.sh ;\
	chmod +x /nodenomicon/nm_drivers/nm_digitalocean.sh ;\
	chmod +x /nodenomicon/nm_drivers/nm_linode.sh ;\
	chmod +x /nodenomicon/nm_drivers/nm_vultr.sh ;\
	chmod +x /nodenomicon/payloads/nodenomicon_node_setup.sh ;\
# Clean trash
	rm -rf /nmap_install ;\
	rm -rf /var/lib/apt/lists/* ;\
# Create output directory & config pool default directory (to be used with a external volume)
	mkdir -p /nodenomicon/work ;\
	mkdir -p /etc/nodenomicon


# ---- Docker image entry point
ENTRYPOINT ["/nodenomicon/nodenomicon.sh"]
CMD ["--help"]
