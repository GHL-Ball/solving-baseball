# calc_timing_disruption.R

library(DBI)
library(RSQLite)
library(tidyverse)
library(mgcv)

# パス設定
DATA_DIR <- Sys.getenv("BASEBALL_DATA_DIR")
DB_PATH  <- file.path(DATA_DIR, "pitch_by_pitch.sqlite")

con <- dbConnect(SQLite(), DB_PATH)
query <- "SELECT * FROM pbp_2021_2025 WHERE year IN (2023, 2024, 2025)"
df_all <- dbGetQuery(con, query)

dbDisconnect(con)

df_all_swing <- df_all %>% 
  filter(!is.na(bat_speed),
         !is.na(swing_length),
         !is.na(intercept_ball_minus_batter_pos_y_inches),
         !is.na(plate_x_rel),
         !is.na(plate_z_rel),
         !is.na(release_speed),
         description %in% c("foul", "hit_into_play", "swinging_strike", "swinging_strike_blocked"),
         !str_detect(des, "(?i)bunt") | is.na(des)) |> 
  mutate(batter_year_id = factor(batter_year_id),
         handedness_type = factor(handedness_type))

# 混合モデル①（GAMM）: Intercept Point
mod_intercept_1 <- bam(
  intercept_ball_minus_batter_pos_y_inches ~ 
    s(plate_x_rel, plate_z_rel, by = handedness_type) + 
    handedness_type + pitch_count +
    s(batter_year_id, bs = "re"),
  data = df_all_swing,
  discrete = TRUE,
  nthreads = 4
)

# Swing Length
mod_swing_len_1 <- bam(
  swing_length ~ 
    s(plate_x_rel, plate_z_rel, by = handedness_type) + 
    handedness_type + pitch_count +
    s(batter_year_id, bs = "re"),
  data = df_all_swing,
  discrete = TRUE,
  nthreads = 4
)

# 混合モデル②（GAMM）: Intercept Point
mod_intercept_2 <- bam(
  intercept_ball_minus_batter_pos_y_inches ~ 
    s(plate_x_rel, plate_z_rel, by = handedness_type) + 
    handedness_type + 
    pitch_count +
    s(release_speed) +
    s(batter_year_id, bs = "re"),
  data = df_all_swing,
  discrete = TRUE,
  nthreads = 4
)

# Swing Length
mod_swing_len_2 <- bam(
  swing_length ~ 
    s(plate_x_rel, plate_z_rel, by = handedness_type) + 
    handedness_type + 
    pitch_count +
    s(release_speed) +
    s(batter_year_id, bs = "re"),
  data = df_all_swing,
  discrete = TRUE,
  nthreads = 4
)

# 1. 予測値と残差の算出
df_all_swing <- df_all_swing %>%
  mutate(
    # 打点前後の偏差
    pred_y_1 = predict(mod_intercept_1, newdata = .),
    res_y_1 = intercept_ball_minus_batter_pos_y_inches - pred_y_1,
    pred_y_2 = predict(mod_intercept_2, newdata = .),
    res_y_2 = intercept_ball_minus_batter_pos_y_inches - pred_y_2,
    
    # スイングの長さの偏差
    pred_len_1 = predict(mod_swing_len_1, newdata = .),
    res_len_1 = swing_length - pred_len_1,
    pred_len_2 = predict(mod_swing_len_2, newdata = .),
    res_len_2 = swing_length - pred_len_2
  )

# 2. 打者×年度内での標準化
df_all_swing <- df_all_swing %>%
  group_by(batter_year_id) %>%
  mutate(
    # その打者の普段のバラつきを 1 とした時の「外され度」
    timing_index_intercept_1 = as.vector(scale(res_y_1)),
    timing_index_swing_len_1 = as.vector(scale(res_len_1)),
    timing_index_intercept_2 = as.vector(scale(res_y_2)),
    timing_index_swing_len_2 = as.vector(scale(res_len_2))
  ) %>%
  ungroup()

# 3. 投手×年度で集計
leaderboard_disruption <- df_all_swing %>%
  group_by(pitcher_id, year) %>%
  summarise(
    n_pitches = n(),
    
    # Disruption：打者のタイミングをどれだけバラつかせたか
    disruption_1 = round(mean(abs(timing_index_intercept_1 - (0.4)), na.rm = TRUE), 3),
    disruption_2 = round(mean(abs(timing_index_intercept_2 - (-0.3)), na.rm = TRUE), 3),
    disruption_len_1 = round(mean(abs(timing_index_swing_len_1 - (0.2)), na.rm = TRUE), 3),
    disruption_len_2 = round(mean(abs(timing_index_swing_len_2 - (-0.2)), na.rm = TRUE), 3),
    
    # Bias：どちら方向にズラしたか（平均）
    # 正 = 早め / 負 = 遅め（intercept_ball_minus_batter_pos_y_inchesの符号次第）
    bias_1 = round(mean(timing_index_intercept_1, na.rm = TRUE), 3),
    bias_2 = round(mean(timing_index_intercept_2, na.rm = TRUE), 3),
    bias_len_1 = round(mean(timing_index_swing_len_1, na.rm = TRUE), 3),
    bias_len_2 = round(mean(timing_index_swing_len_2, na.rm = TRUE), 3),
    
    .groups = "drop"
  )

OUTPUT_DIR <- here::here("data/leaderboards")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

write_csv(
  leaderboard_disruption,
  file.path(OUTPUT_DIR, "disruption_2023_2025.csv")
)
