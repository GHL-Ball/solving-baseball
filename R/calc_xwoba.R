# calc_xwoba

library(tidyverse)
library(DBI)
library(RSQLite)

# パス設定
DATA_DIR <- Sys.getenv("BASEBALL_DATA_DIR")
DB_PATH  <- file.path(DATA_DIR, "pitch_by_pitch.sqlite")

con <- dbConnect(SQLite(), DB_PATH)
query <- "SELECT * FROM pbp_2021_2025"
df_all <- dbGetQuery(con, query)

dbDisconnect(con)

xwoba_batters <- df_all |> 
  group_by(batter_id, year) |> 
  summarise(pa = sum(woba_denom, na.rm = T),
            woba = round(mean(woba_fg, na.rm = T), 3),
            wobacon = round(mean(woba_fg[description == "hit_into_play"], na.rm = T), 3),
            xwoba_ev_la = round(mean(xwoba2v, na.rm = T), 3),
            xwoba_ev_la_sa = round(mean(xwoba, na.rm = T), 3),
            xwobacon_ev_la = round(mean(xwobacon2v, na.rm = T), 3),
            xwobacon_ev_la_sa = round(mean(xwobacon, na.rm = T), 3)) |> 
  mutate(woba_minus_xwoba_2p = woba - xwoba_ev_la,
         woba_minus_xwoba_3p = woba - xwoba_ev_la_sa,
         xwoba_3p_minus_xwoba_2p = xwoba_ev_la_sa - xwoba_ev_la,
         wobacon_minus_xwobacon_2p = wobacon - xwobacon_ev_la,
         wobacon_minus_xwobacon_3p = wobacon - xwobacon_ev_la_sa,
         xwobacon_3p_minus_xwobacon_2p = xwobacon_ev_la_sa - xwobacon_ev_la) |> 
  filter(pa >= 1)

xwoba_pitchers <- df_all |> 
  group_by(pitcher_id, year) |> 
  summarise(pa = sum(woba_denom, na.rm = T),
            woba = round(mean(woba_fg, na.rm = T), 3),
            wobacon = round(mean(woba_fg[description == "hit_into_play"], na.rm = T), 3),
            xwoba_ev_la = round(mean(xwoba2v, na.rm = T), 3),
            xwoba_ev_la_sa = round(mean(xwoba, na.rm = T), 3),
            xwobacon_ev_la = round(mean(xwobacon2v, na.rm = T), 3),
            xwobacon_ev_la_sa = round(mean(xwobacon, na.rm = T), 3)) |> 
  mutate(woba_minus_xwoba_2p = woba - xwoba_ev_la,
         woba_minus_xwoba_3p = woba - xwoba_ev_la_sa,
         xwoba_3p_minus_xwoba_2p = xwoba_ev_la_sa - xwoba_ev_la,
         wobacon_minus_xwobacon_2p = wobacon - xwobacon_ev_la,
         wobacon_minus_xwobacon_3p = wobacon - xwobacon_ev_la_sa,
         xwobacon_3p_minus_xwobacon_2p = xwobacon_ev_la_sa - xwobacon_ev_la) |> 
  filter(pa >= 1)

write.csv(xwoba_batters, "xwoba_bat_2021_2025.csv", row.names = F)
write.csv(xwoba_pitchers, "xwoba_pit_2021_2025.csv", row.names = F)
