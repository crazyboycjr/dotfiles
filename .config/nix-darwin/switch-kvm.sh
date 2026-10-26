#!/usr/bin/env bash

usage() {
    echo "$0 [linux|win11]"
    exit 1
}

NODE=pve
VM_LINUX=100
VM_WIN11=105
# the node address and API token stay out of git: ~/.config/pve/kvm.env sets PVE_URL and PVE_TOKEN
. ~/.config/pve/kvm.env
NODE_URL=$PVE_URL
AUTH="Authorization: PVEAPIToken=$PVE_TOKEN"
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
        # attach_usb $VM_LINUX usb1 Filco-Hakua-Keyboard
        attach_usb $VM_LINUX usb1 NiZ-plum-X87-45g
        "$DDC" set --namelike=AW2725Q --feature=ddc --vcp=0x60 --value=$DP1
        # transfer the sound card
        detach_usb $VM_WIN11 usb2
        attach_usb $VM_LINUX usb2 SoundBlasterX4
        ;;
    win11)
        # transfer the keyboard
        detach_usb $VM_LINUX usb1
        # attach_usb $VM_WIN11 usb1 Filco-Hakua-Keyboard
        attach_usb $VM_LINUX usb1 NiZ-plum-X87-45g
        # transfer the mouse
        # https://github.com/marcelhoffs/input-switcher/issues/30#issuecomment-2433513220
        /usr/local/bin/hidapitester --vidpid 046D:B038 --usage 0x0202 --usagePage 0xff43 --open --length 20 --send-output 0x11,0x00,0x0b,0x1e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        "$DDC" set --namelike=AW2725Q --feature=ddc --vcp=0x60 --value=$HDMI2
        # transfer the sound card
        detach_usb $VM_LINUX usb2
        attach_usb $VM_WIN11 usb2 SoundBlasterX4
        ;;
    *)
        usage;;
esac

