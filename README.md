# EcoQuant

Project repository for the EcoQuant apps and supporting tools.

## Layout

- `apps/` - app code and deployment files
- `results/` - model output CSVs and related artifacts
- `discord/activity_feed_bot/` - Discord activity feed bot

## Discord Bot

The activity feed bot lives in `discord/activity_feed_bot`.
It reads its `.env` from that directory and runs with `python bot.py`.
