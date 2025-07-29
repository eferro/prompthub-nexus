import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { ArrowLeft, Plus, Key, Copy, Trash2, Eye, EyeOff } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

interface ApiKey {
  id: string;
  name: string;
  key_hash: string;
  last_used_at: string | null;
  revoked_at: string | null;
  created_at: string;
  organizations: {
    name: string;
  };
}

interface Organization {
  id: string;
  name: string;
}

const ApiKeys = () => {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([]);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [newApiKey, setNewApiKey] = useState({ name: '', org_id: '' });
  const [generatedKey, setGeneratedKey] = useState('');
  const [showGeneratedKey, setShowGeneratedKey] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [user, loading, navigate]);

  useEffect(() => {
    if (user) {
      fetchData();
    }
  }, [user]);

  const fetchData = async () => {
    try {
      // Fetch API keys
      const { data: keysData, error: keysError } = await supabase
        .from('api_keys')
        .select(`
          *,
          organizations (name)
        `)
        .order('created_at', { ascending: false });

      if (keysError) throw keysError;
      setApiKeys(keysData || []);

      // Fetch organizations where user can create API keys
      const { data: orgsData, error: orgsError } = await supabase
        .from('organization_members')
        .select(`
          organizations (id, name)
        `)
        .in('role', ['admin', 'owner']);

      if (orgsError) throw orgsError;
      setOrganizations(orgsData?.map(om => om.organizations).filter(Boolean) || []);
    } catch (error) {
      console.error('Error fetching data:', error);
      toast({
        title: "Error",
        description: "Failed to load API keys and organizations",
        variant: "destructive"
      });
    } finally {
      setIsLoading(false);
    }
  };

  const generateApiKey = () => {
    // Generate a secure API key
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = 'pm_';
    for (let i = 0; i < 32; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  };

  const createApiKey = async () => {
    if (!newApiKey.name || !newApiKey.org_id) {
      toast({
        title: "Error",
        description: "Please fill in all required fields",
        variant: "destructive"
      });
      return;
    }

    try {
      const apiKey = generateApiKey();
      const keyHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(apiKey));
      const hashArray = Array.from(new Uint8Array(keyHash));
      const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

      const { error } = await supabase
        .from('api_keys')
        .insert({
          name: newApiKey.name,
          key_hash: hashHex,
          org_id: newApiKey.org_id,
          user_id: user?.id
        });

      if (error) throw error;

      setGeneratedKey(apiKey);
      setShowGeneratedKey(true);

      toast({
        title: "Success",
        description: "API key created successfully"
      });

      setNewApiKey({ name: '', org_id: '' });
      fetchData();
    } catch (error) {
      console.error('Error creating API key:', error);
      toast({
        title: "Error",
        description: "Failed to create API key",
        variant: "destructive"
      });
    }
  };

  const revokeApiKey = async (keyId: string) => {
    try {
      const { error } = await supabase
        .from('api_keys')
        .update({ revoked_at: new Date().toISOString() })
        .eq('id', keyId);

      if (error) throw error;

      toast({
        title: "Success",
        description: "API key revoked successfully"
      });

      fetchData();
    } catch (error) {
      console.error('Error revoking API key:', error);
      toast({
        title: "Error",
        description: "Failed to revoke API key",
        variant: "destructive"
      });
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    toast({
      title: "Copied",
      description: "API key copied to clipboard"
    });
  };

  const closeGeneratedKeyDialog = () => {
    setIsCreateDialogOpen(false);
    setShowGeneratedKey(false);
    setGeneratedKey('');
  };

  if (loading || isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <p className="text-xl text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="min-h-screen bg-background p-4">
      <div className="max-w-6xl mx-auto">
        <header className="flex items-center justify-between mb-8">
          <div className="flex items-center gap-4">
            <Button variant="ghost" onClick={() => navigate('/')}>
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back
            </Button>
            <div>
              <h1 className="text-3xl font-bold">API Keys</h1>
              <p className="text-muted-foreground">Generate and manage API keys for MCP integration</p>
            </div>
          </div>
          
          <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
            <DialogTrigger asChild>
              <Button>
                <Plus className="h-4 w-4 mr-2" />
                Generate API Key
              </Button>
            </DialogTrigger>
            <DialogContent>
              {!showGeneratedKey ? (
                <>
                  <DialogHeader>
                    <DialogTitle>Generate New API Key</DialogTitle>
                    <DialogDescription>
                      Create a new API key for accessing prompts via MCP
                    </DialogDescription>
                  </DialogHeader>
                  <div className="grid gap-4 py-4">
                    <div className="grid gap-2">
                      <Label htmlFor="name">Key Name</Label>
                      <Input
                        id="name"
                        value={newApiKey.name}
                        onChange={(e) => setNewApiKey({ ...newApiKey, name: e.target.value })}
                        placeholder="Enter a descriptive name"
                      />
                    </div>
                    <div className="grid gap-2">
                      <Label htmlFor="organization">Organization</Label>
                      <Select value={newApiKey.org_id} onValueChange={(value) => setNewApiKey({ ...newApiKey, org_id: value })}>
                        <SelectTrigger>
                          <SelectValue placeholder="Select organization" />
                        </SelectTrigger>
                        <SelectContent>
                          {organizations.map((org) => (
                            <SelectItem key={org.id} value={org.id}>
                              {org.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                  <div className="flex justify-end gap-2">
                    <Button variant="outline" onClick={() => setIsCreateDialogOpen(false)}>
                      Cancel
                    </Button>
                    <Button onClick={createApiKey}>Generate Key</Button>
                  </div>
                </>
              ) : (
                <>
                  <DialogHeader>
                    <DialogTitle>API Key Generated</DialogTitle>
                    <DialogDescription>
                      Save this API key securely. You won't be able to see it again.
                    </DialogDescription>
                  </DialogHeader>
                  <div className="grid gap-4 py-4">
                    <div className="grid gap-2">
                      <Label>Your API Key</Label>
                      <div className="flex gap-2">
                        <Input
                          readOnly
                          value={generatedKey}
                          className="font-mono"
                        />
                        <Button size="sm" onClick={() => copyToClipboard(generatedKey)}>
                          <Copy className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                    <div className="p-3 bg-amber-50 border border-amber-200 rounded">
                      <p className="text-sm text-amber-800">
                        <strong>Important:</strong> Store this key securely. For security reasons, we cannot show it again.
                      </p>
                    </div>
                  </div>
                  <div className="flex justify-end">
                    <Button onClick={closeGeneratedKeyDialog}>Done</Button>
                  </div>
                </>
              )}
            </DialogContent>
          </Dialog>
        </header>

        {apiKeys.length === 0 ? (
          <Card className="text-center py-12">
            <CardContent>
              <Key className="h-12 w-12 mx-auto mb-4 text-muted-foreground" />
              <h3 className="text-lg font-semibold mb-2">No API keys yet</h3>
              <p className="text-muted-foreground mb-4">
                Generate your first API key to start using PromptMesh with MCP
              </p>
              <Button onClick={() => setIsCreateDialogOpen(true)}>
                <Plus className="h-4 w-4 mr-2" />
                Generate Your First API Key
              </Button>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-4">
            {apiKeys.map((apiKey) => (
              <Card key={apiKey.id}>
                <CardHeader>
                  <div className="flex items-start justify-between">
                    <div>
                      <CardTitle className="text-lg">{apiKey.name}</CardTitle>
                      <CardDescription>{apiKey.organizations.name}</CardDescription>
                      <div className="flex items-center gap-2 mt-2">
                        {apiKey.revoked_at ? (
                          <Badge variant="destructive">Revoked</Badge>
                        ) : (
                          <Badge variant="default">Active</Badge>
                        )}
                      </div>
                    </div>
                    {!apiKey.revoked_at && (
                      <Button variant="ghost" size="sm" onClick={() => revokeApiKey(apiKey.id)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="grid gap-2 text-sm">
                    <div>
                      <span className="font-medium">Created:</span>{' '}
                      {new Date(apiKey.created_at).toLocaleDateString()}
                    </div>
                    {apiKey.last_used_at && (
                      <div>
                        <span className="font-medium">Last used:</span>{' '}
                        {new Date(apiKey.last_used_at).toLocaleDateString()}
                      </div>
                    )}
                    <div>
                      <span className="font-medium">Key (hashed):</span>{' '}
                      <code className="text-xs bg-muted px-2 py-1 rounded">
                        {apiKey.key_hash.substring(0, 8)}...
                      </code>
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default ApiKeys;