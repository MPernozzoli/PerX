-- Create storage bucket for policy PDFs
INSERT INTO storage.buckets (id, name, public) VALUES ('policy-pdfs', 'policy-pdfs', true);

-- Create RLS policies for policy PDFs
CREATE POLICY "Users can view policy PDFs" 
ON storage.objects 
FOR SELECT 
USING (bucket_id = 'policy-pdfs');

CREATE POLICY "Authenticated users can upload policy PDFs" 
ON storage.objects 
FOR INSERT 
WITH CHECK (bucket_id = 'policy-pdfs' AND auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can update policy PDFs" 
ON storage.objects 
FOR UPDATE 
USING (bucket_id = 'policy-pdfs' AND auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can delete policy PDFs" 
ON storage.objects 
FOR DELETE 
USING (bucket_id = 'policy-pdfs' AND auth.uid() IS NOT NULL);

-- Add preferences to user_policy_interactions table
ALTER TABLE user_policy_interactions 
ADD COLUMN selected_guarantee_group TEXT DEFAULT 'FE',
ADD COLUMN active_guarantees JSONB DEFAULT '{}'::jsonb,
ADD COLUMN preferences_updated_at TIMESTAMP WITH TIME ZONE DEFAULT now();

-- Create trigger to update preferences timestamp
CREATE OR REPLACE FUNCTION update_preferences_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.preferences_updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_policy_interactions_preferences
BEFORE UPDATE ON user_policy_interactions
FOR EACH ROW
WHEN (OLD.selected_guarantee_group IS DISTINCT FROM NEW.selected_guarantee_group OR 
      OLD.active_guarantees IS DISTINCT FROM NEW.active_guarantees)
EXECUTE FUNCTION update_preferences_timestamp();