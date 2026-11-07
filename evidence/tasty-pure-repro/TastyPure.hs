-- golem-font/test/race/Main.hs with the Font replaced by pure Haskell work:
-- no FFI of golem's at all. Same tasty, same setNumCapabilities, same forkOn.
module Main (main) where

import Control.Concurrent (forkOn, getNumCapabilities, setNumCapabilities)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar, takeMVar)
import Control.Exception (SomeException, evaluate, try)
import Test.Tasty
import Test.Tasty.HUnit

threads :: Int
threads = 8

inParallel :: (Show a) => [IO a] -> IO [Either String a]
inParallel acts = do
  current <- getNumCapabilities
  setNumCapabilities (max threads current)
  gate <- newEmptyMVar
  vars <- traverse (start gate) (zip [0 ..] acts)
  putMVar gate ()
  traverse takeMVar vars
  where
    start gate (i, act) = do
      v <- newEmptyMVar
      _ <- forkOn i (readMVar gate >> try (act >>= \x -> evaluate (length (show x)) >> pure x) >>= putMVar v . either (\e -> Left (show (e :: SomeException))) Right)
      pure v

metrics :: Int -> Maybe (Int, Int, (Int, Int, Int, Int))
metrics g = if g `mod` 97 == 0 then Nothing else Just (g * 3, g * 5, (g, g + 1, g + 2, length (show (g * g))))

glyphsFrom :: Int -> [Int]
glyphsFrom k = [k .. k + 1999]

main :: IO ()
main =
  defaultMain $
    testGroup
      "pure stand-in for the race test"
      [ testCase "one" $ do
          let alone = [map metrics (glyphsFrom k) | k <- [1 .. threads]]
          _ <- evaluate (length (show alone))
          together <- inParallel [pure (concat (replicate 10 (map metrics (glyphsFrom k)))) | k <- [1 .. threads]]
          together @?= [Right (concat (replicate 10 a)) | a <- alone],
        testCase "two" $ do
          let ask k = [(g + 1, metrics g) | g <- glyphsFrom k]
              alone = map ask [1 .. threads]
          _ <- evaluate (length (show alone))
          together <- inParallel [pure (ask k) | k <- [1 .. threads]]
          together @?= map Right alone
      ]
