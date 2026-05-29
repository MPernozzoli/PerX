-- Fix the function with proper search_path security
DROP FUNCTION IF EXISTS update_preferences_timestamp();

CREATE OR REPLACE FUNCTION update_preferences_timestamp()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = ''
LANGUAGE plpgsql AS $$
BEGIN
  NEW.preferences_updated_at = now();
  RETURN NEW;
END;
$$;