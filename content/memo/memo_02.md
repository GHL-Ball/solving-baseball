---
title: "xwOBAの改良"
date: 2025-10-11
categories: ["play単位"]
tags: ["Batting", "xwOBA"]
---

[Tangotiger Blog](https://tangotiger.com/index.php/search/results/7eafe5f4fef8ce0766fdcd926159fe64/)にて定期的にxwOBAにおいてSpray Angleは過剰適合してしまうという主旨の記事が上がります。

実際、全体の傾向として未知のデータに対する予測力においてLaunch SpeedとLaunch Angleに加えてSpray Angleを説明変数に加えるとモデルの精度は落ちます。

ただ、よく話題になるように個別事例においてはその傾向から良い意味でも悪い意味でも逸脱する打者も当然見られます。

xwOBAモデルにおける真の意味での誤差を見極め、Spray Angleを含めた情報の取捨選択をアップデートしていくことが最終的な目標となります。

Launch SpeedとLaunch Angleのみを説明変数としたxwOBAからSpray Angleの三方向（Pull、Cent、Oppo）のみの情報を付したモデル、Spray Angle（値）の情報を付したモデルの比較を以下に示します。

-![xwOBA比較](/resolving-baseball/images/37.png)

基本的にその年のwOBAの記述力はSpray Angleという情報を付与するほど、翌年のwOBAに対する予測力は付与しないほど上がります。

Spray Angle有のモデルと無のモデルで差が出た上位下位の打者20人を以下に示します。

-![xwOBA比較](/resolving-baseball/images/38.png)
-![xwOBA比較](/resolving-baseball/images/39.png)

複数年で登場する打者が存在するようにSpray Angleの情報が必要な打者も存在する可能性は十分にあります。
ただこれらの誤差には当然球場や対戦相手の偏りも含まれていますので、それらを考慮しながらサンプルサイズにおける誤差も抽出し、最終的には帰属できていない要素を定量化できればと思います。