# calc_pitch_model_gbdt

library(DBI)
library(RSQLite)
library(tidyverse)
library(mgcv)
library(catboost)
library(caret)
library(jsonlite)
library(httr)

# パス設定
DATA_DIR <- Sys.getenv("BASEBALL_DATA_DIR")
DB_PATH  <- file.path(DATA_DIR, "pitch_by_pitch.sqlite")

con <- dbConnect(SQLite(), DB_PATH)
query <- "SELECT * FROM pbp_2021_2025"
df_all <- dbGetQuery(con, query)

dbDisconnect(con)

fg21 <- read.csv("2021.csv") 
fg22 <- read.csv("2022.csv") 
fg23 <- read.csv("2023.csv") 
fg24 <- read.csv("2024.csv") 
fg25 <- read.csv("2025.csv")

df21 <- df_all |> filter(year == 2021)
df22 <- df_all |> filter(year == 2022)
df23 <- df_all |> filter(year == 2023)
df24 <- df_all |> filter(year == 2024)
df25 <- df_all |> filter(year == 2025)

# 学習データは22~24年
pitch_data <- bind_rows(df22, df23, df24)

pitch_data <- pitch_data %>% 
  filter(!pitch_type %in% c("FA", "EP", "PO")) %>% 
  mutate(pitch_type = ifelse(pitch_type == "FO", "FS", pitch_type),
         pitch_type = factor(pitch_type))

original_pitch_type_levels <- levels(pitch_data$pitch_type)

df25 <- df25 %>% 
  filter(!pitch_type %in% c("FA", "EP", "PO")) %>% 
  mutate(pitch_type = ifelse(pitch_type == "FO", "FS", pitch_type),
         pitch_type = factor(pitch_type, levels = original_pitch_type_levels))

df21 <- df21 %>% 
  filter(!pitch_type %in% c("FA", "EP", "PO")) %>% 
  mutate(pitch_type = ifelse(pitch_type == "FO", "FS", pitch_type),
         pitch_type = factor(pitch_type, levels = original_pitch_type_levels))

create_target_variables <- function(data) {
  data %>%
    filter(!(description %in% c("foul_bunt", "missed_bunt", 
                                "pitchout", "bunt_foul_tip",
                                "foul_pitchout")),
           balls <= 3, strikes <= 2) %>% 
    mutate(
      # スイング/見逃し
      is_swing = ifelse(description %in% c("swinging_strike", "foul", "hit_into_play",
                                           "swinging_strike_blocked", "foul_tip"), 1, 0),
      
      # ボール/ストライク（見逃し時のみ）
      is_called_strike = case_when(
        is_swing == 0 & description == "called_strike" ~ 1,
        is_swing == 0 & description %in% c("ball", "blocked_ball", "hit_by_pitch") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_called_ball = case_when(
        is_swing == 0 & description %in% c("ball", "blocked_ball") ~ 1,
        is_swing == 0 & description %in% c("called_strike", "hit_by_pitch") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_hit_by_pitch = case_when(
        is_swing == 0 & description == "hit_by_pitch" ~ 1,
        is_swing == 0 & description %in% c("called_strike", "ball", "blocked_ball") ~ 0,
        TRUE ~ NA_real_
      ),
      
      # スイング結果（スイング時のみ）
      is_whiff = case_when(
        is_swing == 1 & description %in% c("swinging_strike", "foul_tip", "swinging_strike_blocked") ~ 1,
        is_swing == 1 & description %in% c("foul", "hit_into_play") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_foul = case_when(
        is_swing == 1 & description == "foul" ~ 1,
        is_swing == 1 & description %in% c("swinging_strike", "foul_tip", "swinging_strike_blocked", "hit_into_play") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_bbe = case_when(
        is_swing == 1 & description == "hit_into_play" ~ 1,
        is_swing == 1 & description %in% c("swinging_strike", "foul", "foul_tip", "swinging_strike_blocked") ~ 0,
        TRUE ~ NA_real_
      ),
      
      pitch_count = paste0(balls, "-", strikes)
    ) %>% 
    filter(is_bbe == 0 | is.na(is_bbe) | (is_bbe == 1 & !is.na(xrv)))
}

pitch_data <- create_target_variables(pitch_data)

# ピッチカウントを考慮した基準値
pitch_count_summary <- pitch_data %>%
  group_by(pitch_count) %>% 
  summarise(
    avg_swing_rate = mean(is_swing),
    avg_called_strike_rate = mean(is_called_strike, na.rm = T),
    avg_called_ball_rate   = mean(is_called_ball, na.rm = T),
    avg_hit_by_pitch_rate  = mean(is_hit_by_pitch, na.rm = T),
    avg_whiff_rate = mean(is_whiff, na.rm = T),
    avg_foul_rate  = mean(is_foul, na.rm = T),
    avg_bbe_rate   = mean(is_bbe, na.rm = T),
    avg_xrv_bbe = mean(xrv[is_bbe == 1], na.rm = T)
  )

pitch_data <- pitch_data %>% 
  left_join(pitch_count_summary, by = "pitch_count")

# 目的変数の作成
pitch_data <- pitch_data %>% 
  mutate(diff_swing_rate = is_swing - avg_swing_rate,
         diff_called_strike_rate = is_called_strike - avg_called_strike_rate,
         diff_called_ball_rate = is_called_ball - avg_called_ball_rate,
         diff_hit_by_pitch_rate = is_hit_by_pitch - avg_hit_by_pitch_rate,
         diff_whiff_rate = is_whiff - avg_whiff_rate,
         diff_foul_rate = is_foul - avg_foul_rate,
         diff_bbe_rate = is_bbe - avg_bbe_rate,
         diff_xrv_bbe = xrv - avg_xrv_bbe)

# 身長の取得
parse_height <- function(height_str) {
  height_parts <- strsplit(height_str, "' ")[[1]]
  feet <- as.numeric(height_parts[1])
  inches <- as.numeric(gsub('"', '', height_parts[2]))
  height_in_feet <- feet + inches / 12
  return(height_in_feet)
}

chunk_list <- function(lst, chunk_size) {
  split(lst, ceiling(seq_along(lst) / chunk_size))
}

get_player_heights <- function(player_ids) {
  all_data <- list()
  chunks <- chunk_list(player_ids, 500)
  for (chunk in chunks) {
    player_id_str <- paste(chunk, collapse = ",")
    url <- paste0('https://statsapi.mlb.com/api/v1/people?personIds=', player_id_str, '&fields=people,id,height,weight')
    response <- GET(url)
    if (http_status(response)$category != "Success") {
      stop("HTTP request failed")
    }
    json_data <- content(response, as = "parsed", simplifyVector = TRUE)$people
    data <- as.data.frame(json_data)
    data$height <- sapply(data$height, parse_height)
    all_data <- append(all_data, list(data))
    Sys.sleep(0.5)
  }
  result_df <- bind_rows(all_data)
  return(result_df)
}

pitcher_MLBAMID <- bind_rows(df21, df22, df23, df24, df25) %>%
  select(pitcher_id)

pitcher_MLBAMID <- distinct(pitcher_MLBAMID)

pitcher_MLBAMID$MLBAMID <- pitcher_MLBAMID$pitcher_id

pitcher_MLBAMID <- pitcher_MLBAMID %>% select(-pitcher_id)

player_ids <- pitcher_MLBAMID$MLBAMID

player_data <- get_player_heights(player_ids)

Height_pitcher <- merge(pitcher_MLBAMID, player_data, by.x = "MLBAMID", by.y = "id", all.x = TRUE)

pitch_data <- pitch_data %>%
  left_join(Height_pitcher, by = c("pitcher_id" = "MLBAMID")) %>% 
  rename(pitcher_height = height) %>% 
  mutate(pitcher_height = round(pitcher_height, 2))

# 特微量の作成
pitch_data <- pitch_data %>% 
  mutate(release_pos_x_relative = ifelse(pitch_hand == "L", -release_pos_x, release_pos_x),
         ax_relative = round(ifelse(pitch_hand == "L", -ax, ax), 3),
         az = round(az, 3),
         plate_x_relative = round(ifelse(bat_side == "R", plate_x / 0.833, - plate_x / 0.833), 2),
         plate_z_relative = round((plate_z - strike_zone_bottom) / (strike_zone_top - strike_zone_bottom), 2),
         total_movement = sqrt(pfx_x^2 + pfx_z^2)
  ) %>% 
  filter(!is.na(release_pos_x_relative),
         !is.na(release_pos_z),
         !is.na(extension),
         !is.na(pitcher_height),
         !is.na(bat_side),
         !is.na(spin_axis),
         !is.na(pfx_x),
         !is.na(pfx_z),
         !is.na(release_spin_rate),
         !is.na(release_speed),
         !is.na(ax_relative),
         !is.na(az),
         !is.na(arm_angle),
         !is.na(plate_x_relative),
         !is.na(plate_z_relative),
         !is.na(total_movement),
  )

pitch_data <- pitch_data %>% 
  mutate(spin_axis_diff = spin_axis_movement_diff_signed,
         release_spin_rate_diff = spin_efficiency_total_nathan_raw)

# 1. 投手・シーズン・球種ごとに速球の投球数と平均値を集計
fb_summary <- pitch_data %>%
  filter(pitch_type %in% c("FF", "SI", "FC")) %>%
  group_by(pitcher_id, year, pitch_type) %>%
  summarise(
    n_pitches = n(),
    avg_velo = mean(release_speed, na.rm = TRUE),
    avg_ax_relative = mean(ax_relative, na.rm = TRUE),
    avg_az = mean(az, na.rm = TRUE),
    .groups = "drop"
  )

# 2. 投手・シーズンごとに最も投球数が多い速球を特定
primary_fb <- fb_summary %>%
  group_by(pitcher_id, year) %>%
  mutate(priority = case_when(
    pitch_type == "FF" ~ 1,
    pitch_type == "SI" ~ 2,
    pitch_type == "FC" ~ 3
  )) %>%
  arrange(desc(n_pitches), priority) %>%
  slice(1) %>%
  ungroup() %>%
  select(pitcher_id, year, primary_fb_velo = avg_velo, 
         primary_fb_ax_relative = avg_ax_relative, primary_fb_az = avg_az)

# 3. 元のデータに結合
pitch_data <- pitch_data %>%
  left_join(primary_fb, by = c("pitcher_id", "year"))

pitch_data <- pitch_data %>% 
  mutate(release_speed_diff = release_speed - primary_fb_velo,
         ax_relative_diff = ax_relative - primary_fb_ax_relative,
         az_diff = az - primary_fb_az)

# 特微量の選定
stuff_rp_features <- c(
  "release_pos_x_relative",
  "release_pos_z",
  "pitcher_height",
  "bat_side",
  "spin_axis_diff",
  "release_spin_rate_diff",
  "release_speed",
  "ax_relative",
  "az",
  "arm_angle",
  "release_speed_diff",
  "ax_relative_diff",
  "az_diff"
)

location_rp_features <- c(
  "bat_side",
  "plate_x_relative",
  "plate_z_relative"
)

pitch_rp_features <- c(
  "release_pos_x_relative",
  "release_pos_z",
  "pitcher_height",
  "bat_side",
  "spin_axis_diff",
  "release_spin_rate_diff",
  "release_speed",
  "ax_relative",
  "az",
  "arm_angle",
  "release_speed_diff",
  "ax_relative_diff",
  "az_diff",
  "plate_x_relative",
  "plate_z_relative"
)

create_variables_new_data <- function(x, df){
  df <- df %>% 
    left_join(Height_pitcher, by = c("pitcher_id" = "MLBAMID")) %>% 
    rename(pitcher_height = height) %>% 
    filter(!is.na(pitcher_height),
           !is.na(bat_side),
           !is.na(spin_axis),
           !is.na(pfx_x),
           !is.na(pfx_z),
           !is.na(release_spin_rate),
           !is.na(release_speed))
  
  df <- df %>% 
    mutate(release_pos_x_relative = ifelse(pitch_hand == "L", -release_pos_x, release_pos_x),
           ax_relative = round(ifelse(pitch_hand == "L", -ax, ax), 3),
           az = round(az, 3),
           plate_x_relative = round(ifelse(bat_side == "R", plate_x / 0.833, - plate_x / 0.833), 2),
           plate_z_relative = round((plate_z - strike_zone_bottom) / (strike_zone_top - strike_zone_bottom), 2),
           total_movement = sqrt(pfx_x^2 + pfx_z^2))
  
  df <- df %>% 
    filter(!is.na(release_pos_x_relative),
           !is.na(release_pos_z),
           !is.na(extension),
           !is.na(ax_relative),
           !is.na(az),
           !is.na(arm_angle),
           !is.na(plate_x_relative),
           !is.na(plate_z_relative))
}

create_fb_stats <- function(data){
  # 1. 投手・シーズン・球種ごとに速球の投球数と平均値を集計
  fb_data <- data %>%
    filter(pitch_type %in% c("FF", "SI", "FC")) %>%
    group_by(pitcher_id, year, pitch_type) %>%
    summarise(
      n_pitches = n(),
      avg_velo = mean(release_speed, na.rm = TRUE),
      avg_ax_relative = mean(ax_relative, na.rm = TRUE),
      avg_az = mean(az, na.rm = TRUE),
      .groups = "drop"
    )
  
  # 2. 投手・シーズンごとに最も投球数が多い速球を特定
  primary_fb_data <- fb_data %>%
    group_by(pitcher_id, year) %>%
    mutate(priority = case_when(
      pitch_type == "FF" ~ 1,
      pitch_type == "SI" ~ 2,
      pitch_type == "FC" ~ 3
    )) %>%
    arrange(desc(n_pitches), priority) %>%
    slice(1) %>%
    ungroup() %>%
    select(pitcher_id, year, primary_fb_velo = avg_velo, 
           primary_fb_ax_relative = avg_ax_relative, primary_fb_az = avg_az)
  
  # 3. 元のデータに結合
  data <- data %>%
    left_join(primary_fb_data, by = c("pitcher_id", "year"))
  
  data <- data %>% 
    mutate(release_speed_diff = release_speed - primary_fb_velo,
           ax_relative_diff = ax_relative - primary_fb_ax_relative,
           az_diff = az - primary_fb_az)
  
}

df25_with_modeling <- df25 %>% create_variables_new_data(df25)
df25_with_modeling <- create_fb_stats(df25_with_modeling)
df25_with_modeling <- df25_with_modeling %>%
  mutate(spin_axis_diff = spin_axis_movement_diff_signed,
         release_spin_rate_diff = spin_efficiency_total_nathan_raw,
         release_speed_diff = release_speed - primary_fb_velo,
         ax_relative_diff = ax_relative - primary_fb_ax_relative,
         az_diff = az - primary_fb_az)

df21_with_modeling <- df21 %>% create_variables_new_data(df21)
df21_with_modeling <- create_fb_stats(df21_with_modeling)
df21_with_modeling <- df21_with_modeling %>%
  mutate(spin_axis_diff = spin_axis_movement_diff_signed,
         release_spin_rate_diff = spin_efficiency_total_nathan_raw,
         release_speed_diff = release_speed - primary_fb_velo,
         ax_relative_diff = ax_relative - primary_fb_ax_relative,
         az_diff = az - primary_fb_az)

df24_with_modeling <- pitch_data %>% filter(year == 2024)
df23_with_modeling <- pitch_data %>% filter(year == 2023)
df22_with_modeling <- pitch_data %>% filter(year == 2022)

# データの準備関数(変更なし)
prepare_model_data <- function(data, model_type, target_var = NULL) {
  if (model_type == "swing") {
    model_data <- data %>%
      select(all_of(c("diff_swing_rate", stuff_rp_features, location_rp_features, pitch_rp_features))) %>%
      filter(!is.na(diff_swing_rate))
    
    target <- "diff_swing_rate"
    
  } else if (model_type == "take") {
    model_data <- data %>%
      filter(is_swing == 0) %>%
      select(all_of(c(target_var, stuff_rp_features, location_rp_features, pitch_rp_features))) %>%
      filter(!is.na(.data[[target_var]]))
    
    target <- target_var
    
  } else if (model_type == "swing_result") {
    model_data <- data %>%
      filter(is_swing == 1) %>%
      select(all_of(c(target_var, stuff_rp_features, location_rp_features, pitch_rp_features))) %>%
      filter(!is.na(.data[[target_var]]))
    
    target <- target_var
    
  } else if (model_type == "bbe") {
    model_data <- data %>%
      filter(is_bbe == 1) %>%
      select(all_of(c("diff_xrv_bbe", stuff_rp_features, location_rp_features, pitch_rp_features))) %>%
      filter(!is.na(diff_xrv_bbe))
    
    target <- "diff_xrv_bbe"
  }
  
  return(list(data = model_data, target = target))
}

# CatBoostモデル訓練関数（修正版）
train_catboost_model <- function(data, target_col, features, model_type, feature_type) {
  
  # 特徴量とターゲットの準備
  X <- data[, features, drop = FALSE]
  y <- data[[target_col]]
  
  # bat_sideをfactorに変換（CatBoostはfactorを自動処理）
  if ("bat_side" %in% names(X)) {
    X$bat_side <- as.factor(X$bat_side)
  }
  
  # 訓練・検証分割(80:20)
  set.seed(42)
  train_idx <- createDataPartition(y, p = 0.8, list = FALSE)[,1]
  
  X_train <- X[train_idx, ]
  X_val <- X[-train_idx, ]
  y_train <- y[train_idx]
  y_val <- y[-train_idx]
  
  # CatBoost用データセット作成（cat_featuresは指定しない）
  train_pool <- catboost.load_pool(
    data = X_train,
    label = y_train
  )
  
  val_pool <- catboost.load_pool(
    data = X_val,
    label = y_val
  )
  
  # パラメータ設定（修正版）
  params <- list(
    loss_function = "RMSE",
    iterations = 1000,
    learning_rate = 0.1,
    depth = 6,
    l2_leaf_reg = 3,
    bootstrap_type = "Bayesian",
    bagging_temperature = 1,
    random_seed = 42,
    verbose = 0,  # FALSE → 0 に変更
    early_stopping_rounds = 50
  )
  
  # モデル訓練
  model <- catboost.train(
    learn_pool = train_pool,
    test_pool = val_pool,
    params = params
  )
  
  # 予測
  pred_val <- catboost.predict(model, val_pool)
  pred_train <- catboost.predict(model, train_pool)
  
  # 特徴量重要度の取得
  importance <- catboost.get_feature_importance(
    model = model,
    pool = train_pool,
    type = "FeatureImportance"
  )
  
  # 特徴量重要度をデータフレームに整形
  importance_df <- data.frame(
    Feature = colnames(X_train),
    Importance = as.vector(importance),
    stringsAsFactors = FALSE
  )
  
  # カテゴリカル変数のインデックスを取得（factor列を特定）
  cat_indices <- which(sapply(X_train, is.factor)) - 1  # 0-indexed
  
  # 結果の返却
  result <- list(
    model = model,
    feature_importance = importance_df,
    feature_names = colnames(X_train),
    train_rmse = sqrt(mean((pred_train - y_train)^2)),
    val_rmse = sqrt(mean((pred_val - y_val)^2)),
    model_info = paste(model_type, feature_type, "CatBoost", sep = "_"),
    cat_indices = cat_indices
  )
  
  return(result)
}

# メイン実行部分
cat("CatBoostモデル訓練開始...\n")

# モデルタイプと対応する目的変数の定義(変更なし)
model_configs <- list(
  swing = list(targets = "diff_swing_rate", data_filter = "all"),
  take = list(targets = c("diff_called_strike_rate", "diff_called_ball_rate", "diff_hit_by_pitch_rate"), 
              data_filter = "is_swing == 0"),
  swing_result = list(targets = c("diff_whiff_rate", "diff_foul_rate", "diff_bbe_rate"), 
                      data_filter = "is_swing == 1"),
  bbe = list(targets = "diff_xrv_bbe", data_filter = "is_bbe == 1")
)

feature_types <- c("stuff", "location", "pitch")

# 結果保存用リスト
catboost_results <- list()

for (model_type in names(model_configs)) {
  cat(paste("モデルタイプ:", model_type, "\n"))
  
  config <- model_configs[[model_type]]
  
  for (target_var in config$targets) {
    cat(paste("  目的変数:", target_var, "\n"))
    
    # データ準備
    model_data_result <- prepare_model_data(pitch_data, model_type, target_var)
    model_data <- model_data_result$data
    target_col <- model_data_result$target
    
    for (feature_type in feature_types) {
      cat(paste("    フィーチャータイプ:", feature_type, "\n"))
      
      # 使用する特徴量の選択
      if (feature_type == "stuff") {
        features <- stuff_rp_features
      } else if (feature_type == "location") {
        features <- location_rp_features
      } else {
        features <- pitch_rp_features
      }
      
      # 利用可能な特徴量のみ使用
      available_features <- intersect(features, colnames(model_data))
      
      if (length(available_features) > 0) {
        # モデル訓練
        result <- train_catboost_model(
          data = model_data,
          target_col = target_col,
          features = available_features,
          model_type = model_type,
          feature_type = feature_type
        )
        
        # 結果保存
        result_name <- paste("catboost", model_type, gsub("diff_|_rate", "", target_var), feature_type, sep = "_")
        catboost_results[[result_name]] <- result
        
        # スコア表示
        cat(paste("      訓練RMSE:", round(result$train_rmse, 6), "\n"))
        cat(paste("      検証RMSE:", round(result$val_rmse, 6), "\n"))
      } else {
        cat(paste("      警告: 利用可能な特徴量が見つかりません\n"))
      }
    }
  }
  cat("\n")
}

cat("CatBoost訓練完了!\n")

# 結果サマリー表示
cat("\n=== CatBoost結果サマリー ===\n")
for (name in names(catboost_results)) {
  result <- catboost_results[[name]]
  cat(paste(name, ": 検証RMSE =", round(result$val_rmse, 6), "\n"))
}

# 新しいデータにCatBoostモデルを適用する関数
apply_catboost_models <- function(new_data, model_results) {
  
  predictions_df <- new_data
  
  cat("CatBoostモデルを新しいデータに適用中...\n")
  
  for (model_name in names(model_results)) {
    cat(paste("適用中:", model_name, "\n"))
    
    model_info <- model_results[[model_name]]
    model <- model_info$model
    trained_features <- model_info$feature_names
    cat_indices <- model_info$cat_indices
    
    cat(paste("  訓練された特徴量数:", length(trained_features), "\n"))
    cat(paste("  特徴量:", paste(trained_features, collapse = ", "), "\n"))
    
    # 訓練時と同じ特徴量のみ使用
    available_features <- intersect(trained_features, colnames(new_data))
    
    if (length(available_features) == length(trained_features)) {
      # 特徴量データの準備(訓練時と同じ順序で)
      X_new <- new_data[, trained_features, drop = FALSE]
      
      # bat_sideをfactorに変換(訓練時と同じ処理)
      if ("bat_side" %in% names(X_new)) {
        X_new$bat_side <- as.factor(X_new$bat_side)
      }
      
      # 欠損値がある行を特定
      complete_rows <- complete.cases(X_new)
      
      if (sum(complete_rows) > 0) {
        # 予測結果を全データの長さで初期化
        predictions <- rep(NA, nrow(new_data))
        
        # 完全なデータがある行のインデックス
        valid_indices <- which(complete_rows)
        
        # CatBoost用のPoolを作成して予測実行
        test_pool <- catboost.load_pool(
          data = X_new[complete_rows, ],
          cat_features = if(length(cat_indices) > 0) cat_indices else NULL
        )
        
        pred_values <- catboost.predict(model, test_pool)
        predictions[valid_indices] <- pred_values
        
        # 予測結果を列として追加
        col_name <- paste("pred", model_name, sep = "_")
        predictions_df[[col_name]] <- predictions
        
        cat(paste("  予測完了:", length(valid_indices), "/", nrow(new_data), "行\n"))
      } else {
        cat(paste("  警告: 完全なデータがありません\n"))
      }
    } else {
      cat(paste("  警告: 必要な特徴量が不足しています\n"))
      cat(paste("  不足: ", paste(setdiff(trained_features, available_features), collapse = ", "), "\n"))
    }
  }
  
  cat("モデル適用完了!\n")
  return(predictions_df)
}

# モデルを適用
df25_with_predictions <- apply_catboost_models(df25_with_modeling, catboost_results)
df21_with_predictions <- apply_catboost_models(df21_with_modeling, catboost_results)

df24_with_predictions <- apply_catboost_models(df24_with_modeling, catboost_results)
df23_with_predictions <- apply_catboost_models(df23_with_modeling, catboost_results)
df22_with_predictions <- apply_catboost_models(df22_with_modeling, catboost_results)

calculate_pitcher_metrics <- function(df_with_predictions, train_bbe_data, fg_data) {
  
  # 1. 結果変数の作成
  df_processed <- df_with_predictions %>%
    filter(!(description %in% c("foul_bunt", "missed_bunt", 
                                "pitchout", "bunt_foul_tip",
                                "foul_pitchout")),
           balls <= 3, strikes <= 2) %>% 
    mutate(
      # スイング/見逃し
      is_swing = ifelse(description %in% c("swinging_strike", "foul", "hit_into_play",
                                           "swinging_strike_blocked", "foul_tip"), 1, 0),
      
      # ボール/ストライク(見逃し時のみ)
      is_called_strike = case_when(
        is_swing == 0 & description == "called_strike" ~ 1,
        is_swing == 0 & description %in% c("ball", "blocked_ball", "hit_by_pitch") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_called_ball = case_when(
        is_swing == 0 & description %in% c("ball", "blocked_ball") ~ 1,
        is_swing == 0 & description %in% c("called_strike", "hit_by_pitch") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_hit_by_pitch = case_when(
        is_swing == 0 & description == "hit_by_pitch" ~ 1,
        is_swing == 0 & description %in% c("called_strike", "ball", "blocked_ball") ~ 0,
        TRUE ~ NA_real_
      ),
      
      # スイング結果(スイング時のみ)
      is_whiff = case_when(
        is_swing == 1 & description %in% c("swinging_strike", "foul_tip", "swinging_strike_blocked") ~ 1,
        is_swing == 1 & description %in% c("foul", "hit_into_play") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_foul = case_when(
        is_swing == 1 & description == "foul" ~ 1,
        is_swing == 1 & description %in% c("swinging_strike", "foul_tip", "swinging_strike_blocked", "hit_into_play") ~ 0,
        TRUE ~ NA_real_
      ),
      
      is_bbe = case_when(
        is_swing == 1 & description == "hit_into_play" ~ 1,
        is_swing == 1 & description %in% c("swinging_strike", "foul", "foul_tip", "swinging_strike_blocked") ~ 0,
        TRUE ~ NA_real_
      ),
      
      pitch_count = paste0(balls, "-", strikes)
    )
  
  # 2. リーグ平均値の計算
  avg_swing_rate <- mean(df_processed$is_swing)
  avg_called_strike_rate <- mean(df_processed$is_called_strike[df_processed$is_swing == 0], na.rm = TRUE)
  avg_called_ball_rate <- mean(df_processed$is_called_ball[df_processed$is_swing == 0], na.rm = TRUE)
  avg_hit_by_pitch_rate <- mean(df_processed$is_hit_by_pitch[df_processed$is_swing == 0], na.rm = TRUE)
  avg_whiff_rate <- mean(df_processed$is_whiff[df_processed$is_swing == 1], na.rm = TRUE)
  avg_foul_rate <- mean(df_processed$is_foul[df_processed$is_swing == 1], na.rm = TRUE)
  avg_bbe_rate <- mean(df_processed$is_bbe[df_processed$is_swing == 1], na.rm = TRUE)
  avg_bbe_xrv <- mean(df_processed$xrv[df_processed$is_bbe == 1], na.rm = TRUE)
  
  avg_called_strike_value <- mean(df_processed$delta_pitcher_run_exp[df_processed$is_called_strike == 1], na.rm = TRUE)
  avg_called_ball_value <- mean(df_processed$delta_pitcher_run_exp[df_processed$is_called_ball == 1], na.rm = TRUE)
  avg_hit_by_pitch_value <- mean(df_processed$delta_pitcher_run_exp[df_processed$is_hit_by_pitch == 1], na.rm = TRUE)
  avg_swinging_strike_value <- mean(df_processed$delta_pitcher_run_exp[df_processed$is_whiff == 1], na.rm = TRUE)
  avg_foul_value <- mean(df_processed$delta_pitcher_run_exp[df_processed$is_foul == 1], na.rm = TRUE)
  
  # 3. Stuff/Location/Pitchの各種率を計算
  # ★ catboost に変更
  df_processed <- df_processed %>% 
    mutate(
      # Stuff rates
      stuff_whiff_rate_cat = avg_whiff_rate + pred_catboost_swing_result_whiff_stuff,
      stuff_foul_rate_cat = avg_foul_rate + pred_catboost_swing_result_foul_stuff,
      stuff_bbe_rate_cat = avg_bbe_rate + pred_catboost_swing_result_bbe_stuff,
      
      # Location rates
      loc_called_strike_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_location) * 
        (avg_called_strike_rate + pred_catboost_take_called_strike_location),
      loc_called_ball_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_location) * 
        (avg_called_ball_rate + pred_catboost_take_called_ball_location),
      loc_hit_by_pitch_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_location) * 
        (avg_hit_by_pitch_rate + pred_catboost_take_hit_by_pitch_location),
      loc_whiff_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_location) * 
        (avg_whiff_rate + pred_catboost_swing_result_whiff_location),
      loc_foul_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_location) * 
        (avg_foul_rate + pred_catboost_swing_result_foul_location),
      loc_bbe_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_location) * 
        (avg_bbe_rate + pred_catboost_swing_result_bbe_location),
      
      # Pitch rates
      pit_called_strike_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_pitch) * 
        (avg_called_strike_rate + pred_catboost_take_called_strike_pitch),
      pit_called_ball_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_pitch) * 
        (avg_called_ball_rate + pred_catboost_take_called_ball_pitch),
      pit_hit_by_pitch_rate_cat = (1 - avg_swing_rate - pred_catboost_swing_swing_pitch) * 
        (avg_hit_by_pitch_rate + pred_catboost_take_hit_by_pitch_pitch),
      pit_whiff_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_pitch) * 
        (avg_whiff_rate + pred_catboost_swing_result_whiff_pitch),
      pit_foul_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_pitch) * 
        (avg_foul_rate + pred_catboost_swing_result_foul_pitch),
      pit_bbe_rate_cat = (avg_swing_rate + pred_catboost_swing_swing_pitch) * 
        (avg_bbe_rate + pred_catboost_swing_result_bbe_pitch)
    ) %>% 
    
    # 4. Run値の計算
    mutate(
      # Stuff runs
      stuff_called_strike_run_cat = avg_called_strike_rate * avg_called_strike_value,
      stuff_called_ball_run_cat = avg_called_ball_rate * avg_called_ball_value,
      stuff_hit_by_pitch_run_cat = avg_hit_by_pitch_rate * avg_hit_by_pitch_value,
      stuff_whiff_run_cat = stuff_whiff_rate_cat * avg_swinging_strike_value,
      stuff_foul_run_cat = stuff_foul_rate_cat * avg_foul_value,
      stuff_bbe_run_cat = stuff_bbe_rate_cat * (-avg_bbe_xrv - pred_catboost_bbe_xrv_bbe_stuff),
      
      # Location runs
      loc_called_strike_run_cat = loc_called_strike_rate_cat * avg_called_strike_value,
      loc_called_ball_run_cat = loc_called_ball_rate_cat * avg_called_ball_value,
      loc_hit_by_pitch_run_cat = loc_hit_by_pitch_rate_cat * avg_hit_by_pitch_value,
      loc_whiff_run_cat = loc_whiff_rate_cat * avg_swinging_strike_value,
      loc_foul_run_cat = loc_foul_rate_cat * avg_foul_value,
      loc_bbe_run_cat = loc_bbe_rate_cat * (-avg_bbe_xrv - pred_catboost_bbe_xrv_bbe_location),
      
      # Pitch runs
      pit_called_strike_run_cat = pit_called_strike_rate_cat * avg_called_strike_value,
      pit_called_ball_run_cat = pit_called_ball_rate_cat * avg_called_ball_value,
      pit_hit_by_pitch_run_cat = pit_hit_by_pitch_rate_cat * avg_hit_by_pitch_value,
      pit_whiff_run_cat = pit_whiff_rate_cat * avg_swinging_strike_value,
      pit_foul_run_cat = pit_foul_rate_cat * avg_foul_value,
      pit_bbe_run_cat = pit_bbe_rate_cat * (-avg_bbe_xrv - pred_catboost_bbe_xrv_bbe_pitch)
    ) %>% 
    
    # 5. 総合Run値の計算
    mutate(
      stuff_overall_run_cat = stuff_called_strike_run_cat + stuff_called_ball_run_cat + 
        stuff_hit_by_pitch_run_cat + stuff_whiff_run_cat + stuff_foul_run_cat + stuff_bbe_run_cat,
      loc_overall_run_cat = loc_called_strike_run_cat + loc_called_ball_run_cat + 
        loc_hit_by_pitch_run_cat + loc_whiff_run_cat + loc_foul_run_cat + loc_bbe_run_cat,
      pit_overall_run_cat = pit_called_strike_run_cat + pit_called_ball_run_cat + 
        pit_hit_by_pitch_run_cat + pit_whiff_run_cat + pit_foul_run_cat + pit_bbe_run_cat
    )
  
  # 6. 投手ごとに集計
  pitchers <- df_processed %>% 
    group_by(pitcher_id) %>% 
    summarise(
      pitches = n(),
      stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = TRUE),
      loc_overall_run_cat = mean(loc_overall_run_cat, na.rm = TRUE),
      pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = TRUE),
      delta_pitcher_run_exp = mean(delta_pitcher_run_exp, na.rm = TRUE),
      .groups = "drop"
    ) %>% 
    filter(pitches >= 1000) %>% 
    left_join(fg_data, by = c("pitcher_id" = "MLBAMID"))
  
  return(list(
    pitch_level_data = df_processed,
    pitcher_summary = pitchers
  ))
}

result_25 <- calculate_pitcher_metrics(df25_with_predictions, train_bbe_data, fg25)
pitchers_25 <- result_25$pitcher_summary
result_24 <- calculate_pitcher_metrics(df24_with_predictions, train_bbe_data, fg24)
pitchers_24 <- result_24$pitcher_summary
result_23 <- calculate_pitcher_metrics(df23_with_predictions, train_bbe_data, fg23)
pitchers_23 <- result_23$pitcher_summary
result_22 <- calculate_pitcher_metrics(df22_with_predictions, train_bbe_data, fg22)
pitchers_22 <- result_22$pitcher_summary
result_21 <- calculate_pitcher_metrics(df21_with_predictions, train_bbe_data, fg21)
pitchers_21 <- result_21$pitcher_summary

pitcher_all <- bind_rows(pitchers_25, pitchers_24, pitchers_23, pitchers_22, pitchers_21)

pitcher_all <- pitcher_all |> 
  select(pitcher_id, Season, pitches, stuff_overall_run_cat, pit_overall_run_cat) |> 
  rename(year = Season)

pitcher_all <- pitcher_all |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

pitcher_all <- pitcher_all |> 
  select(pitcher_id, year, pitches, stuff_rv_70, pitch_rv_150)

write.csv(pitcher_all, "pitch_model_gbdt_2021_2025.csv")

df25_processed <- result_25$pitch_level_data
df24_processed <- result_24$pitch_level_data
df23_processed <- result_23$pitch_level_data
df22_processed <- result_22$pitch_level_data
df21_processed <- result_21$pitch_level_data

batter_25 <- df25_processed |> 
  group_by(batter_id, year) |> 
  summarise(pitches = n(),
            stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = T),
            pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = T),
            woba_fg = mean(woba_fg, na.rm = T))

batter_25 <- batter_25 |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

batter_25 <- batter_25 |> 
  select(batter_id, year, pitches, stuff_rv_70, pitch_rv_150, woba_fg)

batter_24 <- df24_processed |> 
  group_by(batter_id, year) |> 
  summarise(pitches = n(),
            stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = T),
            pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = T),
            woba_fg = mean(woba_fg, na.rm = T))

batter_24 <- batter_24 |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

batter_24 <- batter_24 |> 
  select(batter_id, year, pitches, stuff_rv_70, pitch_rv_150, woba_fg)

batter_23 <- df23_processed |> 
  group_by(batter_id, year) |> 
  summarise(pitches = n(),
            stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = T),
            pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = T),
            woba_fg = mean(woba_fg, na.rm = T))

batter_23 <- batter_23 |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

batter_23 <- batter_23 |> 
  select(batter_id, year, pitches, stuff_rv_70, pitch_rv_150, woba_fg)

batter_22 <- df22_processed |> 
  group_by(batter_id, year) |> 
  summarise(pitches = n(),
            stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = T),
            pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = T),
            woba_fg = mean(woba_fg, na.rm = T))

batter_22 <- batter_22 |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

batter_22 <- batter_22 |> 
  select(batter_id, year, pitches, stuff_rv_70, pitch_rv_150, woba_fg)

batter_21 <- df21_processed |> 
  group_by(batter_id, year) |> 
  summarise(pitches = n(),
            stuff_overall_run_cat = mean(stuff_overall_run_cat, na.rm = T),
            pit_overall_run_cat = mean(pit_overall_run_cat, na.rm = T),
            woba_fg = mean(woba_fg, na.rm = T))

batter_21 <- batter_21 |> 
  mutate(stuff_rv_70 = -round(stuff_overall_run_cat * 70, 3),
         pitch_rv_150 = -round(pit_overall_run_cat * 150, 3))

batter_21 <- batter_21 |> 
  select(batter_id, year, pitches, stuff_rv_70, pitch_rv_150, woba_fg)

batter_all <- bind_rows(batter_21, batter_22, batter_23, batter_24, batter_25)

write.csv(batter_all, "opponent_pitch_model_gbdt_2021_2025.csv")
