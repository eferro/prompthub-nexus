import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

const Index = () => {
  const { user, loading, signOut } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
  }, [user, loading, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <p className="text-xl text-muted-foreground">Loading...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null; // Will redirect to auth
  }

  return (
    <div className="min-h-screen bg-background p-4">
      <div className="max-w-4xl mx-auto">
        <header className="flex justify-between items-center mb-8">
          <div>
            <h1 className="text-3xl font-bold">PromptMesh</h1>
            <p className="text-muted-foreground">Welcome back, {user.email}</p>
          </div>
          <Button variant="outline" onClick={signOut}>
            Sign Out
          </Button>
        </header>

        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle>Prompts</CardTitle>
              <CardDescription>
                Create and manage your AI prompts across organizations
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button className="w-full">View Prompts</Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Organizations</CardTitle>
              <CardDescription>
                Manage your organization memberships and roles
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button className="w-full" variant="outline">View Organizations</Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>API Keys</CardTitle>
              <CardDescription>
                Generate API keys for MCP integration
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Button className="w-full" variant="outline">Manage Keys</Button>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default Index;
