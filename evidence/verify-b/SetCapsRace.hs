-- Minimal reproducer: two threads call setNumCapabilities n at the same time
-- (GHC 9.10.3, -threaded, started with 2 capabilities), while other threads
-- allocate so that a GC is requested afterwards.  Expected: terminates.
-- Observed: occasionally hangs forever.
module Main (main) where

import Control.Concurrent
import Control.Exception (evaluate)
import Control.Monad
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  let target = case args of (a : _) -> read a; _ -> 8 :: Int
  setNumCapabilities 2 -- what tasty 1.5 does at startup on a 2-processor runner
  gate <- newEmptyMVar
  dones <- replicateM 2 newEmptyMVar
  -- two test-like threads: both raise the capability count, then do some work
  forM_ dones $ \d -> forkIO $ do
    readMVar gate
    cur <- getNumCapabilities
    setNumCapabilities (max target cur)
    vs <- forM [0 .. target - 1] $ \i -> do
      v <- newEmptyMVar
      _ <- forkOn i (evaluate (sum [1 .. 200000 :: Int]) >>= putMVar v)
      pure v
    mapM_ takeMVar vs
    putMVar d ()
  putMVar gate ()
  mapM_ takeMVar dones
  n <- getNumCapabilities
  putStrLn ("ok " ++ show n)
