#!/usr/bin/env bash

usage() {
    echo "$0 [linux|win11]"
    exit 1
}

NODE=pve
NODE_URL=192.168.4.60
VM_LINUX=100
VM_WIN11=105
AUTH="Authorization: PVEAPIToken=root@pam!api=4044ecce-a8fb-4e81-bb75-e859ba69305c"
DDC="/Applications/Nix Apps/BetterDisplay.app/Contents/MacOS/BetterDisplay"

function detach_usb {
    vmid=$1
    usbid=$2
    curl -k -X PUT -H "$AUTH" \
        --data-urlencode "delete=$usbid" \
        "https://$NODE_URL:8006/api2/json/nodes/$NODE/qemu/$vmid/config"
}

function attach_usb {
    vmid=$1
    usbid=$2
    dev=$3
    curl -k -X PUT -H "$AUTH" \
        --data-urlencode "$usbid=mapping=$3" \
        "https://$NODE_URL:8006/api2/json/nodes/$NODE/qemu/$vmid/config"
}

DP1='0x0f' # win11
HDMI1='0x11' # macos
HDMI2='0x12' # linux

[[ $# -ne 1 ]] && usage
target=$1

case $target in
    linux)
        # transfer the keyboard
        detach_usb $VM_WIN11 usb1
        attach_usb $VM_LINUX usb1 Filco-Hakua-Keyboard
        "$DDC" set --namelike=AW2725Q --feature=ddc --vcp=0x60 --value=$HDMI2
        # transfer the sound card
        detach_usb $VM_WIN11 usb2
        attach_usb $VM_LINUX usb2 SoundBlasterX4
        ;;
    win11)
        # transfer the keyboard
        detach_usb $VM_LINUX usb1
        attach_usb $VM_WIN11 usb1 Filco-Hakua-Keyboard
        "$DDC" set --namelike=AW2725Q --feature=ddc --vcp=0x60 --value=$DP1
        # transfer the sound card
        detach_usb $VM_LINUX usb2
        attach_usb $VM_WIN11 usb2 SoundBlasterX4
        ;;
    *)
        usage;;
esac

