import { Toaster } from "@perx/ui/components/ui/toaster";
import { Toaster as Sonner } from "@perx/ui/components/ui/sonner";
import { TooltipProvider } from "@perx/ui/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider, useAuth } from "./contexts/AuthContext";
import { AuthModalProvider } from "./contexts/AuthModalContext";
import { AuthModal } from "./components/AuthModal";
import { HomePage } from "./pages/HomePage";
import { PolicyDetail } from "./pages/PolicyDetail";
import { AddPolicy } from "./pages/AddPolicy";
import { Profile } from "./pages/Profile";
import { Settings } from "./pages/Settings";
import { StudioSettings } from "./pages/StudioSettings";
import { Studios } from "./pages/Studios";
import { StudioDetail } from "./pages/StudioDetail";
import { Admin } from "./pages/Admin";
import NotFound from "./pages/NotFound";
import { Loader2 } from "lucide-react";

const queryClient = new QueryClient();

const ProtectedRoute = ({ children }: { children: React.ReactNode }) => {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    );
  }

  if (!user) {
    return <>{children}</>;
  }

  return <>{children}</>;
};

const AppRoutes = () => {
  const { loading } = useAuth();

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    );
  }

  return (
    <Routes>
      {/* Public routes */}
      <Route path="/" element={<HomePage />} />
      {/* Policy viewing routes - public with limited functionality */}
      <Route path="/:companyCode/:policyCode" element={<PolicyDetail />} />
      <Route path="/:companyCode/:policyCode/:editionCode" element={<PolicyDetail />} />
      <Route path="/policy/:policyId" element={<PolicyDetail />} />
      <Route path="/policy/:policyId/edition/:editionId" element={<PolicyDetail />} />
      
      {/* Protected routes */}
      <Route path="/add-policy" element={<ProtectedRoute><AddPolicy /></ProtectedRoute>} />
      <Route path="/profile" element={<ProtectedRoute><Profile /></ProtectedRoute>} />
      <Route path="/settings" element={<ProtectedRoute><Settings /></ProtectedRoute>} />
      <Route path="/studios" element={<ProtectedRoute><Studios /></ProtectedRoute>} />
      <Route path="/studio/:studioId" element={<ProtectedRoute><StudioDetail /></ProtectedRoute>} />
      <Route path="/studio/:studioId/settings" element={<ProtectedRoute><StudioSettings /></ProtectedRoute>} />
      <Route path="/admin" element={<ProtectedRoute><Admin /></ProtectedRoute>} />
      
      {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
      <Route path="*" element={<NotFound />} />
    </Routes>
  );
};

const App = () => (
  <QueryClientProvider client={queryClient}>
    <AuthProvider>
      <AuthModalProvider>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>
            <AppRoutes />
            <AuthModal />
          </BrowserRouter>
        </TooltipProvider>
      </AuthModalProvider>
    </AuthProvider>
  </QueryClientProvider>
);

export default App;
