-- Add code fields for better URL structure
-- Add company code to companies table
ALTER TABLE public.companies 
ADD COLUMN code TEXT;

-- Add unique policy code to policies table  
ALTER TABLE public.policies
ADD COLUMN code TEXT;

-- Add edition code to policy_editions table
ALTER TABLE public.policy_editions
ADD COLUMN code TEXT;

-- Create function to generate random alphanumeric codes
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
$$ LANGUAGE plpgsql;

-- Update existing records with generated codes
UPDATE public.companies 
SET code = CASE 
    WHEN name ILIKE '%cattolica%' THEN 'CAT'
    WHEN name ILIKE '%generali%' THEN 'GEN' 
    WHEN name ILIKE '%unipol%' THEN 'UNI'
    WHEN name ILIKE '%zurich%' THEN 'ZUR'
    ELSE UPPER(LEFT(name, 3))
END;

-- Generate unique codes for existing policies
DO $$
DECLARE
    policy_record RECORD;
    new_code TEXT;
BEGIN
    FOR policy_record IN SELECT id FROM policies WHERE code IS NULL
    LOOP
        LOOP
            new_code := generate_random_code(8);
            -- Check if code already exists
            IF NOT EXISTS (SELECT 1 FROM policies WHERE code = new_code) THEN
                EXIT;
            END IF;
        END LOOP;
        
        UPDATE policies SET code = new_code WHERE id = policy_record.id;
    END LOOP;
END;
$$;

-- Generate codes for existing policy editions
DO $$
DECLARE
    edition_record RECORD;
    new_code TEXT;
BEGIN
    FOR edition_record IN SELECT id, year FROM policy_editions WHERE code IS NULL
    LOOP
        new_code := 'ED' || edition_record.year::TEXT;
        
        -- If code already exists for same policy, add suffix
        DECLARE
            counter INTEGER := 1;
            base_code TEXT := new_code;
        BEGIN
            WHILE EXISTS (
                SELECT 1 FROM policy_editions pe 
                JOIN policies p ON pe.policy_id = p.id 
                WHERE pe.code = new_code 
                AND pe.id != edition_record.id
            ) LOOP
                new_code := base_code || chr(64 + counter); -- A, B, C...
                counter := counter + 1;
            END LOOP;
        END;
        
        UPDATE policy_editions SET code = new_code WHERE id = edition_record.id;
    END LOOP;
END;
$$;

-- Add unique constraints
ALTER TABLE public.companies 
ADD CONSTRAINT companies_code_unique UNIQUE (code);

ALTER TABLE public.policies
ADD CONSTRAINT policies_code_unique UNIQUE (code);

-- Add constraint for unique edition code per policy
ALTER TABLE public.policy_editions
ADD CONSTRAINT policy_editions_code_policy_unique UNIQUE (policy_id, code);

-- Make codes required for new records
ALTER TABLE public.companies 
ALTER COLUMN code SET NOT NULL;

ALTER TABLE public.policies
ALTER COLUMN code SET NOT NULL;

ALTER TABLE public.policy_editions
ALTER COLUMN code SET NOT NULL;

-- Create function to auto-generate codes on insert
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
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER policies_auto_code 
    BEFORE INSERT OR UPDATE ON public.policies
    FOR EACH ROW EXECUTE FUNCTION auto_generate_codes();

CREATE TRIGGER policy_editions_auto_code 
    BEFORE INSERT OR UPDATE ON public.policy_editions  
    FOR EACH ROW EXECUTE FUNCTION auto_generate_codes();