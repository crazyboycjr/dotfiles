-- | Zoom on Alt+scroll without letting any wheel notch reach the window under
-- the pointer, while Alt+click and Alt+drag keep working in applications.
--
-- X hands a notch's smooth-scroll motion to the window under the pointer
-- before the emulated button press a passive grab would see, so xmonad holds
-- the pointer from the moment Alt goes down, in synchronous mode: every
-- pointer event stops at xmonad, wheel events zoom, and anything else is
-- replayed to the application as if there were no grab, which also ends the
-- hold. The Alt press itself is replayed at once, so Alt+key shortcuts are
-- untouched. While Alt is down, applications miss hover updates and cannot
-- grab the pointer themselves (a menu opened with Alt+F, for example).
module XMonad.Actions.PicomZoom.AltReplay (altReplayZoom) where

import Data.Bits ((.&.))
import Control.Monad (forM_, when)
import Data.Monoid (All (..))
import XMonad
import XMonad.Actions.PicomZoom
import qualified XMonad.Util.ExtensibleState as XS

newtype AltHeld = AltHeld Bool

instance ExtensionClass AltHeld where
    initialValue = AltHeld False

-- | The keycodes grabAlt grabbed. While one is down the keyboard stays frozen
-- until xmonad replays it, so every one of them must reach altDown.
newtype AltKeys = AltKeys [KeyCode]

instance ExtensionClass AltKeys where
    initialValue = AltKeys []

altReplayZoom :: XConfig l -> XConfig l
altReplayZoom conf = conf
    { startupHook = startupHook conf <+> grabAlt
    , handleEventHook = altReplayHook <+> handleEventHook conf
    }

grabAlt :: X ()
grabAlt = withDisplay $ \dpy -> do
    root <- asks theRoot
    -- An unmapped keysym gives keycode 0, which X reads as AnyKey.
    codes <- io $ filter (/= 0) <$> mapM (keysymToKeycode dpy) [xK_Alt_L, xK_Alt_R]
    forM_ codes $ \code -> io $ grabKey dpy code anyModifier root True grabModeAsync grabModeSync
    XS.put (AltKeys codes)

altDown :: X ()
altDown = withDisplay $ \dpy -> do
    root <- asks theRoot
    st <- io $ grabPointer dpy root False
              (buttonPressMask .|. buttonReleaseMask .|. pointerMotionMask)
              grabModeSync grabModeAsync none none currentTime
    io $ allowEvents dpy replayKeyboard currentTime
    when (st == grabSuccess) $ do
        XS.put (AltHeld True)
        io $ allowEvents dpy syncPointer currentTime

-- | Let the held pointer deliver its next event to xmonad.
nextPointerEvent :: X ()
nextPointerEvent = withDisplay $ \dpy -> io $ allowEvents dpy syncPointer currentTime

-- | Give the current pointer event to the application and stop holding.
replayAndRelease :: X ()
replayAndRelease = withDisplay $ \dpy -> do
    io $ allowEvents dpy replayPointer currentTime
    XS.put (AltHeld False)

-- | xmonad drops every key grab when the keyboard mapping changes, and does not
-- export its re-grab, so the Alt grab comes back through a message to
-- ourselves that is handled after xmonad's own re-grab.
regrabAltAtom :: X Atom
regrabAltAtom = getAtom "_XMONAD_REGRAB_ALT"

altReplayHook :: Event -> X All
altReplayHook KeyEvent { ev_event_type = t, ev_keycode = code } | t == keyPress = do
    AltKeys codes <- XS.get
    if code `elem` codes then altDown >> return (All False) else return (All True)
altReplayHook ButtonEvent { ev_event_type = t, ev_button = b, ev_state = st } = do
    AltHeld held <- XS.get
    if not held then return (All True) else do
        if st .&. mod1Mask /= 0 && b `elem` [button4, button5]
            then do
                when (t == buttonPress) $ zoomBy (if b == button4 then zoomStep else 1 / zoomStep)
                nextPointerEvent
            else replayAndRelease
        return (All False)
altReplayHook MotionEvent {} = do
    AltHeld held <- XS.get
    if not held then return (All True) else withDisplay $ \dpy -> do
        root <- asks theRoot
        (_, _, _, _, _, _, _, st) <- io $ queryPointer dpy root
        if st .&. mod1Mask /= 0 then nextPointerEvent else replayAndRelease
        return (All False)
altReplayHook MappingNotifyEvent {} = withDisplay $ \dpy -> do
    root <- asks theRoot
    atom <- regrabAltAtom
    io $ allocaXEvent $ \ev -> do
        setEventType ev clientMessage
        setClientMessageEvent ev root atom 32 0 currentTime
        sendEvent dpy root False structureNotifyMask ev
    return (All True)
altReplayHook ClientMessageEvent { ev_message_type = mt } = do
    atom <- regrabAltAtom
    when (mt == atom) grabAlt
    return (All True)
altReplayHook _ = return (All True)
