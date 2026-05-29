-- Update profiles table default for guarantee to use code instead of full name
ALTER TABLE public.profiles 
ALTER COLUMN default_guarantee SET DEFAULT 'FE';