-- Create enum for organization member roles
CREATE TYPE public.org_role AS ENUM ('owner', 'admin', 'viewer');

-- Create organizations table
CREATE TABLE public.organizations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  is_public BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create organization members table
CREATE TABLE public.organization_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.org_role NOT NULL DEFAULT 'viewer',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(org_id, user_id)
);

-- Create prompts table
CREATE TABLE public.prompts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(org_id, name)
);

-- Create prompt variants table
CREATE TABLE public.prompt_variants (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  prompt_id UUID NOT NULL REFERENCES public.prompts(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  notes TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create prompt arguments table
CREATE TABLE public.prompt_arguments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  prompt_id UUID NOT NULL REFERENCES public.prompts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  required BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(prompt_id, name)
);

-- Create API keys table (store hashed keys for security)
CREATE TABLE public.api_keys (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  revoked_at TIMESTAMP WITH TIME ZONE,
  last_used_at TIMESTAMP WITH TIME ZONE
);

-- Create profiles table for additional user data
CREATE TABLE public.profiles (
  id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  display_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on all tables
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_arguments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Security definer functions to prevent RLS recursion
CREATE OR REPLACE FUNCTION public.get_user_org_role(user_id UUID, org_id UUID)
RETURNS public.org_role AS $$
  SELECT role FROM public.organization_members 
  WHERE organization_members.user_id = $1 AND organization_members.org_id = $2;
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.user_is_org_member(user_id UUID, org_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members 
    WHERE organization_members.user_id = $1 AND organization_members.org_id = $2
  );
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- RLS Policies for organizations
CREATE POLICY "Users can view orgs they belong to" 
ON public.organizations FOR SELECT 
USING (public.user_is_org_member(auth.uid(), id) OR is_public = true);

CREATE POLICY "Only owners can create organizations" 
ON public.organizations FOR INSERT 
WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Only owners can update their organizations" 
ON public.organizations FOR UPDATE 
USING (public.get_user_org_role(auth.uid(), id) = 'owner');

-- RLS Policies for organization members
CREATE POLICY "Users can view members of orgs they belong to" 
ON public.organization_members FOR SELECT 
USING (public.user_is_org_member(auth.uid(), org_id));

CREATE POLICY "Only owners can manage members" 
ON public.organization_members FOR ALL 
USING (public.get_user_org_role(auth.uid(), org_id) = 'owner');

-- RLS Policies for prompts
CREATE POLICY "Users can view prompts in orgs they belong to" 
ON public.prompts FOR SELECT 
USING (public.user_is_org_member(auth.uid(), org_id));

CREATE POLICY "Admins and owners can create prompts" 
ON public.prompts FOR INSERT 
WITH CHECK (
  auth.uid() = creator_id AND 
  public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner')
);

CREATE POLICY "Admins and owners can update prompts" 
ON public.prompts FOR UPDATE 
USING (public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner'));

CREATE POLICY "Admins and owners can delete prompts" 
ON public.prompts FOR DELETE 
USING (public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner'));

-- RLS Policies for prompt variants
CREATE POLICY "Users can view variants of accessible prompts" 
ON public.prompt_variants FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_variants.prompt_id 
    AND public.user_is_org_member(auth.uid(), prompts.org_id)
  )
);

CREATE POLICY "Admins and owners can manage variants" 
ON public.prompt_variants FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_variants.prompt_id 
    AND public.get_user_org_role(auth.uid(), prompts.org_id) IN ('admin', 'owner')
  )
);

-- RLS Policies for prompt arguments
CREATE POLICY "Users can view arguments of accessible prompts" 
ON public.prompt_arguments FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_arguments.prompt_id 
    AND public.user_is_org_member(auth.uid(), prompts.org_id)
  )
);

CREATE POLICY "Admins and owners can manage arguments" 
ON public.prompt_arguments FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_arguments.prompt_id 
    AND public.get_user_org_role(auth.uid(), prompts.org_id) IN ('admin', 'owner')
  )
);

-- RLS Policies for API keys
CREATE POLICY "Users can manage their own API keys" 
ON public.api_keys FOR ALL 
USING (auth.uid() = user_id);

-- RLS Policies for profiles
CREATE POLICY "Users can view all profiles" 
ON public.profiles FOR SELECT 
USING (true);

CREATE POLICY "Users can manage their own profile" 
ON public.profiles FOR ALL 
USING (auth.uid() = id);

-- Create update triggers for timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_prompts_updated_at
  BEFORE UPDATE ON public.prompts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_prompt_variants_updated_at
  BEFORE UPDATE ON public.prompt_variants
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create the default public organization
INSERT INTO public.organizations (name, is_public) 
VALUES ('Public Organization', true);

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();