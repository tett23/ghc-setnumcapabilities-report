-- No golem code. Mimics tasty + the golem race test:
--   * tasty: setNumCapabilities nproc at start, then worker threads, and a
--     thread making safe foreign calls (console output, the timer)
--   * the test: setNumCapabilities 8 while those threads run, then 8
--     forkOn threads that allocate (and, mode "unsafe", make unsafe calls).
import Control.Concurrent
import Control.Exception
import Control.Monad
import Foreign.C.Types
import GHC.Conc (getNumProcessors)
import System.Environment

foreign import ccall safe "usleep" c_usleepSafe :: CUInt -> IO CInt

foreign import ccall unsafe "locked_inc" c_lockedInc :: CInt -> IO CInt

work :: Bool -> Int -> IO Int
work useFfi i = do
  xs <- forM [1 .. 3000 :: Int] $ \k -> do
    r <- if useFfi then c_lockedInc (fromIntegral k) else pure (fromIntegral k)
    pure (length (show [fromIntegral r + i .. fromIntegral r + i + 20]))
  evaluate (sum xs)

main :: IO ()
main = do
  [mode, grow] <- getArgs
  let useFfi = mode == "unsafe"
  np <- getNumProcessors
  setNumCapabilities np
  -- background: safe calls and allocation, as tasty's reporter and timeout threads
  _ <- forkIO $ forever (c_usleepSafe 50 >> evaluate (length (show [1 .. 200 :: Int])))
  _ <- forkIO $ forever (threadDelay 100 >> evaluate (length (show [1 .. 200 :: Int])))
  _ <- forkIO $ forever (evaluate (sum [1 .. 2000 :: Int]) >> yield)
  forM_ [1 .. 4 :: Int] $ \_ -> do
    when (grow == "grow") $ do
      c <- getNumCapabilities
      setNumCapabilities (max 8 c)
    gate <- newEmptyMVar
    vars <- forM [0 .. 7] $ \i -> do
      v <- newEmptyMVar
      _ <- forkOn i (readMVar gate >> work useFfi i >>= putMVar v)
      pure v
    putMVar gate ()
    mapM_ takeMVar vars
  putStrLn "OK"
