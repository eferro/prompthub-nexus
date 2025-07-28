-- Fix security definer functions to have proper search path
CREATE OR REPLACE FUNCTION public.get_user_org_role(user_id UUID, org_id UUID)
RETURNS public.org_role 
LANGUAGE SQL 
SECURITY DEFINER 
STABLE
SET search_path = ''
AS $$
  SELECT role FROM public.organization_members 
  WHERE organization_members.user_id = $1 AND organization_members.org_id = $2;
$$;

CREATE OR REPLACE FUNCTION public.user_is_org_member(user_id UUID, org_id UUID)
RETURNS BOOLEAN 
LANGUAGE SQL 
SECURITY DEFINER 
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members 
    WHERE organization_members.user_id = $1 AND organization_members.org_id = $2
  );
$$;

-- Fix update trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix new user handler function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  public_org_id UUID;
BEGIN
  -- Get the public organization ID
  SELECT id INTO public_org_id 
  FROM public.organizations 
  WHERE is_public = true 
  LIMIT 1;
  
  -- Insert profile
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (
    NEW.id, 
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email)
  );
  
  -- Add user to public organization
  IF public_org_id IS NOT NULL THEN
    INSERT INTO public.organization_members (org_id, user_id, role)
    VALUES (public_org_id, NEW.id, 'viewer');
  END IF;
  
  RETURN NEW;
END;
$$;