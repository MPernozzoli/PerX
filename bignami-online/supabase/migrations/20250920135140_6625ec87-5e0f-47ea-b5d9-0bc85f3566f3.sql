-- Add default preferences columns to profiles table
ALTER TABLE public.profiles 
ADD COLUMN default_guarantee text DEFAULT 'Fenomeno Elettrico',
ADD COLUMN default_company text;