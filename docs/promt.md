Техническое задание: Схема БД WineDiaryBot (Supabase + Elixir/Ecto)
Стек: PostgreSQL (Supabase), Elixir/Phoenix/Ecto.Ключевое требование: Полная совместимость с Ecto. Во всех таблицах должны присутствовать поля inserted_at и updated_at (TIMESTAMP). Использование created_at недопустимо.

1. Структура Справочников (Reference Tables)
Нужны таблицы для нормализации данных. Имена таблиц с префиксом ref_.

ref_countries: Страны (id, name).
ref_regions: Регионы (id, name, country_id).
ref_producers: Производители.
ref_wine_types: Типы вина (Белое, Красное и т.д.).
ref_grapes: Сорта винограда.
ref_colors: Визуальные цвета вина.
ref_levels: Универсальный справочник уровней. Содержит группы (intensity, sugar, acidity, tannins, alcohol, body, finish) и значения (Низкая, Средняя, Высокая).
ref_aromas: Дескрипторы ароматов.
2. Основные Сущности
users: Telegram ID (bigint, unique), UUID PK.
profiles: Социальные данные (связь 1:1 с users).
wines: Паспорт вина. Поддержка гибридного ввода (выбор из справочника ИЛИ ручной ввод *_custom). Проверка через CHECK constraint.
tastings: Запись о дегустации. Оценка (0-10), дата, цена.
tasting_notes: Органолептика. Ссылки на ref_levels и ref_colors.
tasting_aroma_tags: Теги ароматов (M:N связь).
3. Логика и Автоматизация
Триггеры:
Авто-обновление updated_at при любом UPDATE.
Авто-создание profile при создании user.
Пересчет статистики wine_rating_stats при изменении оценок в tastings.
Seeds (Начальные данные):Обязательно заполнить ref_levels базовым набором (sugar: Сухое/Полусухое, acidity: Низкая/Средняя и т.д.), ref_wine_types и ref_colors.
