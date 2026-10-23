-- | Desktop zoom through picom's @_PICOM_ZOOM@ root window property (the zoom
-- branch of crazyboycjr/picom). The property holds the target zoom in 16.16
-- fixed point; picom eases toward it and keeps the point under the pointer
-- still. Wheel bindings live in "XMonad.Actions.PicomZoom.SuperHold" and
-- "XMonad.Actions.PicomZoom.AltReplay".
module XMonad.Actions.PicomZoom (zoomBy, zoomStep, spawnUnzoomed) where

import XMonad

-- | Zoom factor of one wheel notch.
zoomStep :: Double
zoomStep = 1.2

-- | Multiply the target zoom by @f@, clamped to 1x..16x.
zoomBy :: Double -> X ()
zoomBy f = do
    current <- getZoom
    let target = max 1 (min 16 (fromIntegral current / 65536 * f)) :: Double
    setZoom (round (target * 65536))

-- | Run a shell command with the zoom at 1x, and zoom back in once it exits.
-- Screenshot tools select in desktop coordinates but read the screen, which is
-- magnified while zoomed.
spawnUnzoomed :: String -> X ()
spawnUnzoomed cmd = do
    zoom <- getZoom
    if zoom <= 65536
        then spawn cmd
        else do
            setZoom 65536
            -- picom eases out in about 0.3 s
            spawn $ "sleep 0.4; " ++ cmd
                ++ "; xprop -root -f _PICOM_ZOOM 32c -set _PICOM_ZOOM " ++ show zoom

-- | The target zoom in 16.16 fixed point, 65536 when the property is unset.
getZoom :: X Integer
getZoom = withDisplay $ \dpy -> do
    root <- asks theRoot
    atom <- getAtom "_PICOM_ZOOM"
    prop <- io $ getWindowProperty32 dpy atom root
    return $ case prop of
        Just [v] -> fromIntegral v
        _        -> 65536

setZoom :: Integer -> X ()
setZoom v = withDisplay $ \dpy -> do
    root <- asks theRoot
    atom <- getAtom "_PICOM_ZOOM"
    io $ changeProperty32 dpy root atom cARDINAL propModeReplace [fromIntegral v]
