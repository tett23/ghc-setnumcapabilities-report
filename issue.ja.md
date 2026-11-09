<!--
issue.md の日本語訳（2026-11-10）。英語の issue.md は #28109 として投稿済み。この訳は
tett23 の確認用。コード、コマンド、ログの引用は原文のまま。
-->

題名: `setNumCapabilities` は、世界を止める前に別の `setNumCapabilities` が配列を増やすと capability を漏らし、次の GC が止まる

## 要約

（以下で参照するもの、すなわち再現プログラム、実行ごとのログ、止まったプロセスの gdb/lldb ダンプと `-Ds` トレース、調査ログ、testsuite のテストと検証つきの修正案は、すべて https://github.com/tett23/ghc-setnumcapabilities-report にある。README に読む順の案内がある。）

`setNumCapabilities`（rts/Schedule.c）は、世界を止める「前」に `n_capabilities` と `enabled_capabilities` を読み、世界を止めた「後」にその値を使う。

```c
uint32_t old_n_capabilities = n_capabilities;          // Schedule.c:2272 (9.10.3), :2306 (9.14.1), :2281 (master)

if (new_n_capabilities == enabled_capabilities) {      // :2274 / :2308 / :2283
    return;
}
...
cap = rts_lock();
...
stopAllCapabilities(&cap, task);                        // :2297 / :2331 / :2300
...
releaseAllCapabilities(old_n_capabilities, cap,task);  // :2371 / :2405 / :2376
```

`stopAllCapabilities` → `acquireAllCapabilities` は `getNumCapabilities()` 個、つまり「世界を止めた時点」に存在する数の capability を取る（9.10.3 の Schedule.c:1543）。最後の `releaseAllCapabilities` は `old_n_capabilities` 個、つまり関数に「入った時点」に存在した数しか返さない。

したがって不具合の条件は、**ある呼び出しが入口で読んだ `n_capabilities` の値が、その呼び出しの `stopAllCapabilities` が戻った時点の `n_capabilities` の値より小さいこと**である。これは、その 2 点の間に別の `setNumCapabilities` が capability の配列を増やせば必ず起きる。窓は広い。2 番目の呼び出し側は、最初の呼び出し側が全部の capability を持っている間、たいてい `rts_lock()` か `requestSync()` でブロックして過ごすからである。2 番目の呼び出しの向きは関係ない。結果として増やすことになっても、減らすことになっても、何もしないことになっても漏れる。capability `old_n_capabilities .. n_capabilities-1` は、`setNumCapabilities` からすでに戻っていて自分が持ち主だと知らない Task を `running_task` が指したまま残る。

debug RTS で観測した 2 つの interleaving を示す（A と B は 2 つの Haskell スレッドで、それぞれ別の Task にいる）。

*増やす／増やす。* `n_capabilities == enabled_capabilities == 2`。A が `setNumCapabilities 3` を、B が `setNumCapabilities 4` を呼ぶ。

1. 両方が `old_n_capabilities = 2` を読み、両方が `new_n == enabled` の判定を通る。
2. A が sync を取り、`moreCapabilities(2, 3)` で `n_capabilities = enabled_capabilities = 3` にし、cap 0..1 を返す。
3. B の `stopAllCapabilities` は、ここで **3** 個全部の capability を取る。
4. B は 3 → 4 に増やし（`moreCapabilities(3, 4)`）、`releaseAllCapabilities(old_n_capabilities = 2, ...)` で cap 0..1 だけを返す。cap 2 は `running_task == B` のまま永久に残る。

（まさにこの実行の `+RTS -Ds` トレース: ある task が「changing the number of Capabilities from 2 to 4」、次に「grabbing all the capabilities (0/3) … (2/3)」、次に「giving up capability 0」／「freeing capability 0」と記録し、cap 2 については何も出ない。次の GC は「asking for cap 2 to be idle」と記録して終わらない。）

*増やす／減らす。* `n_capabilities == 6`。B が `setNumCapabilities 7` に入り `old_n_capabilities = 6` を読む。B が sync を取る前に、ほかの呼び出しが配列を 9 に増やす。B の呼び出しはここで「減らす」呼び出し（9 → 7）になり、cap 7..8 を無効にしてから cap 0..5 だけを返す。cap 6..8 は `running_task == B` のまま残り、cap 6 は有効なので永久に使用中に見える。

次の stop-the-world 操作まで誰も気づかず、そこで GC が漏れた capability をどう分類するかに応じて、2 か所のどちらかで止まる。

* 漏れた capability が idle と扱われる場合（`enabled_capabilities > n_gc_threads` の並列 GC では普通の場合で、逐次 GC `-qg` では常に）、GC のリーダーはそれに対して `waitForCapability` を呼ぶ（Schedule.c:1789、または `-qg` では `acquireAllCapabilities` 経由の :1554）。自分をその capability の `returning_tasks` に並べ、誰も signal しない条件変数で眠る。プロセスは CPU を使わない。
* 漏れた capability が GC の参加者と扱われる場合、リーダーは `waitForGcThreads`（rts/sm/GC.c:1496、:1527 の 1 ms の `timedWaitCondition`）でループし、1 ミリ秒ごとにその capability をつつきながら、決して入ってこない GC スレッドを待つ。その capability で Task が動くことは二度とないからである。プロセスはほとんど CPU を使わない。

ほかの Task もやがて、保留中の sync の後ろで `yieldCapability` か `waitForReturnCapability` でブロックする。その後の `setNumCapabilities` や `forkProcess` も、同じ理由で `acquireAllCapabilities` の中で止まる。

止まったプロセスを gdb で見ると、まさにこのとおりになっている。止まった増やす／増やすのプロセス（`n_capabilities = 4`）: cap 0..1 は `running_task == A`（A は GC のリーダーで、`scheduleDoGC` → `waitForCapability`、Schedule.c:1789 にいる）、cap 2 は `running_task == B`、A は cap 2 の `returning_tasks` に並び、B の OS スレッドは生きていて `yieldCapability` → `waitForWorkerCapability` で `task->cap` が cap 0 を指したまま止まっている。止まった増やす／減らすのプロセス（`n_capabilities = 9`、`enabled_capabilities = 7`）: cap 0..5 は `running_task == A`（GC のリーダーで、`waitForGcThreads`、GC.c:1527 にいる）、cap 6..8 は `running_task == B`、`pending_sync->type == SYNC_GC_PAR`、`idle_cap[6]` は false、B は `waitForWorkerCapability` で止まっている。

コードは `ghc-9.10.3-release`、`ghc-9.12.4-release`、`ghc-9.14.1-release`、`master`（7dedcf135e、2026-10-17）で同じである。master の `setNumCapabilities` の違いは、`stopTimer()/startTimer()` の対が外れたこと、コメント、I/O マネージャへの通知の呼び出しだけである。再現プログラムを動かしたのは 9.10.3 だけである。

遭遇した経緯: tasty 1.5.4（`Test.Tasty.Parallel.runInParallel`）は起動時に `getNumCapabilities < nthreads` なら `setNumCapabilities nthreads` を呼び（上流では UnkindPartition/tasty#485 で取り消されたが未リリース）、さらに私たちのテストスイートのテストケースが複数のテストスレッドから同時に `setNumCapabilities 8` を呼んでいた。GitHub Actions の `ubuntu-24.04` と `ubuntu-24.04-arm` ランナー（それぞれ 2 vCPU）で、テストバイナリはジョブの約 2%（直近約 400 のうち 8）で止まり、毎回、別のスレッドも同じことをしているかもしれない状況で `setNumCapabilities` を呼ぶテストの中だった。10 コアの macOS ではその構成では一度も止まらなかったが、下の単体の再現プログラムはそこでもほぼ毎回止まる。

回避策: 2 つのスレッドが同時に `setNumCapabilities` の中にいられないようにする（`MVar` で呼び出しを直列化する）か、capability の数をコマンドライン（`-N`、`-with-rtsopts=-N`）で一度だけ設定して `setNumCapabilities` をまったく呼ばない。

関係しうるチケット。どれもこの interleaving は書いていない: #8209（古い `setNumCapabilities` の競合、7.8 で修正）、#14707（`setNumCapabilities` の後にスレッドが `gcWorkerThread` で固まる）、#18808（`setnumcapabilities001` での `setNumCapabilities` と `scheduleDoGC` の TSAN の競合）、#22989（`setnumcapabilities001` の断続的なタイムアウト。あのテストは `setNumCapabilities` を呼ぶスレッドが 1 つなので、おそらく別の原因）、#27460／#27473（この停止が通る `returning_tasks` と `pending_sync` のプロトコル）、#20144（2021 年に修正された AArch64/Darwin の GC 入口のデッドロック。`setNumCapabilities` は関係しない）。`setNumCapabilities` のこの部分に触れる merge request も見つからなかった。最近の変更は `MAX_N_CAPS` のアサーション（!13692）と `stopTimer()` の除去（2026 年 6 月）だけである。

## 再現手順

単体で、依存は `base` だけ。`W` 個のワーカースレッドがアロケートし、400 回ごとに `performGC` を呼ぶ。ラウンドごとに `M` 個のスレッドが同時に `setNumCapabilities` を呼び、各ラウンドの後でメインスレッドが `performGC` を呼ぶ。モードで呼び出しのパターンを選び、対照実験を同じバイナリで走らせられるようにしてある。

```haskell
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
```

```sh
ghc-9.10.3 -O1 -threaded -rtsopts CapRace.hs -o caprace
# 3 rounds, 4 concurrent setters per round (1->5, 5->9, 9->13), 4 workers
for i in $(seq 1 100); do timeout 10 ./caprace conc 3 4 4 +RTS -N1 || echo "run $i: exit $?"; done
```

成功した実行は約 30 ms 後に `ok` を出力する。止まった実行は何も出力しないか `round 0 GC done` まで出力し、kill されるまで CPU を使わずに居座る（`timeout` は終了コード 124 を報告する）。

結果（GHC 9.10.3、`-O1 -threaded -rtsopts`。「停止」= タイムアウト後も生きていて CPU を使っていない。少数の「遅い」実行は生きていて CPU を使っており、この不具合ではない）:

| モード | RTS | setter の動作 | 10 コア macOS (aarch64) | 2 CPU Linux コンテナ (aarch64) |
|---|---|---|---|---|
| `conc 3 4 4` | `-N1` | ラウンドごとに 4 つが同時に増やす。目標は別々 | **198 / 200 停止** | **163 / 200 停止** |
| `conc 1 14 4` | `-N2` | 14 個が同時に 2 → 16 へ増やす | **197 / 200 停止** | – |
| `conc 3 4 4` | `-N1 -qg` | 同上、逐次 GC | **96 / 100 停止** | **66 / 100 停止** |
| `same 3 4 4` | `-N1` | 4 つが同時に「同じ」目標を呼ぶ | **34 / 100 停止** | **35 / 100 停止** |
| `mixed 3 4 4` | `-N1` | 増やすと減らすを同時に | **68 / 100 停止** | **23 / 100 停止** |
| `serial 3 4 4` | `-N1` | `conc` と同じ目標だが呼び出しを `MVar` で直列化 | 0 / 200 停止 | 0 / 200 停止 |
| `dec 3 4 4` | `-N1` | 直列に上げてから、同時に「減らす」だけ | 0 / 200 停止 | 0 / 200 停止 |
| `noop 3 4 4` | `-N8` | すべての呼び出しが何もしない (8 → 8) | 0 / 200 停止 | 0 / 200 停止 |

3 つの対照は機構と一致する。直列化した呼び出しは止まらず、配列を増やせない同時呼び出しは止まらず、何もしない呼び出しは止まらない。`-fno-omit-yields` でビルドしても変わらない（`conc` モードで 30 / 30 停止）。`-debug` RTS でも同じ率で止まる。

漏れとは無関係だが同じ実行で見えるもの: アロケートするワーカースレッドがあると、「直列化した」`setNumCapabilities` の呼び出しの一部が CPU を使いながら数秒から数分かかる（10 コアの機械で `serial` の 200 回中 84 回が 4 秒のタイムアウトを超えた）。これは別に追った。`setNumCapabilities` は sync の前に `stopTimer()` を呼び、`rts_evalIO(ioManagerCapabilitiesChanged_closure)` の後でようやく `startTimer()` を呼ぶ（9.10.3 の Schedule.c:2295、:2378、:2382。9.12.4 と 9.14.1 も同じ順序）。タイマーの tick がないと、`scheduleHandleYield` は yield したスレッドを毎回 run queue の「先頭」に戻すので、IO マネージャへの通知を実行する bound thread は同じ capability 上の忙しいスレッド 1 つに飢えさせられうる。`+RTS -Ds` では、ワーカースレッドが 300 回の停止のあと再実行され続ける間、そのスレッドが 2.5 秒間 runnable のままになっている。`+RTS -C0` でこの遅れは消え、`stopTimer()`／`startTimer()` の対を外しても消える。master では 341ed474（「Remove redundant use of stopTimer in setNumCapabilities」、2026-06-12）ですでに外れている。これは漏れとは別の問題で、上の修正は不要である。遅い実行がこの不具合と取り違えられないように、また 341ed474 はバックポートの価値があるかもしれないので、ここで触れておく。

機構を見るには、`-debug` でビルドして `+RTS -N1 -Ds` で実行する。ある task が「changing the number of Capabilities from N to M」、次に `K > N` で「grabbing all the capabilities (0/K) … (K-1/K)」と記録し、そのあと cap `0..N-1` だけを返す。次の GC は「asking for cap N to be idle」と記録して完了しない。止まったプロセスに gdb を付けて `n_capabilities`、`enabled_capabilities`、`*pending_sync`、各 `i` について `capabilities[i]->running_task`／`->returning_tasks_hd` を表示すると、capability `old_n .. n_capabilities-1` の持ち主が、スレッドが `waitForWorkerCapability` で止まっている Task であることがわかる。

再現プログラム、ループのスクリプト、両方の機械での実行ごとの結果、止まったプロセスの gdb/lldb のバックトレースと `-Ds` トレースは https://github.com/tett23/ghc-setnumcapabilities-report にある（`evidence/verify-a/`、`evidence/verify-b/`。修正とその検証は `mr/` と `evidence/rts-fix-check/`）。

## 期待する動作

同時の `setNumCapabilities` 呼び出しは安全であるべきである。この関数はすでに `requestSync`／`stopAllCapabilities` を通って一度に 1 つしか走らないようになっており、`setNumCapabilities` のドキュメントは呼び出し側に直列化を求めていない。上のプログラムは、どの実行でもどのモードでも 0 で終了すべきである。実際には、ある呼び出しが capability の配列を増やしている間に別の呼び出しが `stopAllCapabilities` へ向かっていると、必ず 2 番目の呼び出しが capability を漏らし、次の GC が永久に止まる。

修正は、`stopAllCapabilities` が戻った「後」に `n_capabilities`／`enabled_capabilities` を読み（そこで `new_n_capabilities == enabled_capabilities` の判定をやり直し、早期に返す前に取ったものを返す）、`releaseAllCapabilities` に常に `acquireAllCapabilities` が取った数を渡すようにすることになる。歓迎されるなら、testsuite のテストつきの MR を用意できる。

## 環境

* 使った GHC のバージョン: 9.10.3（`ghc-9.10.3-release`、ghcup のバイナリ）。該当のコードは 9.12.4、9.14.1、master（7dedcf135e、2026-10-17）で変わっていない。再現プログラムはそれらでは動かしていない。

任意:

* OS: macOS 27.0（Darwin 27.0.0、10 コアの Apple Silicon）。2 CPU の Docker コンテナの Debian GNU/Linux 13 (trixie) aarch64（Linux 6.8）。元の症状については GitHub Actions の `ubuntu-24.04`（x86-64）と `ubuntu-24.04-arm` ランナー、それぞれ 2 vCPU
* アーキテクチャ: aarch64（macOS、Linux コンテナ、arm の CI ランナー）と x86-64（CI ランナー）
* ビルド: `-O1 -threaded -rtsopts`。`-Ds` トレースと gdb のためには `-debug` も
* C コンパイラ: macOS では Apple clang 21.0.0 (clang-2100.3.34.2)。コンテナでは gcc (Debian 14.2.0-19) 14.2.0
* 下流の引き金: tasty 1.5.4（`Test.Tasty.Parallel` がスレッド数が capability 数を超えると `setNumCapabilities` を呼ぶ）と、複数のスレッドから `setNumCapabilities 8` を呼ぶアプリケーションのコード。

LLM の利用: RTS のソースの分析、再現プログラムとデバッグ用スクリプトの作成、この報告の下書きに Claude Code (Anthropic) を使った（https://gitlab.haskell.org/ghc/ghc/-/wikis/contributing/AI、P4）。文章と再現プログラムは読んで手直しし、再現プログラムは自分で実行し、責任を持つ。

/label ~"T::bug"
/label ~"needs triage"
<!-- トリアージ担当が ~RTS ~concurrency と優先度を付ける。ラベルを付けられないならコメントで提案する。 -->
