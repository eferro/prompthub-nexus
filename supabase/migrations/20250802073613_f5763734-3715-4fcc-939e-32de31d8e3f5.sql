-- Create a temporary invitation for the admin to sign up
INSERT INTO public.invitations (email, token, role, invited_by, expires_at)
VALUES (
  'eduardo.ferro.aldama@gmail.com',
  'admin-bootstrap-token',
  'super_admin'::org_role,
  '00000000-0000-0000-0000-000000000000', -- temporary placeholder
  now() + interval '1 day'
);