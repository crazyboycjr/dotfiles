-- | Zoom on Super+Alt+scroll without letting any wheel notch reach the window
-- under the pointer.
--
-- A passive grab on the wheel buttons fires on the emulated button press,
-- after X has already handed the notch's smooth-scroll motion to the window
-- under the pointer. So xmonad holds the pointer from the moment Super goes
-- down. Applications never get Super+mouse anyway, since xmonad owns those
-- bindings; while Super is down they only miss hover updates.
module XMonad.Actions.PicomZoom.SuperHold (superHoldZoom) where

import qualified Data.Map as M
import Control.Monad (when)
import Data.Monoid (All (..))
import XMonad
import XMonad.Actions.PicomZoom
import qualified XMonad.Util.ExtensibleState as XS

newtype PointerHeld = PointerHeld Bool

instance ExtensionClass PointerHeld where
    initialValue = PointerHeld False

superHoldZoom :: XConfig l -> XConfig l
superHoldZoom conf = conf
    { keys = \c -> M.fromList holdKeys <> keys conf c
    , mouseBindings = \c -> M.fromList zoomButtons <> mouseBindings conf c
    , handleEventHook = handleEventHook conf <+> releaseOnSuperUp
    }
  where
    holdKeys = [((m, k), holdPointer) | m <- [0, mod1Mask], k <- [xK_Super_L, xK_Super_R]]
    zoomButtons =
        [ ((mod4Mask .|. mod1Mask, button4), const $ zoomBy zoomStep)
        , ((mod4Mask .|. mod1Mask, button5), const $ zoomBy (1 / zoomStep))
        ]

holdPointer :: X ()
holdPointer = withDisplay $ \dpy -> do
    root <- asks theRoot
    st <- io $ grabPointer dpy root False (buttonPressMask .|. buttonReleaseMask)
                           grabModeAsync grabModeAsync none none currentTime
    when (st == grabSuccess) $ XS.put (PointerHeld True)

releaseOnSuperUp :: Event -> X All
releaseOnSuperUp KeyEvent { ev_event_type = t, ev_keycode = code } | t == keyRelease = do
    sym <- withDisplay $ \dpy -> io $ keycodeToKeysym dpy code 0
    PointerHeld held <- XS.get
    when (held && sym `elem` [xK_Super_L, xK_Super_R]) $ do
        withDisplay $ \dpy -> io $ ungrabPointer dpy currentTime
        XS.put (PointerHeld False)
    return (All True)
releaseOnSuperUp _ = return (All True)
