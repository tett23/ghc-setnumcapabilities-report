-- No FFI of our own: setNumCapabilities 1 -> 8, then 8 forkOn threads that allocate.
-- Mode "grow": raise caps at run time like the golem tests.
-- Mode "fixed": do not change caps (run with +RTS -N8).
import Control.Concurrent
import Control.Exception
import Control.Monad
import System.Environment

work :: Int -> Int
work i = sum [length (show x) | x <- [i * 1000000 .. i * 1000000 + 300000 :: Int]]

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
      _ <- forkOn i (readMVar gate >> evaluate (work i) >>= putMVar v)
      pure v
    putMVar gate ()
    mapM_ takeMVar vars
  putStrLn "OK"
