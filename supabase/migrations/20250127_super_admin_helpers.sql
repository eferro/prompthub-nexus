-- Super Admin Helper Functions
-- Additional functions to support super admin operations

-- 1. Function to invite a new user (only for super admin)
CREATE OR REPLACE FUNCTION public.create_user_invitation(
  p_email TEXT,
  p_role public.org_role DEFAULT 'viewer',
  p_org_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  invitation_id UUID;
  token TEXT;
BEGIN
  -- Check if caller is super admin
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Only super admin can create invitations';
  END IF;
  
  -- Validate email format
  IF p_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;
  
  -- Generate unique token
  token := public.generate_invitation_token();
  
  -- Create invitation
  INSERT INTO public.invitations (email, token, role, org_id, invited_by, expires_at)
  VALUES (
    LOWER(p_email),
    token,
    p_role,
    p_org_id,
    auth.uid(),
    now() + interval '7 days'
  )
  RETURNING id INTO invitation_id;
  
  RETURN invitation_id;
END;
$$;

-- 2. Function to get all pending invitations (only for super admin)
CREATE OR REPLACE FUNCTION public.get_pending_invitations()
RETURNS TABLE (
  id UUID,
  email TEXT,
  role public.org_role,
  org_name TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT 
    i.id,
    i.email,
    i.role,
    COALESCE(o.name, 'No Organization') as org_name,
    i.expires_at,
    i.created_at
  FROM public.invitations i
  LEFT JOIN public.organizations o ON i.org_id = o.id
  WHERE 
    public.is_super_admin() AND
    i.used_at IS NULL AND 
    i.expires_at > now()
  ORDER BY i.created_at DESC;
$$;

-- 3. Function to revoke an invitation (only for super admin)
CREATE OR REPLACE FUNCTION public.revoke_invitation(invitation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Check if caller is super admin
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Only super admin can revoke invitations';
  END IF;
  
  -- Update invitation to expired
  UPDATE public.invitations 
  SET expires_at = now() - interval '1 day'
  WHERE id = invitation_id;
  
  RETURN FOUND;
END;
$$;

-- 4. Function to get super admin status for current user
CREATE OR REPLACE FUNCTION public.get_current_user_super_admin_status()
RETURNS JSON
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT json_build_object(
    'is_super_admin', public.is_super_admin(),
    'user_id', auth.uid(),
    'email', (SELECT email FROM auth.users WHERE id = auth.uid())
  );
$$;

-- 5. Function to promote user to organization owner (only super admin)
CREATE OR REPLACE FUNCTION public.promote_user_to_owner(
  p_user_id UUID,
  p_org_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Check if caller is super admin
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Only super admin can promote users';
  END IF;
  
  -- Update user role to owner
  UPDATE public.organization_members 
  SET role = 'owner'
  WHERE user_id = p_user_id AND org_id = p_org_id;
  
  RETURN FOUND;
END;
$$;

-- 6. Function to get all users and their roles (only for super admin)
CREATE OR REPLACE FUNCTION public.get_all_users_with_roles()
RETURNS TABLE (
  user_id UUID,
  email TEXT,
  display_name TEXT,
  organizations JSON
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT 
    p.id as user_id,
    p.email,
    p.display_name,
    COALESCE(
      json_agg(
        json_build_object(
          'org_id', o.id,
          'org_name', o.name,
          'role', om.role,
          'is_public', o.is_public
        )
      ) FILTER (WHERE o.id IS NOT NULL),
      '[]'::json
    ) as organizations
  FROM public.profiles p
  LEFT JOIN public.organization_members om ON p.id = om.user_id
  LEFT JOIN public.organizations o ON om.org_id = o.id
  WHERE public.is_super_admin()
  GROUP BY p.id, p.email, p.display_name
  ORDER BY p.email;
$$;

-- 7. Function to create organization (enhanced for super admin)
CREATE OR REPLACE FUNCTION public.create_organization_as_super_admin(
  p_name TEXT,
  p_is_public BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  org_id UUID;
BEGIN
  -- Check if caller is super admin
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Only super admin can create organizations directly';
  END IF;
  
  -- Create organization
  INSERT INTO public.organizations (name, is_public)
  VALUES (p_name, p_is_public)
  RETURNING id INTO org_id;
  
  -- Add super admin as owner of the new organization
  INSERT INTO public.organization_members (org_id, user_id, role)
  VALUES (org_id, auth.uid(), 'owner');
  
  RETURN org_id;
END;
$$;

-- 8. Add these functions to the database schema types
COMMENT ON FUNCTION public.create_user_invitation IS 'Super admin only: Create invitation for new user';
COMMENT ON FUNCTION public.get_pending_invitations IS 'Super admin only: Get all pending invitations';
COMMENT ON FUNCTION public.revoke_invitation IS 'Super admin only: Revoke an invitation';
COMMENT ON FUNCTION public.get_current_user_super_admin_status IS 'Get current user super admin status';
COMMENT ON FUNCTION public.promote_user_to_owner IS 'Super admin only: Promote user to organization owner';
COMMENT ON FUNCTION public.get_all_users_with_roles IS 'Super admin only: Get all users with their organization roles';
COMMENT ON FUNCTION public.create_organization_as_super_admin IS 'Super admin only: Create organization and become owner';