{- Minimal reproduction: two threads call setNumCapabilities with the same
   larger count at the same time while others allocate. GHC 9.10.3 reads
   n_capabilities before it stops the capabilities, so the second call
   releases only the old ones and keeps the new ones; the next GC that needs
   them waits forever.  Run as: race +RTS -N4 -RTS 8 -}
module Main (main) where

import Control.Concurrent
import Control.Monad
import Data.IORef
import System.Environment

worker :: IORef Int -> MVar () -> IO ()
worker ref done = do
  forM_ [1 .. 400 :: Int] $ \i -> do
    let xs = map show [1 .. (i `mod` 3000)]
    atomicModifyIORef' ref (\a -> (a + length (concat xs), ()))
  putMVar done ()

main :: IO ()
main = do
  [top] <- map read <$> getArgs
  ref <- newIORef 0
  caps <- getNumCapabilities
  dones <- replicateM (2 * caps) newEmptyMVar
  forM_ (zip [0 ..] dones) $ \(i, d) -> forkOn (i `mod` caps) (worker ref d)
  gate <- newEmptyMVar
  setters <- replicateM 2 newEmptyMVar
  forM_ (zip [0 ..] setters) $ \(i, d) -> forkOn i (readMVar gate >> setNumCapabilities top >> putMVar d ())
  putMVar gate ()
  mapM_ takeMVar setters
  more <- replicateM top newEmptyMVar
  forM_ (zip [0 ..] more) $ \(i, d) -> forkOn i (worker ref d)
  mapM_ takeMVar (dones <> more)
  readIORef ref >>= \s -> when (s < 0) (print s)
