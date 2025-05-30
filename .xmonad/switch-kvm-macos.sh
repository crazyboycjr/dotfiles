#!/usr/bin/env bash

# switch to macos on HDMI-1
ddcutil --model='AW2725Q' setvcp 60 0x11
