-- | Desktop zoom through picom's @_PICOM_ZOOM@ root window property (the zoom
-- branch of crazyboycjr/picom). The property holds the target zoom in 16.16
-- fixed point; picom eases toward it and keeps the point under the pointer
-- still. Wheel bindings live in "XMonad.Actions.PicomZoom.SuperHold" and
-- "XMonad.Actions.PicomZoom.AltReplay".
module XMonad.Actions.PicomZoom (zoomBy, zoomStep) where

import XMonad

-- | Zoom factor of one wheel notch.
zoomStep :: Double
zoomStep = 1.2

-- | Multiply the target zoom by @f@, clamped to 1x..16x.
zoomBy :: Double -> X ()
zoomBy f = withDisplay $ \dpy -> do
    root <- asks theRoot
    atom <- getAtom "_PICOM_ZOOM"
    prop <- io $ getWindowProperty32 dpy atom root
    let current = case prop of
            Just [v] -> fromIntegral v / 65536
            _        -> 1
        target = max 1 (min 16 (current * f)) :: Double
    io $ changeProperty32 dpy root atom cARDINAL propModeReplace [round (target * 65536)]
