-- Create newsletter subscribers table
CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  company TEXT,
  subscribed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Enable Row Level Security
ALTER TABLE public.newsletter_subscribers ENABLE ROW LEVEL SECURITY;

-- Create policy to allow inserts from edge functions (service role)
CREATE POLICY "Allow service role to insert newsletter subscribers"
ON public.newsletter_subscribers
FOR INSERT
TO service_role
WITH CHECK (true);

-- Create policy to allow service role to read newsletter subscribers
CREATE POLICY "Allow service role to read newsletter subscribers"
ON public.newsletter_subscribers
FOR SELECT
TO service_role
USING (true);

-- Create index for faster email lookups
CREATE INDEX idx_newsletter_subscribers_email ON public.newsletter_subscribers(email);
CREATE INDEX idx_newsletter_subscribers_active ON public.newsletter_subscribers(is_active) WHERE is_active = true;