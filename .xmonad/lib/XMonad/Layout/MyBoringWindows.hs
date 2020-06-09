{-# LANGUAGE TypeSynonymInstances, MultiParamTypeClasses, DeriveDataTypeable #-}
{-# LANGUAGE PatternGuards, FlexibleContexts, FlexibleInstances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  XMonad.Layout.BoringWindows
-- Copyright   :  (c) 2008  David Roundy <droundy@darcs.net>
-- License     :  BSD3-style (see LICENSE)
--
-- Maintainer  :  Adam Vogt <vogt.adam@gmail.com>
-- Stability   :  unstable
-- Portability :  unportable
--
-- BoringWindows is an extension to allow windows to be marked boring
--
-----------------------------------------------------------------------------

module XMonad.Layout.MyBoringWindows (
                                   -- * Usage
                                   -- $usage
                                   boringWindows, boringAuto,
                                   markBoring, clearBoring,
                                   focusUp, focusDown, focusMaster,
                                   swapUp, swapDown,

                                   UpdateBoring(UpdateBoring),
                                   BoringMessage(Replace,Merge),
                                   BoringWindows()

                                   -- * Tips
                                   -- ** variant of 'Full'
                                   -- $simplest
                                  ) where

import XMonad.Layout.LayoutModifier(ModifiedLayout(..),
                                    LayoutModifier(handleMessOrMaybeModifyIt, redoLayout))
import XMonad(Typeable, LayoutClass, Message, X, fromMessage,
              sendMessage, windows, withFocused, Window)
import Control.Applicative((<$>))
import Data.List((\\), union)
import Data.Maybe(fromMaybe, listToMaybe, maybeToList)
import qualified Data.Map as M
import qualified XMonad.StackSet as W

-- $usage
-- You can use this module with the following in your
-- @~\/.xmonad\/xmonad.hs@:
--
-- > import XMonad.Layout.BoringWindows
--
-- Then edit your @layoutHook@ by adding the layout modifier:
--
-- > myLayout = boringWindows (Full ||| etc..)
-- > main = xmonad def { layoutHook = myLayout }
--
-- Then to your keybindings, add:
--
-- > , ((modm, xK_j), focusUp)
-- > , ((modm, xK_k), focusDown)
-- > , ((modm, xK_m), focusMaster)
--
-- For more detailed instructions on editing the layoutHook see:
--
-- "XMonad.Doc.Extending#Editing_the_layout_hook"


data BoringMessage = FocusUp | FocusDown | FocusMaster | SwapUp | SwapDown | IsBoring Window | ClearBoring
                     | Replace String [Window]
                     | Merge String [Window]
                     deriving ( Read, Show, Typeable )

instance Message BoringMessage

-- | UpdateBoring is sent before attempting to view another boring window, so
-- that layouts have a chance to mark boring windows.
data UpdateBoring = UpdateBoring
    deriving (Typeable)
instance Message UpdateBoring

markBoring, clearBoring, focusUp, focusDown, focusMaster :: X ()
markBoring = withFocused (sendMessage . IsBoring)
clearBoring = sendMessage ClearBoring
focusUp = sendMessage UpdateBoring >> sendMessage FocusUp
focusDown = sendMessage UpdateBoring >> sendMessage FocusDown
focusMaster = sendMessage UpdateBoring >> sendMessage FocusMaster
swapUp = sendMessage UpdateBoring >> sendMessage SwapUp
swapDown = sendMessage UpdateBoring >> sendMessage SwapDown

data BoringWindows a = BoringWindows
    { namedBoring :: M.Map String [a] -- ^ store borings with a specific source
    , chosenBoring :: [a]             -- ^ user-chosen borings
    , hiddenBoring :: Maybe [a]       -- ^ maybe mark hidden windows
    } deriving (Show,Read,Typeable)

boringWindows :: (LayoutClass l a, Eq a) => l a -> ModifiedLayout BoringWindows l a
boringWindows = ModifiedLayout (BoringWindows M.empty [] Nothing)

-- | Mark windows that are not given rectangles as boring
boringAuto :: (LayoutClass l a, Eq a) => l a -> ModifiedLayout BoringWindows l a
boringAuto = ModifiedLayout (BoringWindows M.empty [] (Just []))

instance LayoutModifier BoringWindows Window where
    redoLayout (b@BoringWindows { hiddenBoring = bs }) _r mst arrs = do
        let bs' = W.integrate' mst \\ map fst arrs
        return (arrs, Just $ b { hiddenBoring = const bs' <$> bs } )

    handleMessOrMaybeModifyIt bst@(BoringWindows nbs cbs lbs) m
        | Just (Replace k ws) <- fromMessage m
        , maybe True (ws/=) (M.lookup k nbs) =
            let nnb = if null ws then M.delete k nbs
                          else M.insert k ws nbs
            in rjl bst { namedBoring = nnb }
        | Just (Merge k ws) <- fromMessage m
        , maybe True (not . null . (ws \\)) (M.lookup k nbs) =
            rjl bst { namedBoring = M.insertWith union k ws nbs }
        | Just (IsBoring w) <- fromMessage m , w `notElem` cbs =
            rjl bst { chosenBoring = w:cbs }
        | Just ClearBoring <- fromMessage m, not (null cbs) =
            rjl bst { namedBoring = M.empty, chosenBoring = []}
        | Just FocusUp <- fromMessage m =
                            do windows $ W.modify' $ skipBoring W.focusUp'
                               return Nothing
        | Just FocusDown <- fromMessage m =
                            do windows $ W.modify' $ skipBoring W.focusDown'
                               return Nothing
        | Just FocusMaster <- fromMessage m =
                            do windows $ W.modify'
                                            $ skipBoring W.focusDown' -- wiggle focus to make sure
                                            . skipBoring W.focusUp'   -- no boring window gets the focus
                                            . focusMaster'
                               return Nothing
        | Just SwapUp <- fromMessage m =
                            do windows $ W.modify' $ swapUpSkipBoring swapUp'
                               return Nothing
        | Just SwapDown <- fromMessage m =
                            do windows $ W.modify' $ swapDownSkipBoring swapDown'
                               return Nothing
        -- iterate `f` for n times to find the first valid Stack order
        where skipUntil :: (W.Stack a -> Bool) -> (W.Stack a -> W.Stack a) -> W.Stack a -> W.Stack a
              -- skipUntil pred f st = fromMaybe st $ listToMaybe $ filter pred $ take (length $ W.integrate st) $ iterate f st
              skipUntil pred f st = fromMaybe st $ listToMaybe $ filter pred $ nonLazyIterate (length $ W.integrate st) f st
              skipBoring f st = skipUntil ((`notElem` W.focus st:bs) . W.focus) f st
              swapUpSkipBoring f st = skipUntil (not . boringSwapUp) f st
              swapDownSkipBoring f st = skipUntil (not . boringSwapDown) f st
              bs = concat $ cbs:maybeToList lbs ++ M.elems nbs
              rjl = return . Just . Left
              boringSwapUp (W.Stack t ls rs) = case rs of
                                                    r:rs -> r `elem` bs
                                                    [] -> False
              boringSwapDown (W.Stack t ls rs) = case ls of
                                                    l:ls -> l `elem` bs
                                                    [] -> False
              nonLazyIterate 0 f st = [st]
              nonLazyIterate n f st = tail $ reverse $ foldl (\all@(a:acc) _ -> f a:all) [st] [1..n]
    handleMessOrMaybeModifyIt _ _ = return Nothing

-- | Variant of 'focusMaster' that works on a
-- 'Stack' rather than an entire 'StackSet'.
focusMaster' :: W.Stack a -> W.Stack a
focusMaster' c@(W.Stack _ [] _) = c
focusMaster' (W.Stack t ls rs) = W.Stack x [] (xs ++ t : rs) where (x:xs) = reverse ls
-- | /O(s)/. Set focus to the master window.

-- | helper functions that grabbed from XMonad.StackSet source code
swapUp' :: W.Stack a -> W.Stack a
swapUp' (W.Stack t (l:ls) rs) = W.Stack t ls (l:rs)
swapUp' (W.Stack t []     rs) = W.Stack t (reverse rs) []
swapDown' = (reverseStack . swapUp' . reverseStack)

-- | reverse a stack: up becomes down and down becomes up.
reverseStack :: W.Stack a -> W.Stack a
reverseStack (W.Stack t ls rs) = W.Stack t rs ls

{- $simplest

An alternative to 'Full' is "XMonad.Layout.Simplest".  Less windows are
ignored by 'focusUp' and 'focusDown'. This may be helpful when you want windows
to be uninteresting by some other layout modifier (ex.
"XMonad.Layout.Minimize")

-}
