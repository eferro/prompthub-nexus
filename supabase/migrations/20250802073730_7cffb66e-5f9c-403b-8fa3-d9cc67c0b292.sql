-- Make invited_by nullable to allow bootstrap invitation
ALTER TABLE public.invitations ALTER COLUMN invited_by DROP NOT NULL;