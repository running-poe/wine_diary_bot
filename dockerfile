# ==========================================
# Этап 1: Сборка (Builder)
# ==========================================
FROM hexpm/elixir:1.16.3-erlang-26.2.5-alpine-3.20.1 AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

# Копируем файл зависимостей
COPY mix.exs ./

# Скачиваем зависимости (только prod)
RUN mix deps.get --only prod

# Компилируем зависимости
RUN mix deps.compile

# Копируем исходный код
COPY lib lib
COPY config config

# Сборка релиза
RUN MIX_ENV=prod mix release

# ==========================================
# Этап 2: Запуск (Runner)
# ==========================================
FROM alpine:3.20.1

RUN apk add --no-cache \
    openssl \
    ncurses \
    imagemagick \
    libjpeg-turbo \
    libpng \
    libstdc++ \
    curl

WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder --chown=appuser:appgroup /app/_build/prod/rel/wine_diary_bot ./

USER appuser

CMD ["bin/wine_diary_bot", "start"]