import { useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from './useAuth';
import { toast } from '@/hooks/use-toast';

interface Invitation {
  id: string;
  email: string;
  role: 'owner' | 'admin' | 'viewer' | 'super_admin';
  org_name: string;
  expires_at: string;
  created_at: string;
}

interface UserWithRoles {
  user_id: string;
  email: string;
  display_name: string;
  organizations: Array<{
    org_id: string;
    org_name: string;
    role: 'owner' | 'admin' | 'viewer' | 'super_admin';
    is_public: boolean;
  }>;
}

export function useSuperAdmin() {
  const { isSuperAdmin } = useAuth();
  const [loading, setLoading] = useState(false);

  const createInvitation = useCallback(async (
    email: string,
    role: 'owner' | 'admin' | 'viewer' = 'viewer',
    orgId?: string
  ) => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can create invitations');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('create_user_invitation', {
        p_email: email,
        p_role: role,
        p_org_id: orgId
      });

      if (error) throw error;

      toast({
        title: "Invitation sent",
        description: `Invitation sent to ${email} with role ${role}`,
      });

      return data;
    } catch (error: any) {
      toast({
        title: "Error creating invitation",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  const getPendingInvitations = useCallback(async (): Promise<Invitation[]> => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can view invitations');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('get_pending_invitations');

      if (error) throw error;

      return data || [];
    } catch (error: any) {
      toast({
        title: "Error fetching invitations",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  const revokeInvitation = useCallback(async (invitationId: string) => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can revoke invitations');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('revoke_invitation', {
        invitation_id: invitationId
      });

      if (error) throw error;

      toast({
        title: "Invitation revoked",
        description: "The invitation has been revoked successfully",
      });

      return data;
    } catch (error: any) {
      toast({
        title: "Error revoking invitation",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  const createOrganization = useCallback(async (
    name: string,
    isPublic: boolean = false
  ) => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can create organizations');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('create_organization_as_super_admin', {
        p_name: name,
        p_is_public: isPublic
      });

      if (error) throw error;

      toast({
        title: "Organization created",
        description: `Organization "${name}" created successfully`,
      });

      return data;
    } catch (error: any) {
      toast({
        title: "Error creating organization",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  const getAllUsersWithRoles = useCallback(async (): Promise<UserWithRoles[]> => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can view all users');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('get_all_users_with_roles');

      if (error) throw error;

      return data || [];
    } catch (error: any) {
      toast({
        title: "Error fetching users",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  const promoteUserToOwner = useCallback(async (
    userId: string,
    orgId: string
  ) => {
    if (!isSuperAdmin) {
      throw new Error('Only super admin can promote users');
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('promote_user_to_owner', {
        p_user_id: userId,
        p_org_id: orgId
      });

      if (error) throw error;

      toast({
        title: "User promoted",
        description: "User has been promoted to organization owner",
      });

      return data;
    } catch (error: any) {
      toast({
        title: "Error promoting user",
        description: error.message,
        variant: "destructive",
      });
      throw error;
    } finally {
      setLoading(false);
    }
  }, [isSuperAdmin]);

  return {
    isSuperAdmin,
    loading,
    createInvitation,
    getPendingInvitations,
    revokeInvitation,
    createOrganization,
    getAllUsersWithRoles,
    promoteUserToOwner,
  };
}