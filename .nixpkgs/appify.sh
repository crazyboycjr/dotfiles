#!/bin/bash

NIX_PROFILE=/home/cjr/.nix-profile

RDMA_INC_PATH=$NIX_PROFILE/include/rdma
for f in `find $RDMA_INC_PATH`; do
	ln -sf $f /usr/include/rdma
done

IB_INC_PATH=$NIX_PROFILE/include/infiniband
ln -sf "$IB_INC_PATH" /usr/include
