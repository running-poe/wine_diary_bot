echo # 1. Полная очистка (контейнеры, образы, кэш сборки)
docker stop wine_diary_bot 
docker rm wine_diary_bot 
docker rmi wine_diary_bot_image
docker builder prune -f

echo # 2. Сборка без кэша
docker build --no-cache -t wine_diary_bot_image .

echo # 3. Запуск
docker run -d --name wine_diary_bot --restart always --env-file .env -e LOG_LEVEL=debug wine_diary_bot_image

echo # 4. Логи
docker logs -f wine_diary_bot