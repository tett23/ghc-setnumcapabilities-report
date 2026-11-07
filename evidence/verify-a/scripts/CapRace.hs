{- CapRace: concurrent setNumCapabilities calls.
   Modes (first arg):
     conc    : M threads call setNumCapabilities concurrently with *increasing*
               distinct targets (base+1 .. base+M), per round base grows so that
               n_capabilities really grows (moreCapabilities path).
     same    : like conc, but all M threads use the same target (base+M).
     serial  : like conc, but every setNumCapabilities is wrapped in a global MVar.
     dec     : first (serially) raise to top, then M threads concurrently call
               decreasing targets; never any increase concurrently.
     noop    : all calls use the current enabled count (start with -N8, target 8).
     mixed   : one increase and one decrease concurrently.
   Second arg: rounds. Third arg: M (setter threads). Fourth: worker threads.
   After each round: performGC (this is where the hang happens) and print.
-}
module Main (main) where

import Control.Concurrent
import Control.Exception (evaluate)
import Control.Monad
import Data.IORef
import System.Environment
import System.IO
import System.Mem (performGC)

-- allocation-heavy worker that also calls performGC
worker :: IORef Bool -> IO ()
worker stop = loop (0 :: Int)
  where
    loop i = do
      s <- readIORef stop
      unless s $ do
        let xs = [1 .. (i `mod` 3000) + 100] :: [Int]
        _ <- evaluate (sum xs)
        when (i `mod` 400 == 0) performGC
        loop (i + 1)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  let (mode, rounds, m, w) = case args of
        [a, b, c, d] -> (a, read b, read c, read d)
        _ -> error "usage: CapRace MODE ROUNDS M WORKERS"
  stop <- newIORef False
  replicateM_ w (forkIO (worker stop))
  gate <- newMVar ()
  forM_ [0 .. rounds - 1] $ \r -> do
    n0 <- getNumCapabilities
    let base = case mode of
          "dec" -> 1 + (r + 1) * m -- top of this round
          _ -> n0
    dones <- replicateM m newEmptyMVar
    start <- newEmptyMVar
    case mode of
      "dec" -> do
        -- raise serially first (no concurrency), then decrease concurrently
        setNumCapabilities base
        forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          setNumCapabilities (base - i)
          putMVar d ()
      "noop" -> forM_ dones $ \d -> forkIO $ do
          readMVar start
          setNumCapabilities n0
          putMVar d ()
      "same" -> forM_ dones $ \d -> forkIO $ do
          readMVar start
          setNumCapabilities (base + m)
          putMVar d ()
      "serial" -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          withMVar gate $ \_ -> setNumCapabilities (base + i)
          putMVar d ()
      "mixed" -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          -- odd threads increase, even threads decrease to 1
          setNumCapabilities (if odd i then base + i else 1)
          putMVar d ()
      _ -> forM_ (zip [1 .. m] dones) $ \(i, d) -> forkIO $ do
          readMVar start
          setNumCapabilities (base + i)
          putMVar d ()
    putMVar start ()
    mapM_ takeMVar dones
    n1 <- getNumCapabilities
    putStrLn ("round " ++ show r ++ " caps " ++ show n0 ++ " -> " ++ show n1 ++ " ; GC...")
    performGC
    putStrLn ("round " ++ show r ++ " GC done")
  writeIORef stop True
  putStrLn "ok"
