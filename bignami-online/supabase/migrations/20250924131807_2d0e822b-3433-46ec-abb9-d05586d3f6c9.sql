-- Fix security warnings by properly dropping and recreating functions with triggers
-- First drop the triggers
DROP TRIGGER IF EXISTS policies_auto_code ON public.policies;
DROP TRIGGER IF EXISTS policy_editions_auto_code ON public.policy_editions;

-- Now drop the functions
DROP FUNCTION IF EXISTS generate_random_code(INTEGER);
DROP FUNCTION IF EXISTS auto_generate_codes();

-- Recreate functions with proper search_path
CREATE OR REPLACE FUNCTION generate_random_code(length INTEGER DEFAULT 8)
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..length LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::INTEGER, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Recreate auto-generate codes function with proper search_path  
CREATE OR REPLACE FUNCTION auto_generate_codes()
RETURNS TRIGGER AS $$
BEGIN
    -- Generate policy code if not provided
    IF TG_TABLE_NAME = 'policies' AND NEW.code IS NULL THEN
        LOOP
            NEW.code := generate_random_code(8);
            IF NOT EXISTS (SELECT 1 FROM policies WHERE code = NEW.code) THEN
                EXIT;
            END IF;
        END LOOP;
    END IF;
    
    -- Generate edition code if not provided
    IF TG_TABLE_NAME = 'policy_editions' AND NEW.code IS NULL THEN
        NEW.code := 'ED' || NEW.year::TEXT;
        
        -- Check for uniqueness within the same policy
        DECLARE
            counter INTEGER := 1;
            base_code TEXT := NEW.code;
        BEGIN
            WHILE EXISTS (
                SELECT 1 FROM policy_editions 
                WHERE code = NEW.code 
                AND policy_id = NEW.policy_id 
                AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
            ) LOOP
                NEW.code := base_code || chr(64 + counter);
                counter := counter + 1;
            END LOOP;
        END;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Recreate the triggers
CREATE TRIGGER policies_auto_code 
    BEFORE INSERT OR UPDATE ON public.policies
    FOR EACH ROW EXECUTE FUNCTION auto_generate_codes();

CREATE TRIGGER policy_editions_auto_code 
    BEFORE INSERT OR UPDATE ON public.policy_editions  
    FOR EACH ROW EXECUTE FUNCTION auto_generate_codes();