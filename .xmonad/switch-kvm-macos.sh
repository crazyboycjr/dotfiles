#!/usr/bin/env bash

DP1=0x0f
HDMI1=0x11
HDMI2=0x12

# switch to macos on HDMI-1
ddcutil --model='AW2725Q' setvcp 60 0x11
# ddcutil --model='PHL 279P1' setvcp 60 0x11
