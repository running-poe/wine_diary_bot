docker stop wine_diary_bot
docker rm wine_diary_bot
docker build --no-cache -t wine_diary_bot_image .
docker run -d --name wine_diary_bot --restart always --env-file .env -e LOG_LEVEL=debug wine_diary_bot_image
docker logs -f wine_diary_bot