{- Minimal reproduction: setNumCapabilities while other threads make safe
   foreign calls and allocate. Mirrors golem-plugin-test: tasty raises the
   capabilities at startup, then ConcurrencySpec raises them again (to 8)
   while other tests run. Exits 0 when every round finishes. -}
module Main (main) where

import Control.Concurrent
import Control.Monad
import Foreign.C.Types
import System.Environment

foreign import ccall safe "unistd.h usleep" c_usleep :: CUInt -> IO CInt

worker :: Int -> MVar () -> IO ()
worker n done = do
  forM_ [1 .. n] $ \i -> do
    _ <- c_usleep (fromIntegral (i `mod` 50))
    let xs = [1 .. (i `mod` 2000)] :: [Int]
    when (sum xs < 0) (putStrLn "never")
  putMVar done ()

main :: IO ()
main = do
  [rounds, threads, top] <- map read <$> getArgs
  forM_ [1 .. rounds :: Int] $ \r -> do
    setNumCapabilities 1
    dones <- replicateM threads newEmptyMVar
    forM_ (zip [0 ..] dones) $ \(i, d) -> forkOn i (worker 2000 d)
    -- raise the count while the workers run, as tasty and ConcurrencySpec do
    forM_ [2 .. top] $ \c -> setNumCapabilities c >> yield
    mapM_ takeMVar dones
    when (r `mod` 50 == 0) (putStrLn ("round " <> show r))
  putStrLn "ok"
