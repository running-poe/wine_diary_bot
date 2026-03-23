-- ==========================================
-- 0. ПОЛНАЯ ОЧИСТКА БАЗЫ ДАННЫХ
-- ==========================================

-- Удаляем основные таблицы
DROP TABLE IF EXISTS public.tasting_aroma_tags CASCADE;
DROP TABLE IF EXISTS public.tasting_photos CASCADE;
DROP TABLE IF EXISTS public.tasting_notes CASCADE;
DROP TABLE IF EXISTS public.tastings CASCADE;
DROP TABLE IF EXISTS public.wine_rating_stats CASCADE;
DROP TABLE IF EXISTS public.user_wine_stats CASCADE;
DROP TABLE IF EXISTS public.wine_grapes CASCADE;
DROP TABLE IF EXISTS public.wine_prices CASCADE;
DROP TABLE IF EXISTS public.wines CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- Удаляем справочники
DROP TABLE IF EXISTS public.ref_aromas CASCADE;
DROP TABLE IF EXISTS public.ref_levels CASCADE;
DROP TABLE IF EXISTS public.ref_colors CASCADE;
DROP TABLE IF EXISTS public.ref_grapes CASCADE;
DROP TABLE IF EXISTS public.ref_wine_types CASCADE;
DROP TABLE IF EXISTS public.ref_producers CASCADE;
DROP TABLE IF EXISTS public.ref_regions CASCADE;
DROP TABLE IF EXISTS public.ref_countries CASCADE;

-- Удаляем функции
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.update_wine_rating_stats() CASCADE;

-- ==========================================
-- 1. УТИЛИТЫ
-- ==========================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Функция автообновления updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$ BEGIN
    NEW.updated_at = NOW(); -- NOW() возвращает timestamp, совместимый с Ecto
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql;

-- ==========================================
-- 2. СПРАВОЧНИКИ (DICTIONARIES)
-- ==========================================

-- Используем TIMESTAMP (WITHOUT TIME ZONE) для совместимости с Ecto NaiveDateTime

-- 2.1 Страны
CREATE TABLE IF NOT EXISTS public.ref_countries (
    id SMALLSERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    code CHAR(2),
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_countries IS 'Справочник стран';

-- 2.2 Регионы
CREATE TABLE IF NOT EXISTS public.ref_regions (
    id SMALLSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    country_id SMALLINT REFERENCES public.ref_countries(id),
    UNIQUE(name, country_id),
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_regions IS 'Справочник регионов';

-- 2.3 Производители
CREATE TABLE IF NOT EXISTS public.ref_producers (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_producers IS 'Справочник производителей';

-- 2.4 Типы вина
CREATE TABLE IF NOT EXISTS public.ref_wine_types (
    id SMALLSERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_wine_types IS 'Типы вина';

-- 2.5 Сорта винограда
CREATE TABLE IF NOT EXISTS public.ref_grapes (
    id SMALLSERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_grapes IS 'Сорта винограда';

-- 2.6 Цвет вина
CREATE TABLE IF NOT EXISTS public.ref_colors (
    id SMALLSERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_colors IS 'Цвета вина';

-- 2.7 Уровни (органолептика)
CREATE TABLE IF NOT EXISTS public.ref_levels (
    id SMALLSERIAL PRIMARY KEY,
    group_name TEXT NOT NULL, -- intensity, sugar, acidity, etc.
    value TEXT NOT NULL,
    CONSTRAINT unique_level UNIQUE(group_name, value),
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ref_levels_group ON public.ref_levels(group_name);
COMMENT ON TABLE public.ref_levels IS 'Уровни органолептики';

-- 2.8 Ароматы
CREATE TABLE IF NOT EXISTS public.ref_aromas (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    category TEXT,
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE public.ref_aromas IS 'Справочник ароматов';

-- Триггеры для справочников
CREATE TRIGGER update_ref_countries_updated_at BEFORE UPDATE ON public.ref_countries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_regions_updated_at BEFORE UPDATE ON public.ref_regions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_producers_updated_at BEFORE UPDATE ON public.ref_producers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_wine_types_updated_at BEFORE UPDATE ON public.ref_wine_types FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_grapes_updated_at BEFORE UPDATE ON public.ref_grapes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_colors_updated_at BEFORE UPDATE ON public.ref_colors FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_levels_updated_at BEFORE UPDATE ON public.ref_levels FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_ref_aromas_updated_at BEFORE UPDATE ON public.ref_aromas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ==========================================
-- 3. ПОЛЬЗОВАТЕЛИ
-- ==========================================

CREATE TABLE IF NOT EXISTS public.users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- ИСПРАВЛЕНО: TIMESTAMP WITHOUT TIME ZONE
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    telegram_id BIGINT UNIQUE,
    email TEXT
);
COMMENT ON TABLE public.users IS 'Пользователи';
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    display_name TEXT,
    avatar_url TEXT,
    social_links JSONB,
    is_private BOOLEAN DEFAULT TRUE
);
COMMENT ON TABLE public.profiles IS 'Профили';
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Триггер создания профиля
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$ BEGIN
    INSERT INTO public.profiles (user_id) VALUES (NEW.id);
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_create_user
    AFTER INSERT ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==========================================
-- 4. ВИНА
-- ==========================================

CREATE TABLE IF NOT EXISTS public.wines (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_by_user_id UUID REFERENCES public.users(id),
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    name TEXT NOT NULL,
    
    producer_id INTEGER REFERENCES public.ref_producers(id),
    producer_custom TEXT,
    
    country_id SMALLINT REFERENCES public.ref_countries(id),
    country_custom TEXT,
    
    region_id SMALLINT REFERENCES public.ref_regions(id),
    region_custom TEXT,
    
    wine_type_id SMALLINT REFERENCES public.ref_wine_types(id),
    wine_type_custom TEXT
);

ALTER TABLE public.wines ADD CONSTRAINT check_producer CHECK (num_nonnulls(producer_id, producer_custom) <= 1);
ALTER TABLE public.wines ADD CONSTRAINT check_country CHECK (num_nonnulls(country_id, country_custom) <= 1);
ALTER TABLE public.wines ADD CONSTRAINT check_region CHECK (num_nonnulls(region_id, region_custom) <= 1);
ALTER TABLE public.wines ADD CONSTRAINT check_wine_type CHECK (num_nonnulls(wine_type_id, wine_type_custom) <= 1);

CREATE TRIGGER update_wines_updated_at BEFORE UPDATE ON public.wines FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
COMMENT ON TABLE public.wines IS 'Каталог вин';

CREATE TABLE IF NOT EXISTS public.wine_prices (
    id SERIAL PRIMARY KEY,
    wine_id UUID NOT NULL REFERENCES public.wines(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    shop_name TEXT NOT NULL,
    shop_url TEXT,
    price NUMERIC(10, 2) NOT NULL,
    currency CHAR(3) DEFAULT 'RUB',
    is_active BOOLEAN DEFAULT TRUE
);
CREATE TRIGGER update_wine_prices_updated_at BEFORE UPDATE ON public.wine_prices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.wine_grapes (
    id SERIAL PRIMARY KEY,
    wine_id UUID NOT NULL REFERENCES public.wines(id) ON DELETE CASCADE,
    grape_id INTEGER REFERENCES public.ref_grapes(id),
    grape_custom TEXT,
    is_main BOOLEAN DEFAULT FALSE,
    percent INTEGER,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT check_grape_source CHECK (num_nonnulls(grape_id, grape_custom) = 1)
);
CREATE TRIGGER update_wine_grapes_updated_at BEFORE UPDATE ON public.wine_grapes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ==========================================
-- 5. ДЕГУСТАЦИИ
-- ==========================================

CREATE TABLE IF NOT EXISTS public.tastings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    wine_id UUID NOT NULL REFERENCES public.wines(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    tasting_date DATE NOT NULL,
    vintage INTEGER,
    purchase_price NUMERIC(10, 2),
    purchase_place TEXT,
    purchase_coords POINT,
    
    rating NUMERIC(3, 2), -- 0-10
    general_comment TEXT,
    
    CONSTRAINT check_rating_range CHECK (rating >= 0.0 AND rating <= 10.0)
);
CREATE TRIGGER update_tastings_updated_at BEFORE UPDATE ON public.tastings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasting_notes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tasting_id UUID NOT NULL REFERENCES public.tastings(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    color_id SMALLINT REFERENCES public.ref_colors(id), color_custom TEXT,
    color_intensity_id SMALLINT REFERENCES public.ref_levels(id), color_intensity_custom TEXT,
    
    aroma_intensity_id SMALLINT REFERENCES public.ref_levels(id), aroma_intensity_custom TEXT,
    
    taste_intensity_id SMALLINT REFERENCES public.ref_levels(id), taste_intensity_custom TEXT,
    sugar_id SMALLINT REFERENCES public.ref_levels(id), sugar_custom TEXT,
    acidity_id SMALLINT REFERENCES public.ref_levels(id), acidity_custom TEXT,
    tannins_id SMALLINT REFERENCES public.ref_levels(id), tannins_custom TEXT,
    alcohol_id SMALLINT REFERENCES public.ref_levels(id), alcohol_custom TEXT,
    body_id SMALLINT REFERENCES public.ref_levels(id), body_custom TEXT,
    finish_id SMALLINT REFERENCES public.ref_levels(id), finish_custom TEXT
);

ALTER TABLE public.tasting_notes ADD CONSTRAINT check_color CHECK (num_nonnulls(color_id, color_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_color_int CHECK (num_nonnulls(color_intensity_id, color_intensity_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_aroma_int CHECK (num_nonnulls(aroma_intensity_id, aroma_intensity_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_taste_int CHECK (num_nonnulls(taste_intensity_id, taste_intensity_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_sugar CHECK (num_nonnulls(sugar_id, sugar_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_acidity CHECK (num_nonnulls(acidity_id, acidity_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_tannins CHECK (num_nonnulls(tannins_id, tannins_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_alcohol CHECK (num_nonnulls(alcohol_id, alcohol_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_body CHECK (num_nonnulls(body_id, body_custom) <= 1);
ALTER TABLE public.tasting_notes ADD CONSTRAINT check_finish CHECK (num_nonnulls(finish_id, finish_custom) <= 1);

CREATE TRIGGER update_tasting_notes_updated_at BEFORE UPDATE ON public.tasting_notes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasting_photos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tasting_id UUID NOT NULL REFERENCES public.tastings(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    image_url TEXT NOT NULL,
    is_main BOOLEAN DEFAULT FALSE
);
CREATE UNIQUE INDEX idx_unique_main_photo ON public.tasting_photos (tasting_id) WHERE (is_main = TRUE);
CREATE TRIGGER update_tasting_photos_updated_at BEFORE UPDATE ON public.tasting_photos FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasting_aroma_tags (
    id SERIAL PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES public.tasting_notes(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    aroma_id INTEGER REFERENCES public.ref_aromas(id),
    aroma_custom TEXT,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT check_aroma_tag_source CHECK (num_nonnulls(aroma_id, aroma_custom) = 1)
);
CREATE TRIGGER update_tasting_aroma_tags_updated_at BEFORE UPDATE ON public.tasting_aroma_tags FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ==========================================
-- 6. СТАТИСТИКА
-- ==========================================

CREATE TABLE IF NOT EXISTS public.wine_rating_stats (
    wine_id UUID PRIMARY KEY REFERENCES public.wines(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    ratings_count INTEGER DEFAULT 0,
    avg_rating NUMERIC(4, 2),
    min_rating NUMERIC(3, 2),
    max_rating NUMERIC(3, 2),
    stddev_rating NUMERIC(5, 3),
    rating_distribution JSONB
);
CREATE TRIGGER update_wine_rating_stats_updated_at BEFORE UPDATE ON public.wine_rating_stats FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_wine_stats (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    wine_id UUID NOT NULL REFERENCES public.wines(id) ON DELETE CASCADE,
    
    inserted_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    tastings_count INTEGER DEFAULT 0,
    last_tasted_at DATE,
    UNIQUE(user_id, wine_id)
);
CREATE TRIGGER update_user_wine_stats_updated_at BEFORE UPDATE ON public.user_wine_stats FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ==========================================
-- 7. ТРИГГЕРЫ ЛОГИКИ
-- ==========================================

CREATE OR REPLACE FUNCTION public.update_wine_rating_stats()
RETURNS TRIGGER AS $$ DECLARE
    w_id UUID;
BEGIN
    -- Определяем ID вина
    IF TG_OP = 'DELETE' THEN 
        w_id := OLD.wine_id; 
    ELSE 
        w_id := NEW.wine_id; 
    END IF;

    -- Пересчет статистики
    INSERT INTO public.wine_rating_stats (
        wine_id, ratings_count, avg_rating, min_rating, max_rating, 
        stddev_rating, rating_distribution, updated_at
    )
    SELECT
        t.wine_id,
        COUNT(t.rating),
        AVG(t.rating),
        MIN(t.rating),
        MAX(t.rating),
        STDDEV_POP(t.rating),
        -- ИСПРАВЛЕНО: Расчет распределения через подзапрос
        -- Сначала группируем по оценкам, считаем количество, потом собираем JSON
        (SELECT jsonb_object_agg(sub.rating::text, sub.cnt)
         FROM (
             SELECT rating, COUNT(*) as cnt
             FROM public.tastings t_sub
             WHERE t_sub.wine_id = w_id AND t_sub.rating IS NOT NULL
             GROUP BY rating
         ) sub
        ),
        NOW()
    FROM public.tastings t
    WHERE t.wine_id = w_id AND t.rating IS NOT NULL
    GROUP BY t.wine_id
    ON CONFLICT (wine_id) DO UPDATE
    SET 
        ratings_count = EXCLUDED.ratings_count,
        avg_rating = EXCLUDED.avg_rating,
        min_rating = EXCLUDED.min_rating,
        max_rating = EXCLUDED.max_rating,
        stddev_rating = EXCLUDED.stddev_rating,
        rating_distribution = EXCLUDED.rating_distribution,
        updated_at = NOW();

    -- Удаляем статистику, если оценок не осталось
    DELETE FROM public.wine_rating_stats WHERE wine_id = w_id AND ratings_count = 0;

    -- Обновление личной статистики пользователя
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.user_wine_stats (user_id, wine_id, tastings_count, last_tasted_at, updated_at)
        VALUES (NEW.user_id, NEW.wine_id, 1, NEW.tasting_date, NOW())
        ON CONFLICT (user_id, wine_id) DO UPDATE
        SET 
            tastings_count = user_wine_stats.tastings_count + 1,
            last_tasted_at = GREATEST(user_wine_stats.last_tasted_at, NEW.tasting_date),
            updated_at = NOW();
    
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.user_wine_stats
        SET tastings_count = tastings_count - 1, updated_at = NOW()
        WHERE user_id = OLD.user_id AND wine_id = OLD.wine_id;
        
        DELETE FROM public.user_wine_stats WHERE tastings_count <= 0;
    END IF;

    RETURN NULL;
END;
 $$ LANGUAGE plpgsql;

CREATE TRIGGER on_tasting_change
AFTER INSERT OR UPDATE OF rating, wine_id OR DELETE
ON public.tastings
FOR EACH ROW
EXECUTE FUNCTION public.update_wine_rating_stats();

-- ==========================================
-- 8. БЕЗОПАСНОСТЬ (RLS)
-- ==========================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tastings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasting_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasting_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasting_aroma_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wine_rating_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_wine_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_producers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_wine_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_grapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_colors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ref_aromas ENABLE ROW LEVEL SECURITY;

DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' LOOP
        EXECUTE format('CREATE POLICY "Open access" ON public.%I FOR ALL USING (true)', r.table_name);
    END LOOP;
END $$;

-- ==========================================
-- 9. НАЧАЛЬНОЕ ЗАПОЛНЕНИЕ (SEEDS)
-- ==========================================

INSERT INTO public.ref_levels (group_name, value) VALUES
('intensity', 'Легкая'), ('intensity', 'Средняя'), ('intensity', 'Выраженная'), ('intensity', 'Глубокий'),
('sugar', 'Сухое'), ('sugar', 'Полусухое'), ('sugar', 'Полусладкое'), ('sugar', 'Сладкое'),
('acidity', 'Низкая'), ('acidity', 'Средняя'), ('acidity', 'Высокая'),
('tannins', 'Низкие'), ('tannins', 'Средние'), ('tannins', 'Высокие'),
('alcohol', 'Низкий'), ('alcohol', 'Средний'), ('alcohol', 'Высокий'),
('body', 'Легкое'), ('body', 'Среднее'), ('body', 'Полное'),
('finish', 'Короткое'), ('finish', 'Среднее'), ('finish', 'Долгое');

INSERT INTO public.ref_wine_types (name) VALUES 
('Белое тихое'), ('Красное тихое'), ('Розовое тихое'), ('Игристое'), ('Оранжевое'), ('Десертное');

INSERT INTO public.ref_colors (name) VALUES 
('Золотой'), ('Лимонный'), ('Гранатовый'), ('Рубиновый'), ('Кирпичный'), ('Розовый'), ('Соломенный');