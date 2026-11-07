-- Like Pure.hs, but each thread also makes many short unsafe FFI calls
-- that take a shared pthread mutex (as golem_font.c does).
import Control.Concurrent
import Control.Exception
import Control.Monad
import Foreign.C.Types
import System.Environment

foreign import ccall unsafe "locked_inc" c_lockedInc :: CInt -> IO CInt

work :: Int -> IO Int
work i = do
  xs <- forM [1 .. 20000 :: Int] $ \k -> do
    r <- c_lockedInc (fromIntegral k)
    pure (length (show (fromIntegral r + i)))
  evaluate (sum xs)

main :: IO ()
main = do
  [mode, reps] <- getArgs
  forM_ [1 .. read reps :: Int] $ \_ -> do
    when (mode == "grow") $ do
      c <- getNumCapabilities
      setNumCapabilities (max 8 c)
    gate <- newEmptyMVar
    vars <- forM [0 .. 7] $ \i -> do
      v <- newEmptyMVar
      _ <- forkOn i (readMVar gate >> work i >>= putMVar v)
      pure v
    putMVar gate ()
    mapM_ takeMVar vars
  putStrLn "OK"
