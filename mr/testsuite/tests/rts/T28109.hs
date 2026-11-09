-- Concurrent setNumCapabilities calls must not leak capabilities (#28109).
--
-- Before the fix, setNumCapabilities read n_capabilities before stopping the
-- world and released only that many capabilities afterwards.  When several
-- threads raised the capability count at the same time, the later callers
-- acquired more capabilities than they released, and the next GC waited for
-- the leaked ones forever.
--
-- Each round, four threads call setNumCapabilities at once with distinct,
-- increasing targets; then the main thread forces a GC, which is where the
-- leak shows up.  With the bug this hangs in nearly every run (19 of 20 on a
-- 10-core machine, 37 of 40 on a 2-CPU one); the watchdog turns the hang
-- into a failure.  The program prints nothing on success.
import Control.Concurrent
import Control.Monad
import Foreign.C.Types
import System.Mem (performGC)

-- Starts an OS thread outside the RTS that exits the process after the
-- given number of seconds (see T28109_c.c).
foreign import ccall unsafe "start_watchdog" c_startWatchdog :: CInt -> IO ()

rounds, setters :: Int
rounds = 6
setters = 4

main :: IO ()
main = do
  c_startWatchdog 60
  forM_ [1 .. rounds] $ \_ -> do
    base <- getNumCapabilities
    start <- newEmptyMVar
    dones <- forM [1 .. setters] $ \i -> do
      done <- newEmptyMVar
      _ <- forkIO $ do
        readMVar start
        setNumCapabilities (base + i)
        putMVar done ()
      pure done
    putMVar start ()
    mapM_ takeMVar dones
    performGC
