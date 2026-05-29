-- Fix the function with proper search_path security
DROP TRIGGER IF EXISTS update_user_policy_interactions_preferences ON user_policy_interactions;
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

-- Recreate the trigger
CREATE TRIGGER update_user_policy_interactions_preferences
BEFORE UPDATE ON user_policy_interactions
FOR EACH ROW
WHEN (OLD.selected_guarantee_group IS DISTINCT FROM NEW.selected_guarantee_group OR 
      OLD.active_guarantees IS DISTINCT FROM NEW.active_guarantees)
EXECUTE FUNCTION update_preferences_timestamp();