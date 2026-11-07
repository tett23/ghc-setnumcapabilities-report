{- SyncLag: how long does a stop-the-world operation take while other threads
   allocate?  usage: synclag MODE ITERS WORKERS [+RTS ...]
     MODE  gc    : main calls performGC ITERS times
           caps  : main calls setNumCapabilities alternately n+1 / n, ITERS times
   Workers allocate (a list of up to 3100 Ints per iteration) and never
   call performGC.  Prints the max / mean latency per operation and how many
   operations took more than 100 ms. -}
module Main (main) where

import Control.Concurrent
import Control.Exception (evaluate)
import Control.Monad
import Data.IORef
import GHC.Clock (getMonotonicTimeNSec)
import System.Environment
import System.IO
import System.Mem (performGC)
import Text.Printf (printf)

worker :: IORef Bool -> IO ()
worker stop = loop (0 :: Int)
  where
    loop i = do
      s <- readIORef stop
      unless s $ do
        let xs = [1 .. (i `mod` 3000) + 100] :: [Int]
        _ <- evaluate (sum xs)
        loop (i + 1)

timed :: IO () -> IO Double
timed act = do
  t0 <- getMonotonicTimeNSec
  act
  t1 <- getMonotonicTimeNSec
  pure (fromIntegral (t1 - t0) / 1e6)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  [mode, itersS, workersS] <- getArgs
  let iters = read itersS :: Int
      workers = read workersS :: Int
  stop <- newIORef False
  replicateM_ workers (forkIO (worker stop))
  threadDelay 20000
  n0 <- getNumCapabilities
  lats <- forM [1 .. iters] $ \i -> do
    let target = if odd i then n0 + 1 else n0
    case mode of
      "gc" -> timed performGC
      "caps" -> timed (setNumCapabilities target)
      _ -> error "mode: gc | caps"
  writeIORef stop True
  let mx = maximum lats
      mean = sum lats / fromIntegral (length lats)
      slow = length (filter (> 100) lats)
  printf "mode=%s iters=%d workers=%d caps=%d max_ms=%.1f mean_ms=%.2f over100ms=%d\n" mode iters workers n0 mx mean slow
