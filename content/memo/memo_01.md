---
title: "コマンド力の推定"
date: 2025-11-11
categories: ["pitch単位"]
tags: ["Pitching", "コマンド"]
---

コマンド力の推定を捕手の構えという情報なしで行います。

コマンド力を「目標とした座標に投げられる能力」と定義すると、それの推定に必要なのは投手が当該投球において目標とした座標の推定です。
目標とした座標は捕手の構えと一致することが多いですが、投手も捕手も考えなしに目標座標は決めていないはずです。
ピッチカウント、打者、球種、その投手の特性、点差や塁状況などがそれを決定する要素となっているでしょう。

本格的なモデルを組まずともこれらの考え方を活かした簡素なコマンド指標を作ることはできます。

今回実行するにあたり条件とした要素は「ピッチカウント」「球種」「打席の左右」です。
それらの条件を揃えたデータセット内での投球座標の散らばりを見ることでコマンド力の推定を行います。

```r
library(tidyverse)

years <- 2021:2025
Name <- read_csv("name.csv") %>% select(Name, MLBAMID)

df <- map_dfr(years, ~read_csv(paste0(.x, ".csv")) %>% mutate(year = .x))

# 新しい列を作成
df <- df %>% 
  mutate(
  # 打者ごとに正規化する
    relative_x = plate_x / 0.833,
    relative_z = (plate_z - strike_zone_bottom) / 
                 (strike_zone_top - strike_zone_bottom),
    pitch_count = paste0(balls, "-", strikes)
  ) %>% 
  select(year, pitcher_id, bat_side, pitch_count, 
         plate_x, plate_z, relative_x, relative_z, 
         pitch_type, arm_angle)

# ユークリッド距離的散らばりを計算
df_dist <- df %>%
  group_by(pitcher_id, pitch_count, pitch_type, bat_side, year) %>%
  mutate(
    mean_x = mean(plate_x, na.rm = TRUE),
    mean_z = mean(plate_z, na.rm = TRUE),
    distance = sqrt((plate_x - mean_x)^2 + (plate_z - mean_z)^2)
  ) %>%
  select(year, pitcher_id, bat_side, pitch_count, pitch_type, arm_angle, distance) %>%
  ungroup()

# 投手ごとのサマリー
df_dist_summary <- df_dist %>% 
  group_by(year, pitcher_id) %>%
  summarize(
    mean_distance = mean(distance, na.rm = TRUE),
    sd_distance = sd(distance, na.rm = TRUE),
    min_distance = min(distance, na.rm = TRUE),
    max_distance = max(distance, na.rm = TRUE),
    IQR_distance = IQR(distance, na.rm = TRUE),
    p25_distance = quantile(distance, 0.25, na.rm = TRUE),
    p75_distance = quantile(distance, 0.75, na.rm = TRUE),
    pitches = n(),
    .groups = 'drop'
  ) %>% 
  group_by(year) %>%
  mutate(pitches_rank = percent_rank(pitches)) %>%
  filter(pitches_rank >= 0.5) %>%
  ungroup() %>%
  left_join(Name, by = c("pitcher_id" = "MLBAMID"))
```

かなり簡単な考え方と計算ですが理論的にはBB%のようなコマンド力を語る際に登場しやすい指標よりもコマンド力を推定するにおいてはノイズは小さくなります。
コマンド関係の指標との相関や2025年の上位下位20投手を以下に示します。

![コマンド力推定01](/resolving-baseball/images/34.png)
![コマンド力推定02](/resolving-baseball/images/35.png)
![コマンド力推定03](/resolving-baseball/images/36.png)

四分位範囲を選んだのは、真にコマンドの良い投手をなるべく過小評価したくないという考えからです。
今回条件とした要素以外にも投手や捕手は点差や塁状況、打者の特徴によって目標座標を変えていることは想定できます。
今回指定した条件の傾向から大きく外れる局面はそう多くはないと考えられるますが、平均値はもちろん標準偏差もそれらの少ない局面の影響を受けてしまいます。
四分位範囲とすることで外れ値的な目標座標を計算から除外し、コマンド最上位層の過小評価を簡便ではあるが是正することを試みました。

次回以降は基本的な考え方は受け継ぎつつも、数理モデルへの落とし込みや散らばり方の傾向に合わせた投球戦略などのステップに進めればと思います。