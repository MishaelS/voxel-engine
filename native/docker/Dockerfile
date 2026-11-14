# Build environment for the native library (GDExtension) on Linux and
# Windows, used by tools/build.sh (--docker, or a missing library; BUILDING.md).
# Ubuntu 20.04: glibc 2.31, so the Linux .so runs on most distributions from
# 2020 on. Works on an x86_64 and an arm64 host: the host's own g++ plus the
# cross g++ for the other Linux arch, and MinGW-w64 (posix threads) for Windows.
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
RUN set -eux; \
	arch="$(dpkg --print-architecture)"; \
	case "$arch" in \
		amd64) cross="g++-aarch64-linux-gnu" ;; \
		arm64) cross="g++-x86-64-linux-gnu" ;; \
		*) echo "unsupported host arch $arch"; exit 1 ;; \
	esac; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		g++ "$cross" g++-mingw-w64-x86-64 \
		ninja-build python3 python3-pip git ca-certificates; \
	update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix; \
	update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix; \
	pip3 install --no-cache-dir "cmake>=3.28,<4"; \
	apt-get purge -y python3-pip; apt-get autoremove -y; \
	rm -rf /var/lib/apt/lists/* /root/.cache

# Any uid can write HOME (the container runs as the host user).
ENV HOME=/tmp
WORKDIR /src
