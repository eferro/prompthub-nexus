-- Create bootstrap invitation for admin
INSERT INTO public.invitations (email, token, role, expires_at)
VALUES (
  'eduardo.ferro.aldama@gmail.com',
  'admin-bootstrap-token',
  'super_admin'::org_role,
  now() + interval '1 day'
) ON CONFLICT DO NOTHING;