#!/usr/bin/env bash

NODE=pve
VM_LINUX=100
VM_WIN11=105
AUTH="Authorization: PVEAPIToken=root@pam!api=4044ecce-a8fb-4e81-bb75-e859ba69305c"

function detach_usb {
	vmid=$1
	usbid=$2
	curl -k -X PUT -H "$AUTH" \
		--data-urlencode "delete=$usbid" \
		"https://pve:8006/api2/json/nodes/$NODE/qemu/$vmid/config"
}

function attach_usb {
	vmid=$1
	usbid=$2
	dev=$3
	curl -k -X PUT -H "$AUTH" \
		--data-urlencode "$usbid=mapping=$3" \
		"https://pve:8006/api2/json/nodes/$NODE/qemu/$vmid/config"
}

# detach_usb $VM_LINUX usb0
# attach_usb $VM_WIN11 usb0 m590
# detach_usb $VM_WIN11 usb0
# attach_usb $VM_LINUX usb0 m590

# curl -k -X POST -H "$AUTH" \
#     --data-urlencode "delete=usb0" \
#     "https://pve:8006/api2/json/nodes/$NODE/qemu/$VM_LINUX/config"
# 
# curl -k -X POST -H "$AUTH" \
#     --data-urlencode "usb0=mapping=m590" \
#     "https://pve:8006/api2/json/nodes/$NODE/qemu/$VM_LINUX/config"

detach_usb $VM_LINUX usb1
attach_usb $VM_WIN11 usb1 Filco-Hakua-Keyboard
# switch to win11 on DisplayPort-1
ddcutil --model='DELL U2720Q' setvcp 60 0x0f

# sleep 2
# 
# detach_usb $VM_WIN11 usb1
# attach_usb $VM_LINUX usb1 Filco-Hakua-Keyboard
