import XMonad
import XMonad.Config.Desktop
import XMonad.Util.SpawnOnce

import XMonad.Hooks.EwmhDesktops

import XMonad.ManageHook
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers

import Data.List
import qualified Data.Map as M

import qualified XMonad.StackSet as W

import XMonad.Layout.MultiToggle
import XMonad.Layout.MultiToggle.Instances

import Graphics.X11.ExtraTypes.XF86
import qualified XMonad.Util.Brightness as Bright

import XMonad.Util.MyExclusiveScratchpads
import XMonad.Layout.MyBoringWindows  -- required for Scratchpads
import XMonad.Layout.Minimize  -- required for Scratchpads

import XMonad.Actions.CopyWindow

myModMask = mod4Mask
altMask   = mod1Mask
myTerminal = "alacritty --config-file ~/.config/alacritty/xmonad.yml"

myFocusFollowsMouse = False
myClickJustFocuses = False

myStartupHook = do
    spawnOnce "$HOME/.config/polybar/launch.sh"

myWorkspaces = ["web", "code", "III", "IV", "im", "VI", "VII",  "VIII", "misc"]

myLauncher = "rofi -modi drun,run -show drun -font \"DejaVu Sans 16\" -show-icons"

appFloat    = ["Dia", "Gimp", "krita"]
appCenter   = ["feh", "MPlayer", "Zenity", "Pavucontrol", "Org.gnome.Nautilus", "Eog"]
appIgnore   = ["Peek"]

appWeb  = ["firefox", "Google-chrome"]
appCode = ["Code", "Gvim"]
appIM   = ["dingtalk", "TelegramDesktop", "wechat.exe"]
appDoc  = ["Wps", "Wpp", "okular", "krita", "Zeal"]
appEnt  = [ "teeworlds"
          , "netease-cloud-music"
          , "Steam"
          ]
appMisc = ["VirtualBox"]

myManageHook = composeAll . concat $
    [ [isFullscreen --> doFullFloat]
    , [className =? a --> doFloat | a <- appFloat]
    , [className =? a --> doCenterFloat  | a <- appCenter]
    , [className =? a --> doIgnore       | a <- appIgnore]
    , [className =? a --> doShift "web"  | a <- appWeb]
    , [className =? a --> doShift "code" | a <- appCode]
    , [className =? a --> doShift "im"   | a <- appIM]
    , [className =? a --> idHook         | a <- appDoc]
    , [className =? a --> doShift "VII"  | a <- appEnt]
    , [className =? a --> doShift "misc" | a <- appMisc]
    , [(isPrefixOf "Minecraft") <$> className --> doShift "ent"]
    ]

myKeys conf@(XConfig {XMonad.modMask = modm}) = M.fromList $
    -- Spawn the launcher using command specified by myLauncher.
    [ ((modm, xK_p), spawn myLauncher)

    , ((modm, xK_f), sendMessage $ Toggle FULL)

    -- Scratchpad
    , ((0, xK_F1), scratchpadAction scratchpads "terminal-0")
    , ((0, xK_F3), scratchpadAction scratchpads "terminal-1")
    , ((0, xK_F4), scratchpadAction scratchpads "terminal-2")

    -- Overloaded by boringWindows to skip boring windows
    , ((modm, xK_Tab), focusDown)
    , ((modm .|. shiftMask, xK_Tab), focusUp)
    , ((modm, xK_j), focusDown)
    , ((modm, xK_k), focusUp)
    , ((modm, xK_m), focusMaster)
    , ((modm .|. shiftMask, xK_k), swapUp)
    , ((modm .|. shiftMask, xK_j), swapDown)

    -- Screenshot
    , ((0, xK_Print), spawn "xfce4-screenshooter")
    , ((shiftMask, xK_Print), spawn "xfce4-screenshooter --region --save $PICTURES")
    , ((altMask, xK_Print), spawn "xfce4-screenshooter --window --save $PICTURES")
    , ((controlMask, xK_Print), spawn "xfce4-screenshooter --fullscreen --clipboard ")
    , ((shiftMask .|. controlMask, xK_Print), spawn "xfce4-screenshooter --region --clipboard")
    , ((altMask .|. controlMask, xK_Print), spawn "xfce4-screenshooter --window --clipboard")

    -- Switch workspace
    -- , ((0, xK_F1), windows $ W.greedyView (XMonad.workspaces conf !! 0))
    -- , ((0, xK_F3), windows $ W.greedyView (XMonad.workspaces conf !! 1))
    -- , ((0, xK_F4), windows $ W.greedyView (XMonad.workspaces conf !! 2))

    -- Mute, increase and decrease volume.
    , ((0, xF86XK_AudioMute), spawn "amixer -q set Master toggle")
    , ((0, xF86XK_AudioLowerVolume), spawn "amixer -q set Master 5%-")
    , ((0, xF86XK_AudioRaiseVolume), spawn "amixer -q set Master 5%+")

    -- Audio previous.
    , ((0, 0x1008FF16), spawn "")

    -- Play/pause.
    , ((0, 0x1008FF14), spawn "")

    -- Audio next.
    , ((0, 0x1008FF17), spawn "")

    -- Brightness.
    , ((0, xF86XK_MonBrightnessUp), Bright.increase)
    , ((0, xF86XK_MonBrightnessDown), Bright.decrease)
    ]

myLayoutHook = minimize . boringWindows . avoidStruts

exclusiveScratchpads = mkXScratchpads
    [ ("terminal-0", "alacritty --title scratch-0", title =? "scratch-0")
    , ("terminal-1", "alacritty --title scratch-1", title =? "scratch-1")
    , ("terminal-2", "alacritty --title scratch-2", title =? "scratch-2")
    ] defaultFloating

regularScratchpads = [ XSP "term" "urxvt -name scratchpad" (appName =? "scratchpad") defaultFloating [] ]

scratchpads = exclusiveScratchpads ++ regularScratchpads

myScratchpadManageHook = xScratchpadsManageHook scratchpads

main = do
    xmonad $ ewmh desktopConfig
        { modMask     = myModMask
        , terminal    = myTerminal
        , focusFollowsMouse = myFocusFollowsMouse
        , clickJustFocuses  = myClickJustFocuses
        , workspaces  = myWorkspaces
        , keys = \c -> myKeys c `M.union` keys XMonad.def c
        , startupHook = myStartupHook <+> startupHook desktopConfig
        , manageHook  =  manageDocks <+> myManageHook <+> myScratchpadManageHook <+> manageHook desktopConfig
        , handleEventHook   = fullscreenEventHook <+> handleEventHook desktopConfig
        , layoutHook  = myLayoutHook . layoutHook $ desktopConfig
        }
