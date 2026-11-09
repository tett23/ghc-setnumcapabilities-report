<!--
issue-stoptimer.md の日本語訳（2026-11-10）。投稿するのは英語版で、この訳は
tett23 の確認用。#NNNNN は capability の漏れの issue の番号に置き換える。
-->

題名: `setNumCapabilities` は、I/O マネージャへの通知を実行する間タイマーを止めたままにするため、数秒かそれ以上止まることがある（master では 341ed474 で修正済み。バックポートは？）

## 要約

（再現プログラム、計測ログ、`-Ds` トレース、調査ログは https://github.com/tett23/ghc-setnumcapabilities-report の `evidence/sync-lag/` にある。同じリポジトリに #NNNNN の資料もある。）

見たリリース済みの GHC（9.10.3、9.12.4、9.14.1）のすべてで、`setNumCapabilities`（rts/Schedule.c）は世界を止める前に `stopTimer()` を呼び、最後の I/O マネージャへの通知の後でようやく `startTimer()` を呼ぶ。

```c
    stopTimer();                                                  // Schedule.c:2295 (9.10.3)
    stopAllCapabilities(&cap, task);
    ...
    releaseAllCapabilities(old_n_capabilities, cap,task);
    ...
    rts_evalIO(&cap, ioManagerCapabilitiesChanged_closure, NULL); // :2378
    startTimer();                                                 // :2382
    rts_unlock(cap);
```

（9.12.4 と 9.14.1 は `rts_evalIO` の代わりに `notifyIOManagerCapabilitiesChanged(&cap)` で、同じ順序。ソースを読んだだけで、動かしてはいない。）

この通知は Haskell のコード（`ioManagerCapabilitiesChanged`）を、呼び出し元の capability 上の bound thread として実行する。タイマーが止まっている間は tick がないので `cap->context_switch` は決して立たず、`scheduleHandleYield`（Schedule.c:1252）と `scheduleHandleHeapOverflow`（:1142）は、停止したスレッドを毎回 run queue の「先頭」に戻す。同じ capability に別の実行可能なスレッドがいると、そのスレッドは停止のたびに再実行され、bound の通知スレッドには順番が回らない。`setNumCapabilities` はそのスレッドが終わるまで戻らないので、呼び出し元は止まる。debug ビルドでは数秒（GC の割り込みがときどきこのパターンを崩す）、忙しいスレッドのアロケートが少ない最適化ビルドでは、忙しいスレッドがブロックするまで。

下の再現プログラム（4 つのアロケートするスレッド。メインスレッドが n+1 と n を交互に 50 回 `setNumCapabilities`、`+RTS -N2`）で観測した結果:

| ビルド | RTS オプション | 50 回の呼び出し |
|---|---|---|
| `-O -threaded` | `-N2` | **120 秒たっても終わらない**（6 回中 6 回） |
| `-O -threaded` | `-N2 -C0` | 1 回あたり最大 58 ms（3 回） |
| `-threaded -debug` | `-N2` | 1 回あたり最大 0.1〜5.4 秒。50 回中最大 19 回が 100 ms 超（11 回） |
| `-threaded -debug` | `-N2 -C0` | 最大 3.7 ms（2 回） |
| `-O -threaded`、`stopTimer()`／`startTimer()` の対を外した RTS | `-N2` | 最大 95 ms（3 回） |
| `-threaded -debug`、同じ RTS | `-N2` | 最大 79 ms（3 回） |

同じメインスレッドから同じ負荷のもとで `performGC` を呼ぶと毎回約 1 ms なので、これは `setNumCapabilities` に固有である。

debug ビルドで 2.5 秒かかった呼び出しの `+RTS -Ds` トレースは次の順序を示す。t=55.7 ms に「changing the number of Capabilities from 2 to 3」、55.8 ms までに sync と新しい capability が完了、56.1 ms に「cap 1: created thread 10 / new bound thread (10)」（通知スレッド）、56.4 ms に bound task が、run queue の先頭に unbound のスレッドがいたために capability 1 をワーカーに渡し、そのあとそのワーカーが 300 回を超える「stopped (yielding)」／「stopped (heap overflow)」のたびに自分のスレッドを再実行して 2557 ms に至る。その間、すべての「all threads」ダンプは capability 1 のスレッド 10 を「not blocked」と列挙している。2557.1 ms に「passing capability 1 to bound task」、スレッド 10 が走ってすぐ終わる。

タイマーの停止は #17289（再割り当て中の capability 配列に tick が触る）のためにあった。配列はもう再割り当てされないので、master では 2026-06-12 に 341ed474（「Remove redundant use of stopTimer in setNumCapabilities」。そこでは #27105 の部分的な修正とされている）でこの対が外された。master は動かしていない。表の最後の行は、9.10.3 の `rts/Schedule.c` から同じ 2 行を外してコンパイルし、9.10.3 の RTS アーカイブに差し替えたものである。

これは #NNNNN（同時の `setNumCapabilities` 呼び出しによる capability の漏れ）の調査中に遭遇した。2 つは独立で、#NNNNN の修正はこの挙動を変えない。関係しうるもの: #27105（`stopTimer` は非同期）、#27473（GC の sync の即応性）。

## 再現手順

単体で、依存は `base` だけ。

```haskell
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
```

```sh
ghc-9.10.3 -O -threaded -rtsopts SyncLag.hs -o synclag
./synclag gc 50 4 +RTS -N2        # finishes at once, max_ms about 1.5
./synclag caps 50 4 +RTS -N2      # does not finish (kill it after a minute or two)
./synclag caps 50 4 +RTS -N2 -C0  # finishes, max_ms about 60
```

`-O -threaded` の代わりに `-threaded -debug` にすると、`caps` の実行は終わるが個々の呼び出しが最大で数秒かかる。`+RTS -Ds` は上で述べた飢えた bound thread を示す。

再現プログラム、計測ログ、`-Ds` トレースは https://github.com/tett23/ghc-setnumcapabilities-report にある（`evidence/sync-lag/`）。

## 期待する動作

`setNumCapabilities` は sync が済めば有限の時間で戻るべきで、自分の capability 上のほかのスレッドがたまたまブロックすることに依存すべきではない。`stopTimer()`／`startTimer()` の対を外すと（master と同じ）、上の実行ではすべての呼び出しが 95 ms 以内に完了した。

341ed474 を保守中のリリースブランチにバックポートできれば、リリース済みのコンパイラでもこれは解決する。

## 環境

* 使った GHC のバージョン: 9.10.3（ghcup のバイナリ）。同じコードの順序が `ghc-9.12.4-release` と `ghc-9.14.1-release` にある（読んだだけで、動かしていない）。master（7dedcf135e 以降）にはもう `stopTimer()` はない。

任意:

* OS: macOS 27.0（Darwin 27.0.0）
* アーキテクチャ: aarch64（10 コアの Apple Silicon）
* ビルド: `-O -threaded -rtsopts` と `-threaded -debug -rtsopts`
* C コンパイラ: Apple clang 21.0.0 (clang-2100.3.34.2)（「対を外した」行のために `rts/Schedule.c` を再コンパイルするのに使った）

LLM の利用: RTS のソースの分析、再現プログラムとスクリプトの作成、この報告の下書きに Claude Code (Anthropic) を使った（https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI、P4）。文章と再現プログラムは読んで手直しし、再現プログラムは自分で実行し、責任を持つ。

/label ~"T::bug"
/label ~"needs triage"
<!-- トリアージ担当が ~RTS と優先度を付ける。コメントで ~"backport needed:9.14"（または現在の保守ブランチ）に触れる。 -->
