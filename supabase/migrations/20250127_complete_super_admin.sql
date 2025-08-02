-- Complete Super Admin Role Implementation
-- This migration fixes the incomplete super admin system

-- 1. Add super_admin to the org_role enum if not already present
DO $$ 
BEGIN
    -- Check if super_admin value exists in enum
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'super_admin' 
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'org_role')
    ) THEN
        ALTER TYPE public.org_role ADD VALUE 'super_admin';
    END IF;
END $$;

-- 2. Create the is_super_admin function
CREATE OR REPLACE FUNCTION public.is_super_admin(user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN 
LANGUAGE SQL 
SECURITY DEFINER 
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members 
    WHERE organization_members.user_id = COALESCE($1, auth.uid()) 
    AND role = 'super_admin'
  );
$$;

-- 3. Create invitations table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.invitations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  role public.org_role NOT NULL,
  org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
  invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  used_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on invitations table
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

-- 4. Update organization creation policy - ONLY super admin can create organizations
DROP POLICY IF EXISTS "Only owners can create organizations" ON public.organizations;
DROP POLICY IF EXISTS "Super admins can create organizations" ON public.organizations;

CREATE POLICY "Only super admin can create organizations" 
ON public.organizations FOR INSERT 
WITH CHECK (public.is_super_admin());

-- 5. Update organization management policies to include super admin
DROP POLICY IF EXISTS "Only owners can update their organizations" ON public.organizations;
CREATE POLICY "Super admin and owners can update organizations" 
ON public.organizations FOR UPDATE 
USING (public.is_super_admin() OR public.get_user_org_role(auth.uid(), id) = 'owner');

DROP POLICY IF EXISTS "Only owners can manage members" ON public.organization_members;
CREATE POLICY "Super admin and owners can manage members" 
ON public.organization_members FOR ALL 
USING (public.is_super_admin() OR public.get_user_org_role(auth.uid(), org_id) = 'owner');

-- 6. Create invitation policies - ONLY super admin can create invitations
CREATE POLICY "Only super admin can create invitations" 
ON public.invitations FOR INSERT 
WITH CHECK (public.is_super_admin());

CREATE POLICY "Super admin can view all invitations" 
ON public.invitations FOR SELECT 
USING (public.is_super_admin());

CREATE POLICY "Super admin can update invitations" 
ON public.invitations FOR UPDATE 
USING (public.is_super_admin());

CREATE POLICY "Super admin can delete invitations" 
ON public.invitations FOR DELETE 
USING (public.is_super_admin());

-- 7. Create function to generate invitation tokens
CREATE OR REPLACE FUNCTION public.generate_invitation_token()
RETURNS TEXT 
LANGUAGE SQL 
SECURITY DEFINER
AS $$
  SELECT encode(gen_random_bytes(32), 'base64');
$$;

-- 8. Create function to handle invitation signup
CREATE OR REPLACE FUNCTION public.handle_invitation_signup()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  invitation_record RECORD;
  public_org_id UUID;
BEGIN
  -- Check if user was invited
  SELECT * INTO invitation_record 
  FROM public.invitations 
  WHERE email = NEW.email 
  AND used_at IS NULL 
  AND expires_at > now()
  ORDER BY created_at DESC 
  LIMIT 1;
  
  IF invitation_record IS NOT NULL THEN
    -- Mark invitation as used
    UPDATE public.invitations 
    SET used_at = now() 
    WHERE id = invitation_record.id;
    
    -- Create profile
    INSERT INTO public.profiles (id, email, display_name)
    VALUES (
      NEW.id, 
      NEW.email,
      COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email)
    );
    
    -- Add user to organization with invited role
    IF invitation_record.org_id IS NOT NULL THEN
      INSERT INTO public.organization_members (org_id, user_id, role)
      VALUES (invitation_record.org_id, NEW.id, invitation_record.role);
    ELSE
      -- For super admin invitation, add to all organizations or create if needed
      IF invitation_record.role = 'super_admin' THEN
        -- Get or create public organization
        SELECT id INTO public_org_id 
        FROM public.organizations 
        WHERE is_public = true 
        LIMIT 1;
        
        IF public_org_id IS NULL THEN
          INSERT INTO public.organizations (name, is_public) 
          VALUES ('Public Organization', true)
          RETURNING id INTO public_org_id;
        END IF;
        
        -- Add super admin to public organization
        INSERT INTO public.organization_members (org_id, user_id, role)
        VALUES (public_org_id, NEW.id, 'super_admin');
      END IF;
    END IF;
  ELSE
    -- Regular user signup - add to public org as viewer
    SELECT id INTO public_org_id 
    FROM public.organizations 
    WHERE is_public = true 
    LIMIT 1;
    
    INSERT INTO public.profiles (id, email, display_name)
    VALUES (
      NEW.id, 
      NEW.email,
      COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email)
    );
    
    IF public_org_id IS NOT NULL THEN
      INSERT INTO public.organization_members (org_id, user_id, role)
      VALUES (public_org_id, NEW.id, 'viewer');
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 9. Replace the existing new user trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_invitation_signup();

-- 10. Ensure the bootstrap super admin invitation exists
INSERT INTO public.invitations (email, token, role, expires_at)
VALUES (
  'eduardo.ferro.aldama@gmail.com',
  'admin-bootstrap-token',
  'super_admin'::org_role,
  now() + interval '365 days'  -- Extended expiry for bootstrap
) ON CONFLICT (token) DO UPDATE SET
  expires_at = now() + interval '365 days';

-- 11. Grant super admin additional view permissions
DROP POLICY IF EXISTS "Users can view orgs they belong to" ON public.organizations;
CREATE POLICY "Users can view orgs they belong to or super admin can view all" 
ON public.organizations FOR SELECT 
USING (
  public.is_super_admin() OR 
  public.user_is_org_member(auth.uid(), id) OR 
  is_public = true
);

DROP POLICY IF EXISTS "Users can view members of orgs they belong to" ON public.organization_members;
CREATE POLICY "Users can view members or super admin can view all" 
ON public.organization_members FOR SELECT 
USING (
  public.is_super_admin() OR 
  public.user_is_org_member(auth.uid(), org_id)
);

-- 12. Allow super admin to manage all prompts
DROP POLICY IF EXISTS "Admins and owners can create prompts" ON public.prompts;
CREATE POLICY "Super admin, admins and owners can create prompts" 
ON public.prompts FOR INSERT 
WITH CHECK (
  auth.uid() = creator_id AND (
    public.is_super_admin() OR
    public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner')
  )
);

DROP POLICY IF EXISTS "Admins and owners can update prompts" ON public.prompts;
CREATE POLICY "Super admin, admins and owners can update prompts" 
ON public.prompts FOR UPDATE 
USING (
  public.is_super_admin() OR
  public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner')
);

DROP POLICY IF EXISTS "Admins and owners can delete prompts" ON public.prompts;
CREATE POLICY "Super admin, admins and owners can delete prompts" 
ON public.prompts FOR DELETE 
USING (
  public.is_super_admin() OR
  public.get_user_org_role(auth.uid(), org_id) IN ('admin', 'owner')
);

-- 13. Allow super admin to manage all prompt variants and arguments
DROP POLICY IF EXISTS "Admins and owners can manage variants" ON public.prompt_variants;
CREATE POLICY "Super admin, admins and owners can manage variants" 
ON public.prompt_variants FOR ALL 
USING (
  public.is_super_admin() OR
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_variants.prompt_id 
    AND public.get_user_org_role(auth.uid(), prompts.org_id) IN ('admin', 'owner')
  )
);

DROP POLICY IF EXISTS "Admins and owners can manage arguments" ON public.prompt_arguments;
CREATE POLICY "Super admin, admins and owners can manage arguments" 
ON public.prompt_arguments FOR ALL 
USING (
  public.is_super_admin() OR
  EXISTS (
    SELECT 1 FROM public.prompts 
    WHERE prompts.id = prompt_arguments.prompt_id 
    AND public.get_user_org_role(auth.uid(), prompts.org_id) IN ('admin', 'owner')
  )
);

-- 14. Comment explaining the super admin design
COMMENT ON FUNCTION public.is_super_admin IS 
'Returns true if the user is a super admin. Super admins can:
- Create organizations
- Invite new users  
- Access all organizations and data
- Override most permission restrictions
Only one super admin should exist: eduardo.ferro.aldama@gmail.com';