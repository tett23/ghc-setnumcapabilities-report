{- Minimal reproduction attempt: one setNumCapabilities call that adds
   capabilities while other threads allocate and make safe foreign calls,
   with more capabilities than processors afterwards (idle GC caps).
   Run as: grow +RTS -N4 -RTS 8   (on a 4-CPU machine) -}
module Main (main) where

import Control.Concurrent
import Control.Monad
import Data.IORef
import Foreign.C.Types
import System.Environment

foreign import ccall safe "unistd.h usleep" c_usleep :: CUInt -> IO CInt

worker :: IORef Int -> Int -> MVar () -> IO ()
worker ref n done = do
  forM_ [1 .. n] $ \i -> do
    when (i `mod` 7 == 0) (void (c_usleep 20))
    let xs = map show [1 .. (i `mod` 3000)]
    atomicModifyIORef' ref (\a -> (a + length (concat xs), ()))
  putMVar done ()

main :: IO ()
main = do
  [top] <- map read <$> getArgs
  ref <- newIORef 0
  caps <- getNumCapabilities
  dones <- replicateM (2 * top) newEmptyMVar
  forM_ (zip [0 ..] dones) $ \(i, d) -> forkOn (i `mod` caps) (worker ref 400 d)
  threadDelay 20000
  setNumCapabilities top
  -- more workers on the new capabilities, as ConcurrencySpec's forkOn does
  more <- replicateM top newEmptyMVar
  forM_ (zip [0 ..] more) $ \(i, d) -> forkOn i (worker ref 400 d)
  mapM_ takeMVar (dones <> more)
  readIORef ref >>= \s -> when (s < 0) (print s)
