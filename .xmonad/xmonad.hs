import XMonad
import XMonad.Config.Desktop
import XMonad.Util.SpawnOnce

import XMonad.Hooks.EwmhDesktops

import XMonad.ManageHook
import XMonad.Hooks.ManageDocks
import XMonad.Hooks.ManageHelpers

import Data.Monoid
import Data.List
import qualified Data.Map as M

import Data.Bits (shiftL, shiftR)

import qualified XMonad.StackSet as W

import XMonad.Layout.MultiToggle
import XMonad.Layout.MultiToggle.Instances

import Graphics.X11.ExtraTypes.XF86
import qualified XMonad.Util.Brightness as Bright

import XMonad.Util.MyExclusiveScratchpads
import XMonad.Layout.MyBoringWindows  -- required for Scratchpads
import XMonad.Layout.MyMinimize  -- required for Scratchpads

import XMonad.Actions.CopyWindow
import XMonad.Actions.MouseGestures
import XMonad.Actions.CycleWS

myModMask = mod4Mask
altMask   = mod1Mask
myTerminal = "alacritty --config-file ~/.config/alacritty/xmonad.yml"
myFocusFollowsMouse = False
myClickJustFocuses = False


button8Mask, button9Mask :: ButtonMask
button8Mask = button1Mask `shiftR` 1 `shiftL` 8
button9Mask = button1Mask `shiftR` 1 `shiftL` 9

button8, button9 :: Button
button8 = 8
button9 = 9

-- XGrabButton(display, button, modifiers, grab_window, owner_events, event_mask,
--                 pointer_mode, keyboard_mode, confine_to, cursor)
--       Display *display;
--       unsigned int button;
--       unsigned int modifiers;
--       Window grab_window;
--       Bool owner_events;
--       unsigned int event_mask;
--       int pointer_mode, keyboard_mode;
--       Window confine_to;
--       Cursor cursor;


-- display	Specifies the connection to the X server.
-- button	Specifies the pointer button that is to be grabbed or AnyButton.
-- modifiers	Specifies the set of keymasks or AnyModifier. The mask is the bitwise inclusive OR of the valid keymask bits.
-- grab_window	Specifies the grab window.
-- owner_events	Specifies a Boolean value that indicates whether the pointer events are to be reported as usual or reported with respect to the grab window if selected by the event mask.
-- event_mask	Specifies which pointer events are reported to the client. The mask is the bitwise inclusive OR of the valid pointer event mask bits.
-- pointer_mode	Specifies further processing of pointer events. You can pass GrabModeSync or GrabModeAsync.
-- keyboard_mode	Specifies further processing of keyboard events. You can pass GrabModeSync or GrabModeAsync.
-- confine_to	Specifies the window to confine the pointer in or None.
-- cursor	Specifies the cursor that is to be displayed or None.

-- grabButton
--     :: Display
--     -> Button
--     -> ButtonMask
--     -> Window
--     -> Bool
--     -> EventMask
--     -> GrabMode
--     -> GrabMode
--     -> Window
--     -> Cursor
--     -> IO ()

myStartupHook :: X ()
myStartupHook = do
    spawnOnce "$HOME/.config/polybar/launch.sh"
    XConf { display = dpy, theRoot = rootw } <- ask
    -- myKeyCode <- io $ keysymToKeycode dpy xK_Meta_R
    -- io $ grabKey dpy myKeyCode anyModifier rootw True grabModeAsync grabModeAsync
    -- io $ grabButton dpy button8 anyModifier rootw True (buttonPressMask .|. buttonReleaseMask) grabModeAsync grabModeAsync 0 0
    -- io $ grabButton dpy button1 anyModifier rootw True (buttonPressMask .|. buttonReleaseMask) grabModeAsync grabModeAsync 0 0
    -- io $ selectInput dpy rootw (buttonPressMask .|. buttonReleaseMask)
    io (appendFile "/tmp/xmonad_debug" ("startup" ++ "\n"))

myWorkspaces :: [String]
myWorkspaces = ["web", "code", "III", "IV", "im", "VI", "VII",  "VIII", "misc"]

myLauncher :: String
myLauncher = "rofi -modi drun,run -show drun -font \"DejaVu Sans 16\" -show-icons"

appFloat, appCenter, appIgnore, appIM :: [String]
appFloat    = ["Dia", "Gimp", "krita"]
appCenter   = ["feh", "MPlayer", "Zenity", "Pavucontrol", "Org.gnome.Nautilus", "Eog"]
appIgnore   = []
appIM       = ["dingtalk", "wechat.exe"]

myManageHook :: ManageHook
myManageHook = composeAll . concat $
    [ [isFullscreen --> doFullFloat]
    , [className =? a --> doFloat | a <- appFloat]
    , [className =? a --> doCenterFloat  | a <- appCenter]
    , [className =? a --> doIgnore       | a <- appIgnore]
    , [className =? a --> doShift "im"   | a <- appIM]
    ]

myKeys :: XConfig Layout -> M.Map (ButtonMask, KeySym) (X ())
myKeys conf@XConfig {XMonad.modMask = modm} = M.fromList
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
    [ ([], focus)
    , ([U], const swapUp)
    , ([D], const swapDown)
    , ([L], const nextWS)
    , ([R], const prevWS)
    , ([R, D], \_ -> sendMessage NextLayout)
    , ([R, U], \_ -> sendMessage FirstLayout)
    ]

myMouseBindings :: XConfig Layout -> M.Map (ButtonMask, Button) (Window -> X ())
myMouseBindings XConfig {XMonad.modMask = modm} = M.fromList
    -- mod-button1, Set the window to floating mode and move by dragging
    [ ((modm, button1), \w -> focus w >> mouseMoveWindow w)
    -- mod-button2, Raise the window to the top of the stack
    , ((modm, button2), \w -> focus w >> windows W.swapMaster)
    -- mod-button3, Set the window to floating mode and resize by dragging
    , ((modm, button3), \w -> focus w >> mouseResizeWindow w)
    -- bind swap window events to the mouse scroll wheel (button4 and button5)
    , ((modm, button4), const focusUp)
    , ((modm, button5), const focusDown)
    , ((modm .|. shiftMask, button4), const swapUp)
    , ((modm .|. shiftMask, button5), const swapDown)
    , ((modm .|. controlMask, button4), const $ sendMessage Shrink)
    , ((modm .|. controlMask, button5), const $ sendMessage Expand)
    -- 
    , ((0, 9), const $ io (appendFile "/tmp/xmonad_debug" (show modm ++ "\n")))
    -- , ((modm, 0), mouseGesture gestures)
    -- , ((0, 8), const $ return ())
    -- below are not working for some reason
    -- , ((modm .|. button8Mask, button3), \w -> focus w >> mouseResizeWindow w)
    -- , ((modm .|. button8Mask, button1), \w -> focus w >> mouseMoveWindow w)
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

myHandleEventHook :: Event -> X All
myHandleEventHook e = handle e >> return (All True)
-- myHandleEventHook e = return (All True)

handle :: Event -> X ()
handle e@ButtonEvent { ev_window = window, ev_state = modifiers, ev_button = button, ev_time = time } = withDisplay $ \dpy -> do
    io (appendFile "/tmp/xmonad_debug" ("buttonEvent: " ++ show e ++ "\n"))
    io (appendFile "/tmp/xmonad_debug" (show button1Mask ++ "\n"))
    io (appendFile "/tmp/xmonad_debug" (show button2Mask ++ "\n"))
    io (appendFile "/tmp/xmonad_debug" (show button3Mask ++ "\n"))
    io (appendFile "/tmp/xmonad_debug" (show button4Mask ++ "\n"))
    io (appendFile "/tmp/xmonad_debug" (show button5Mask ++ "\n"))
    -- io $ allowEvents dpy replayPointer time
    -- io $ sync dpy False
    -- broadcastMessage e
    -- modifiersClean <- cleanMask modifiers
    -- io (appendFile "/tmp/xmonad_debug" ("Button modifersClean: " ++ show modifiersClean ++ "\n"))
    -- mBindings <- asks $ myMouseBindings . config
    -- userCodeDef () $ whenJust (M.lookup (modifiersClean, button) mBindings) (\f -> f window)
handle e@KeyEvent { ev_state = modifiers, ev_keycode = keycode } = withDisplay $ \dpy -> do
    io (appendFile "/tmp/xmonad_debug" ("keyEvent: " ++ show e ++ "\n"))
    -- keysym <- io $ keycodeToKeysym dpy keycode 0
    -- modifiersClean <- cleanMask modifiers
    -- io (appendFile "/tmp/xmonad_debug" ("Key modifersClean: " ++ show modifiersClean ++ "\n"))
    -- kBindings <- asks $ myKeys . config
    -- userCodeDef () $ whenJust (M.lookup (modifiersClean, keysym) kBindings) id
handle _ = return ()

main = do
    xmonad $ ewmh desktopConfig
        { modMask     = myModMask
        , terminal    = myTerminal
        , borderWidth = 2
        , focusFollowsMouse = myFocusFollowsMouse
        , clickJustFocuses  = myClickJustFocuses
        , workspaces  = myWorkspaces
        , keys = \c -> myKeys c `M.union` keys def c
        , mouseBindings = myMouseBindings
        , startupHook = myStartupHook <+> startupHook desktopConfig
        , manageHook  =  manageDocks <+> myManageHook <+> myScratchpadManageHook <+> manageHook desktopConfig
        , handleEventHook   = myHandleEventHook <+> fullscreenEventHook <+> handleEventHook desktopConfig
        , layoutHook  = myLayoutHook . layoutHook $ desktopConfig
        }
