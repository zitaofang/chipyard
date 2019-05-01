FROM gradescope/auto-builds:ubuntu-16.04

RUN apt-get update && \
    apt-get install -y git autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev libusb-1.0-0-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev device-tree-compiler pkg-config libexpat-dev

ENV RISCV /home/root
