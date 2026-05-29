-- Fix RLS policies for companies table to allow authenticated users to create companies
DROP POLICY IF EXISTS "Authenticated users can manage companies" ON public.companies;

-- Create a proper policy for authenticated users to manage companies
CREATE POLICY "Authenticated users can manage companies" 
ON public.companies 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Also ensure policies table has proper RLS
DROP POLICY IF EXISTS "Authenticated users can manage policies" ON public.policies;

CREATE POLICY "Authenticated users can manage policies" 
ON public.policies 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- And policy_editions table
DROP POLICY IF EXISTS "Authenticated users can manage policy editions" ON public.policy_editions;

CREATE POLICY "Authenticated users can manage policy editions" 
ON public.policy_editions 
FOR ALL 
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);