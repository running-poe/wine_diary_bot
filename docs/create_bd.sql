-- ==========================================
-- 1. РАСШИРЕНИЯ И УТИЛИТЫ
-- ==========================================

-- Расширение для генерации UUID (если не включено в Supabase по умолчанию)
create extension if not exists "uuid-ossp";

-- ==========================================
-- 2. СПРАВОЧНИКИ (DICTIONARIES)
-- ==========================================

-- 2.1 Страны
create table if not exists public.ref_countries (
    id smallserial primary key,
    name text unique not null, -- Название страны
    code char(2) -- Буквенный код (RU, FR)
);
comment on table public.ref_countries is 'Справочник стран';

-- 2.2 Регионы
create table if not exists public.ref_regions (
    id smallserial primary key,
    name text not null, -- Название региона
    country_id smallint references public.ref_countries(id), -- Ссылка на страну
    unique(name, country_id) -- Уникальность названия в рамках страны
);
comment on table public.ref_regions is 'Справочник винодельческих регионов';

-- 2.3 Производители
create table if not exists public.ref_producers (
    id serial primary key,
    name text unique not null -- Название производителя/бренда
);
comment on table public.ref_producers is 'Справочник производителей вина';

-- 2.4 Типы вина
create table if not exists public.ref_wine_types (
    id smallserial primary key,
    name text unique not null -- Тип: Белое, Красное, Игристое
);
comment on table public.ref_wine_types is 'Справочник типов вина';

-- 2.5 Сорта винограда
create table if not exists public.ref_grapes (
    id smallserial primary key,
    name text unique not null -- Название сорта
);
comment on table public.ref_grapes is 'Справочник сортов винограда';

-- 2.6 Цвет вина (визуальный)
create table if not exists public.ref_colors (
    id smallserial primary key,
    name text unique not null -- Золотой, Рубиновый и т.д.
);
comment on table public.ref_colors is 'Справочник цветов вина';

-- 2.7 Универсальный справочник уровней (органолептика)
create table if not exists public.ref_levels (
    id smallserial primary key,
    group_name text not null, -- Группа показателя: 'intensity', 'sugar', 'acidity', 'tannins', 'body', 'finish'
    value text not null, -- Значение: 'Низкая', 'Средняя', 'Высокая'
    constraint unique_level unique(group_name, value)
);
create index idx_ref_levels_group on public.ref_levels(group_name);
comment on table public.ref_levels is 'Справочник уровней органолептических свойств';

-- 2.8 Справочник ароматов/вкусов
create table if not exists public.ref_aromas (
    id serial primary key,
    name text unique not null, -- Яблоко, Дуб, Ваниль
    category text -- Категория для UI: 'Фрукты', 'Ягоды', 'Дуб'
);
comment on table public.ref_aromas is 'Справочник дескрипторов ароматов и вкусов';

-- ==========================================
-- 3. ПОЛЬЗОВАТЕЛИ И ПРОФИЛИ
-- ==========================================

-- 3.1 Пользователи (Auth)
create table if not exists public.users (
    id uuid default gen_random_uuid() primary key,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    telegram_id bigint unique, -- ID пользователя в Telegram
    email text -- Email (если будет веб-версия)
);
comment on table public.users is 'Основная таблица пользователей';

-- 3.2 Профили (Social)
create table if not exists public.profiles (
    user_id uuid primary key references public.users(id) on delete cascade,
    updated_at timestamp with time zone default timezone('utc'::text, now()),
    display_name text, -- Отображаемое имя
    avatar_url text, -- Ссылка на аватар
    social_links jsonb, -- JSON со ссылками на соцсети {"instagram": "@user"}
    is_private boolean default true -- Флаг приватности профиля
);
comment on table public.profiles is 'Профили пользователей (социальные данные)';

-- Триггер: Создавать профиль автоматически при создании пользователя
create or replace function public.handle_new_user()
returns trigger as $$ begin
    insert into public.profiles (user_id)
    values (new.id);
    return new;
end;
 $$ language plpgsql security definer;

create trigger on_create_user
    after insert on public.users
    for each row execute function public.handle_new_user();

-- ==========================================
-- 4. ВИНА (WINES)
-- ==========================================

-- 4.1 Паспорт вина
create table if not exists public.wines (
    id uuid default gen_random_uuid() primary key,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    created_by_user_id uuid references public.users(id), -- Кто добавил вино в базу
    
    name text not null, -- Название вина (обязательно)
    
    -- Поля с выбором из справочника ИЛИ ручной ввод
    producer_id integer references public.ref_producers(id),
    producer_custom text, 
    
    country_id smallint references public.ref_countries(id),
    country_custom text,
    
    region_id smallint references public.ref_regions(id),
    region_custom text,
    
    wine_type_id smallint references public.ref_wine_types(id),
    wine_type_custom text
);

-- Constraints: Либо ID, либо Custom, либо ничего (но не оба сразу)
alter table public.wines add constraint check_producer check (num_nonnulls(producer_id, producer_custom) <= 1);
alter table public.wines add constraint check_country check (num_nonnulls(country_id, country_custom) <= 1);
alter table public.wines add constraint check_region check (num_nonnulls(region_id, region_custom) <= 1);
alter table public.wines add constraint check_wine_type check (num_nonnulls(wine_type_id, wine_type_custom) <= 1);

comment on table public.wines is 'Справочник вин (паспорт вина)';

-- 4.2 Цены вина в магазинах
create table if not exists public.wine_prices (
    id serial primary key,
    wine_id uuid not null references public.wines(id) on delete cascade,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    shop_name text not null, -- Название магазина
    shop_url text, -- Ссылка
    price numeric(10, 2) not null, -- Цена
    currency char(3) default 'RUB', -- Валюта
    is_active boolean default true -- Актуальность цены
);
comment on table public.wines is 'История цен на вино в разных магазинах';

-- 4.3 Сорта винограда в вине (Связующая таблица)
create table if not exists public.wine_grapes (
    id serial primary key,
    wine_id uuid not null references public.wines(id) on delete cascade,
    grape_id integer references public.ref_grapes(id),
    grape_custom text, -- Свой сорт
    is_main boolean default false, -- Основной сорт или купажный
    percent integer, -- Процент (если известен)
    constraint check_grape_source check (num_nonnulls(grape_id, grape_custom) = 1) -- Обязательно наличие одного
);
comment on table public.wine_grapes is 'Состав вина (сорта винограда)';

-- ==========================================
-- 5. ДЕГУСТАЦИИ (TASTINGS)
-- ==========================================

-- 5.1 Записи дегустаций
create table if not exists public.tastings (
    id uuid default gen_random_uuid() primary key,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    user_id uuid not null references public.users(id) on delete cascade, -- Кто пробовал
    wine_id uuid not null references public.wines(id) on delete cascade, -- Какое вино
    
    tasting_date date not null, -- Дата дегустации
    vintage integer, -- Винтаж (год урожая)
    purchase_price numeric(10, 2), -- Цена покупки
    purchase_place text, -- Место покупки
    purchase_coords point, -- Координаты на карте
    
    rating numeric(3, 2), -- Оценка (0.00 - 10.00)
    general_comment text, -- Общий комментарий
    
    constraint check_rating_range check (rating >= 0.0 and rating <= 10.0)
);
comment on table public.tastings is 'Записи дегустаций';

-- 5.2 Органолептика
create table if not exists public.tasting_notes (
    id uuid default gen_random_uuid() primary key,
    tasting_id uuid not null references public.tastings(id) on delete cascade,
    
    -- Визуал
    color_id smallint references public.ref_colors(id), color_custom text,
    color_intensity_id smallint references public.ref_levels(id), color_intensity_custom text,
    
    -- Аромат
    aroma_intensity_id smallint references public.ref_levels(id), aroma_intensity_custom text,
    
    -- Вкус
    taste_intensity_id smallint references public.ref_levels(id), taste_intensity_custom text,
    sugar_id smallint references public.ref_levels(id), sugar_custom text,
    acidity_id smallint references public.ref_levels(id), acidity_custom text,
    tannins_id smallint references public.ref_levels(id), tannins_custom text,
    alcohol_id smallint references public.ref_levels(id), alcohol_custom text,
    body_id smallint references public.ref_levels(id), body_custom text,
    finish_id smallint references public.ref_levels(id), finish_custom text
);

-- Constraints для tasting_notes
alter table public.tasting_notes add constraint check_color check (num_nonnulls(color_id, color_custom) <= 1);
alter table public.tasting_notes add constraint check_color_int check (num_nonnulls(color_intensity_id, color_intensity_custom) <= 1);
alter table public.tasting_notes add constraint check_aroma_int check (num_nonnulls(aroma_intensity_id, aroma_intensity_custom) <= 1);
alter table public.tasting_notes add constraint check_taste_int check (num_nonnulls(taste_intensity_id, taste_intensity_custom) <= 1);
alter table public.tasting_notes add constraint check_sugar check (num_nonnulls(sugar_id, sugar_custom) <= 1);
alter table public.tasting_notes add constraint check_acidity check (num_nonnulls(acidity_id, acidity_custom) <= 1);
alter table public.tasting_notes add constraint check_tannins check (num_nonnulls(tannins_id, tannins_custom) <= 1);
alter table public.tasting_notes add constraint check_alcohol check (num_nonnulls(alcohol_id, alcohol_custom) <= 1);
alter table public.tasting_notes add constraint check_body check (num_nonnulls(body_id, body_custom) <= 1);
alter table public.tasting_notes add constraint check_finish check (num_nonnulls(finish_id, finish_custom) <= 1);

comment on table public.tasting_notes is 'Органолептические свойства дегустации';

-- 5.3 Фотографии дегустации
create table if not exists public.tasting_photos (
    id uuid default gen_random_uuid() primary key,
    tasting_id uuid not null references public.tastings(id) on delete cascade,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    image_url text not null, -- URL из Supabase Storage
    is_main boolean default false 
);
create unique index idx_unique_main_photo on public.tasting_photos (tasting_id) where (is_main = true); -- Только одно главное фото
comment on table public.tasting_photos is 'Фотографии к дегустации';

-- 5.4 Теги ароматов/вкусов (Связующая таблица)
create table if not exists public.tasting_aroma_tags (
    id serial primary key,
    note_id uuid not null references public.tasting_notes(id) on delete cascade,
    category text not null, -- Категория: 'primary_red', 'secondary_white'
    aroma_id integer references public.ref_aromas(id),
    aroma_custom text,
    constraint check_aroma_tag_source check (num_nonnulls(aroma_id, aroma_custom) = 1)
);
comment on table public.tasting_aroma_tags is 'Теги ароматов для дегустации';

-- ==========================================
-- 6. СТАТИСТИКА (STATS)
-- ==========================================

-- 6.1 Статистика оценок вина (предрасчет)
create table if not exists public.wine_rating_stats (
    wine_id uuid primary key references public.wines(id) on delete cascade,
    
    ratings_count integer default 0, -- Кол-во оценок
    avg_rating numeric(4, 2), -- Средняя оценка
    min_rating numeric(3, 2), -- Мин оценка
    max_rating numeric(3, 2), -- Макс оценка
    stddev_rating numeric(5, 3), -- Среднеквадратичное отклонение (дисперсия)
    rating_distribution jsonb, -- JSON для гистограммы {"8.0": 5, "9.0": 2}
    updated_at timestamp with time zone default timezone('utc'::text, now())
);
comment on table public.wine_rating_stats is 'Агрегированная статистика оценок вина';

-- 6.2 Личная статистика пользователя по вину
create table if not exists public.user_wine_stats (
    id serial primary key,
    user_id uuid not null references public.users(id) on delete cascade,
    wine_id uuid not null references public.wines(id) on delete cascade,
    tastings_count integer default 0, -- Сколько раз пробовал
    last_tasted_at date, -- Дата последней пробы
    unique(user_id, wine_id)
);
comment on table public.user_wine_stats is 'Статистика пользователя: сколько раз пробовал вино';

-- ==========================================
-- 7. ТРИГГЕРЫ И ФУНКЦИИ (LOGIC)
-- ==========================================

-- Функция обновления статистики вина
create or replace function public.update_wine_rating_stats()
returns trigger as $$ declare
    w_id uuid;
begin
    -- Определяем ID вина
    if tg_op = 'DELETE' then
        w_id := old.wine_id;
    else
        w_id := new.wine_id;
    end if;

    -- Пересчитываем статистику
    insert into public.wine_rating_stats (wine_id, ratings_count, avg_rating, min_rating, max_rating, stddev_rating, rating_distribution, updated_at)
    select 
        t.wine_id,
        count(t.rating),
        avg(t.rating),
        min(t.rating),
        max(t.rating),
        stddev_pop(t.rating),
        jsonb_object_agg(t.rating::text, count(t.rating)),
        now()
    from public.tastings t
    where t.wine_id = w_id and t.rating is not null
    group by t.wine_id
    on conflict (wine_id) do update
    set 
        ratings_count = excluded.ratings_count,
        avg_rating = excluded.avg_rating,
        min_rating = excluded.min_rating,
        max_rating = excluded.max_rating,
        stddev_rating = excluded.stddev_rating,
        rating_distribution = excluded.rating_distribution,
        updated_at = now();

    -- Удаляем запись статистики, если оценок не осталось
    delete from public.wine_rating_stats where wine_id = w_id and ratings_count = 0;

    -- Обновляем личную статистику пользователя
    if tg_op = 'INSERT' then
        insert into public.user_wine_stats (user_id, wine_id, tastings_count, last_tasted_at)
        values (new.user_id, new.wine_id, 1, new.tasting_date)
        on conflict (user_id, wine_id) do update
        set tastings_count = user_wine_stats.tastings_count + 1,
            last_tasted_at = greatest(user_wine_stats.last_tasted_at, new.tasting_date);
    
    elsif tg_op = 'DELETE' then
        update public.user_wine_stats
        set tastings_count = tastings_count - 1
        where user_id = old.user_id and wine_id = old.wine_id;
        
        delete from public.user_wine_stats where tastings_count <= 0;
    end if;

    return null;
end;
 $$ language plpgsql;

-- Триггер на таблицу tastings
create trigger on_tasting_change
after insert or update of rating, wine_id or delete
on public.tastings
for each row
execute function public.update_wine_rating_stats();

-- ==========================================
-- 8. БЕЗОПАСНОСТЬ (RLS)
-- ==========================================

-- Включаем RLS на всех таблицах
alter table public.users enable row level security;
alter table public.profiles enable row level security;
alter table public.wines enable row level security;
alter table public.tastings enable row level security;
alter table public.tasting_notes enable row level security;
alter table public.tasting_photos enable row level security;
alter table public.tasting_aroma_tags enable row level security;
alter table public.wine_rating_stats enable row level security;
alter table public.user_wine_stats enable row level security;
-- Для справочников RLS обычно открыт на чтение
alter table public.ref_countries enable row level security;
alter table public.ref_regions enable row level security;
alter table public.ref_producers enable row level security;
alter table public.ref_wine_types enable row level security;
alter table public.ref_grapes enable row level security;
alter table public.ref_colors enable row level security;
alter table public.ref_levels enable row level security;
alter table public.ref_aromas enable row level security;

-- Пример политик (Open Policy для API доступа при разработке)
CREATE POLICY "Open access" ON public.users FOR ALL USING (true);
CREATE POLICY "Open access" ON public.profiles FOR ALL USING (true);
CREATE POLICY "Open access" ON public.wines FOR ALL USING (true);
CREATE POLICY "Open access" ON public.tastings FOR ALL USING (true);
CREATE POLICY "Open access" ON public.tasting_notes FOR ALL USING (true);
CREATE POLICY "Open access" ON public.tasting_photos FOR ALL USING (true);
CREATE POLICY "Open access" ON public.tasting_aroma_tags FOR ALL USING (true);
CREATE POLICY "Open access" ON public.wine_rating_stats FOR ALL USING (true);
CREATE POLICY "Open access" ON public.user_wine_stats FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_countries FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_regions FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_producers FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_wine_types FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_grapes FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_colors FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_levels FOR ALL USING (true);
CREATE POLICY "Open access" ON public.ref_aromas FOR ALL USING (true);