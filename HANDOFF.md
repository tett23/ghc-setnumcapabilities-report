# 引き継ぎ：GHC の setNumCapabilities の競合の調査と報告

2026-10-17 に Golem（tett23/golem）のセッションで調べた内容を、このフォルダーで調査と報告を続けるセッションに引き継ぐ。
このファイルを最初に読み、続けて下の「ファイルの地図」の順に読む。

## 目的

GHC の RTS の不具合を上流（gitlab.haskell.org/ghc/ghc）に報告する。
issue を先に出し、修正も出すなら issue を参照する MR を後から出す（GHC の規約。`maintainer-checklist.md`）。
投稿、アカウントの作成、MR の push は tett23 が自分で行う。
このセッションの仕事は、原因の確定、issue と MR の下書きの仕上げ、残った疑問の調査である。

## わかっていること

### 症状

- Golem のテスト（GHC 9.10.3、tasty 1.5.4、`-threaded`）が、CPU の少ない Linux（GitHub Actions の ubuntu-24.04 の x86-64 と arm、Docker の 2 CPU）で、ときどき永久に止まった。
- 10 コアの macOS では、テストの形のままでは止まらなかった（最小の再現なら macOS でも止まる）。
- 止まったとき、すべての OS スレッドが RTS の中で待っていた（GC の主は `scheduleDoGC` → `waitForCapability`、ほかは `yieldCapability` か `resumeThread` → `waitForReturnCapability`）。

### 原因（確認済み）

`rts/Schedule.c` の `setNumCapabilities`（ghc-9.10.3-release。9.12.4、9.14、master 7dedcf135 でも同じ順序）：

- `old_n_capabilities = n_capabilities` を読む（2272 行）のと、`new_n_capabilities == enabled_capabilities` の判定（2274 行）が、`stopAllCapabilities`（2297 行）より前にある。
- 同期の後の `acquireAllCapabilities` は、その時点のすべての capability を取る（1543 行）。
- 最後の `releaseAllCapabilities(old_n_capabilities, …)`（2371 行）は、古い数のぶんしか返さない。
- そのため、二つの呼び出しが重なり、後の呼び出しが読んだ old_n が同期の時点の n_capabilities より小さいと、差のぶんの capability の `running_task` が後の呼び出しの Task のまま残る。
- 次の GC が、その capability を待ち続ける。
  - 漏れた capability が idle の扱いなら `waitForCapability`（1786–1789 行）で止まる。
  - 使用中の扱いなら `waitForGcThreads`（GC.c:1527）の 1 ms ごとの見回りが終わらない（CPU はほぼ使わない）。

### 確認の証拠（`evidence/`）

- **verify-a**（最小の再現 `CapRace.hs`、base だけ）：結果の表は `evidence/verify-a/RESULTS.md`。
  - 10 コアの Mac で、同時に増やすと 198/200 が止まる。2→16 を 14 スレッドで同時に呼ぶと 197/200。`-qg` を付けても 96/100 が止まる。
  - 対照：MVar で直列にすると 0/200、減らす向きだけだと 0/200、`-N8` で呼び出しが何もしないと 200/200 が正常に終わる。
  - debug RTS の gdb と `+RTS -Ds` で、漏れた capability の持ち主と、返されない capability を直接確かめた（`gdb/`、`trace/`）。
- **verify-b**（`SetCapsRace.hs`）：2 CPU のコンテナで 179 回のうち 5 回止まる。gdb のダンプ、`-Ds` のトレースあり。CI の直近 400 回の実行で止まったテストは、実行中に `setNumCapabilities` を呼ぶ 4 つだけだった（`ci-orphan-processes-per-run.txt`）。
- **plugin-test-repro**（`Race.hs`）：4 CPU の Linux で 10/32、macOS で 9/15 が止まる。1 回だけ呼ぶと 0/約 810。
- **tasty-pure-repro**：golem を使わない tasty のテストで 26/149 が止まる。
- **rts-9.10.3-source**：調べたときの RTS のソースの写し（2026-11-08 に削除。タグ ghc-9.10.3-release を参照）。

### Golem 側の対処（済み）

tett23/golem#174 で、テストを `-with-rtsopts=-N` でリンクし、テストから `setNumCapabilities` を外した。
`scripts/ci/rts-capabilities.sh` が再発を検査する。
以後、Golem の CI は止まっていない。

## まだ決まっていないこと（このセッションで扱う）

1. **issue の下書きの仕上げ**（`issue.md`）
   - `[VERIFY]` の数字を、上の verify-a と verify-b の結果で埋める。
   - `[FILL]` は tett23 の環境の情報（OS、C コンパイラのバージョンなど）で、tett23 に聞く。
   - 条件を正確に書き直す。「増やす呼び出しが 2 回重なる」より広く、「後の呼び出しが読んだ old_n が同期の時点の n_capabilities より小さい」なら、増やす向きでも減らす向きでも起きる（verify-a の hang3 が減らす向きの実例）。
   - 止まる箇所が 2 種類あること（`waitForCapability` と `waitForGcThreads`）を書く。
   - LLM を使ったことの申告の行を残す（GHC の AI の方針で必須）。
2. **verify-a が説明できなかった現象**
   - 直列にした場合や減らす向きだけの場合でも、capabilities の数（最大 13）がコア数（2〜10）より多いと、CPU を使ったまま数秒から 60 秒を超えて終わらないことがある（`busy_timeout`）。
   - `-fno-omit-yields` を付けても消えない。gdb では GC の途中（scavenge）か、`waitForGcThreads` の見回りの途中で、ダンプのたびに状態が変わる。1 件は 3 秒後に正常に終わった。
   - デッドロックではなく遅いだけと見ているが、原因はわかっていない。issue に含めるか、別に扱うかを決める。
3. **MR を出すかどうか**（`mr-outline.md`）
   - 修正の方針は、`old_n_capabilities` を読む処理と早期に返す判定を、`stopAllCapabilities` の後に移すこと。
   - 出すなら、hadrian で GHC をビルドし、修正の前に失敗し、後に安定して通るテスト（`testsuite/tests/rts/T番号`）を用意する必要がある。
   - MR は、すべての行を理解して説明できる人間の責任になる（GHC の AI の方針）。
4. **重複の確認**
   - gitlab.haskell.org の Web は Anubis で弾かれるので、REST API（`https://gitlab.haskell.org/api/v4/projects/ghc%2Fghc/issues?search=...`）か GitHub のミラーを使う。
   - 近い issue：[#22989](https://gitlab.haskell.org/ghc/ghc/-/issues/22989)、[#18808](https://gitlab.haskell.org/ghc/ghc/-/issues/18808)、[#27460](https://gitlab.haskell.org/ghc/ghc/-/issues/27460)、[#27473](https://gitlab.haskell.org/ghc/ghc/-/issues/27473)。同じ競合を書いたものは見つかっていない。
5. **tasty への連絡**：起動時の `setNumCapabilities` は tasty 1.5.4（UnkindPartition/tasty#457）で入り、#485 で取り消された（未リリース）。tasty に知らせる必要があるかを決める。

## ファイルの地図

- `README.md`：公開時の入口（英語）。`publish-checklist.md`：公開前に tett23 が決めること・直すこと（2026-11-08）。
- `tasty-comment.md`：tasty#485 への任意のコメントの下書き（HANDOFF の 5 の結論は notes-sources.md）。
- `issue-stoptimer.md`：遅延（HANDOFF の 2）の別 issue の英語の下書き。341ed474 のバックポート依頼。証拠は `evidence/sync-lag/`。
- `LOG.md`：調査の過程の時系列の記録（英語。2026-10-17 の引き継ぎ後に追加。試したこと、失敗、計測、判断の理由）。
- `mr/`：MR に入れるもの（パッチ、テスト、changelog、コミットメッセージ、MR の説明）。
- `evidence/rts-fix-check/`：GHC をビルドせずに修正を確かめた方法とその結果。
- `issue.md`：issue の英語の下書き（GHC の default の雛形に沿う）。
- `mr-outline.md`：MR の方針、コミットメッセージ、テストの案、changelog の書式。
- `maintainer-checklist.md`：tett23 が自分でやること（アカウント、投稿、MR）。
- `notes-sources.md`：読んだ URL、重複の検索の結果、判断の理由。
- `raw/`：2026-11-08 に公開準備で削除（GitLab API の JSON と GHC 文書の写し。読んだものの一覧は `notes-sources.md`）。
- `evidence/verify-a/`、`evidence/verify-b/`、`evidence/plugin-test-repro/`、`evidence/tasty-pure-repro/`：上の「確認の証拠」。`evidence/rts-9.10.3-source/`、`evidence/plugin-fix.diff` と `verify-b/proposed-fix-applied-in-scratch.diff`（Golem の diff）と `repro/` は 2026-11-08 に削除。

## 環境

- **Docker（colima）**：tett23 の指示で残してある。消さないこと。
  - プロファイル `default`（aarch64、2 CPU、2 GiB）
    - コンテナ `verify-a-1`（2 CPU、`/root/build` にバイナリとログ）、ボリューム `verify-a-home`
    - コンテナ `verify-b-1`、ボリューム `verify-b-home`
    - コンテナ `golemhang-a892`、ボリューム `golemhang-a892-home`
    - イメージ `golemhang-img`（debian、ghcup の GHC 9.10.3、cabal 3.16.1.0、gdb）、ボリューム `golemhang-home`
  - プロファイル `golemplug`（aarch64、4 CPU、8 GiB）
    - コンテナ `plughang`（debug 版のバイナリは `/w2`、修正版は `/t/plugin-fixed`）
  - メモリが少ないので、golem のような大きなプロジェクトのビルドは落ちることがある。最小の再現のプログラムなら問題ない。
- **clone 済みのリポジトリ**（ghq、読むだけ）
  - GHC：`/Users/tett23/repositories/src/github.com/ghc/ghc`（必要なファイルだけを取る部分的な clone。ghc-9.10.3-release と master 7dedcf135）
  - tasty：`/Users/tett23/repositories/src/github.com/UnkindPartition/tasty`
  - 必要なら ghq で公式の上流を clone してよい（tett23 の許可済み）。
- **Mac**：10 コア、ghcup の GHC 9.10.3、lldb。

## 決まりごと

- tett23 への出力は日本語。GHC に出す文は英語。
- 投稿、アカウントの作成、MR の push はしない（tett23 が行う）。
- ダウンロードは、公式の上流（GHC、tasty、公式の Docker イメージ、ghcup）に限る。
- Golem のリポジトリはこの調査では変更しない。
