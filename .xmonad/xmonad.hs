import XMonad
import XMonad.Config.Desktop (desktopConfig)
import XMonad.Util.SpawnOnce (spawnOnce)

import XMonad.Hooks.EwmhDesktops (ewmh, fullscreenEventHook)

import XMonad.Hooks.ManageDocks (avoidStruts, manageDocks)
import XMonad.Hooks.ManageHelpers (doCenterFloat, doFullFloat, isFullscreen)

import qualified Data.Map as M
import Data.Monoid (All(..))

import qualified XMonad.StackSet as W

import XMonad.Layout.MultiToggle (Toggle(..), mkToggle, single)
import XMonad.Layout.MultiToggle.Instances (StdTransformers(FULL))

import Graphics.X11.ExtraTypes.XF86
import XMonad.Util.Brightness as Bright

import XMonad.Layout.MyBoringWindows
    (boringWindows, focusDown, focusMaster, focusUp, swapDown, swapUp)  -- required for Scratchpads
import XMonad.Layout.MyMinimize (minimize)   -- required for Scratchpads
import XMonad.Util.MyExclusiveScratchpads
    ( ExclusiveScratchpad(XSP)
    , ExclusiveScratchpads
    , defaultFloating
    , mkXScratchpads
    , scratchpadAction
    , xScratchpadsManageHook
    )
import XMonad.Actions.CycleWS (nextWS, prevWS)
import XMonad.Actions.MouseGestures (Direction2D(D, L, R, U), mouseGesture)

import XMonad.Hooks.RefocusLast (refocusLastLayoutHook)

myModMask = mod4Mask
altMask   = mod1Mask
myTerminal = "alacritty --config-file ~/.config/alacritty/xmonad.yml"
myFocusFollowsMouse = False
myClickJustFocuses = False

myStartupHook :: X ()
myStartupHook = do
    spawnOnce "$HOME/.config/polybar/launch.sh"

myWorkspaces :: [String]
myWorkspaces = ["web", "code", "III", "IV", "im", "VI", "VII",  "VIII", "misc"]

myLauncher :: String
myLauncher = "rofi -modi drun,run -show drun -font \"DejaVu Sans 16\" -show-icons"

appFloat, appCenter, appIgnore, appIM :: [String]
appFloat    = ["Dia", "Gimp", "krita"]
appCenter   = ["feh", "MPlayer", "Zenity", "Pavucontrol", "Org.gnome.Nautilus", "Eog"]
appIgnore   = []
appIM       = ["dingtalk", "wechat.exe"]

-- | Helper to read a property
-- getProp :: Atom -> Window -> X (Maybe [CLong])
getProp a w = withDisplay $ \dpy -> io $ getWindowProperty32 dpy a w

-- | Check if window is DIALOG window
checkDialog :: Query Bool
checkDialog = ask >>= \w -> liftX $ do
    a      <- getAtom "_NET_WM_WINDOW_TYPE"
    dialog <- getAtom "_NET_WM_WINDOW_TYPE_DIALOG"
    mbr    <- getProp a w
    case mbr of
        Just [r] -> return $ fromIntegral r == dialog
        _        -> return False

myManageHook' :: ManageHook
myManageHook' = (composeAll . concat)
    [ [isFullscreen --> doFullFloat]
    , [ checkDialog --> doCenterFloat ]
    , [ className =? a --> doFloat       | a <- appFloat ]
    , [ className =? a --> doCenterFloat | a <- appCenter ]
    , [ className =? a --> doIgnore      | a <- appIgnore ]
    , [ className =? a --> doShift "im"  | a <- appIM ]
    ]

myKeys :: XConfig Layout -> M.Map (ButtonMask, KeySym) (X ())
myKeys conf@XConfig { modMask = modm } = M.fromList
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
    , ((modm .|. shiftMask, xK_j), swapDown)
    , ((modm .|. shiftMask, xK_k), swapUp)

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
    , ((0, 0x1008FF16), return ())

    -- Play/pause.
    , ((0, 0x1008FF14), return ())

    -- Audio next.
    , ((0, 0x1008FF17), return ())

    -- Brightness.
    , ((0, xF86XK_MonBrightnessUp), Bright.increase)
    , ((0, xF86XK_MonBrightnessDown), Bright.decrease)
    ]

gestures :: M.Map [Direction2D] (Window -> X ())
gestures = M.fromList
    [ ([]    , focus)
    , ([U], const $ spawn "xfce4-screenshooter --region --clipboard")
    , ([D]   , \w -> focus w >> kill)
    , ([L]   , const nextWS)
    , ([R]   , const prevWS)
    , ([R, D], const $ sendMessage NextLayout)
    , ([R, U], const $ sendMessage FirstLayout)
    ]

myMouseBindings :: XConfig Layout -> M.Map (ButtonMask, Button) (Window -> X ())
myMouseBindings XConfig { modMask = modm } = M.fromList
    [ ((modm, button2)                , mouseGesture gestures)
    , ((modm, button4)                , const focusUp)
    , ((modm, button5)                , const focusDown)
    , ((modm .|. shiftMask, button4)  , const swapUp)
    , ((modm .|. shiftMask, button5)  , const swapDown)
    , ((modm .|. controlMask, button4), const $ sendMessage Shrink)
    , ((modm .|. controlMask, button5), const $ sendMessage Expand)
    ]

exclusiveScratchpads :: ExclusiveScratchpads
exclusiveScratchpads = mkXScratchpads
    [ ("terminal-0", "alacritty --title scratch-0", title =? "scratch-0")
    , ("terminal-1", "alacritty --title scratch-1", title =? "scratch-1")
    , ("terminal-2", "alacritty --title scratch-2", title =? "scratch-2")
    ]
    defaultFloating

regularScratchpads :: ExclusiveScratchpads
regularScratchpads =
    [XSP "term" "urxvt -name scratchpad" (appName =? "scratchpad") defaultFloating []]

scratchpads :: ExclusiveScratchpads
scratchpads = exclusiveScratchpads ++ regularScratchpads

myScratchpadManageHook :: ManageHook
myScratchpadManageHook = xScratchpadsManageHook scratchpads

myManageHook :: ManageHook
myManageHook = myManageHook' <+> manageDocks <+> myScratchpadManageHook

myHandleEventHook :: Event -> X All
myHandleEventHook e = handle e >> return (All True)
-- myHandleEventHook e = return (All True)

-- extend this later to handle XEvent
handle :: Event -> X ()
handle = const $ return ()

myLayoutHook =
    minimize . boringWindows . avoidStruts . mkToggle (single FULL) . refocusLastLayoutHook

main = do
    xmonad $ ewmh desktopConfig
        { modMask           = myModMask
        , terminal          = myTerminal
        , borderWidth       = 2
        , focusFollowsMouse = myFocusFollowsMouse
        , clickJustFocuses  = myClickJustFocuses
        , workspaces        = myWorkspaces
        , keys              = \c -> myKeys c `M.union` keys def c
        , mouseBindings     = \c -> myMouseBindings c `M.union` mouseBindings def c
        , startupHook       = myStartupHook <+> startupHook desktopConfig
        , manageHook        = myManageHook <+> manageHook desktopConfig
        , handleEventHook   = myHandleEventHook <+> fullscreenEventHook <+> handleEventHook desktopConfig
        , layoutHook        = myLayoutHook . layoutHook $ desktopConfig
        }
