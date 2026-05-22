import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { UploadProvider } from "@/contexts/UploadContext";
import UploadProgress from "@/components/UploadProgress";
import Footer from "@/components/Footer";
import Index from "./pages/Index";
import Login from "./pages/Login";
import Admin from "./pages/Admin";
import ApiMode from "./pages/ApiMode";
import GISEditor from "./pages/GISEditor";
import NotFound from "./pages/NotFound";
import Privacy from "./pages/Privacy";
import CookiePolicy from "./pages/CookiePolicy";
import SessionHeartbeat from "@/components/SessionHeartbeat";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 min - riduce refetch PostgREST su focus/remount
    },
  },
});

const App = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <UploadProvider>
        <TooltipProvider>
        <Toaster />
        <Sonner position="top-center" />
        <UploadProgress />
        <BrowserRouter>
          <SessionHeartbeat />
          <div className="flex flex-col min-h-screen">
            <div className="flex-1">
              <Routes>
                <Route path="/" element={<Index />} />
                <Route path="/login" element={<Login />} />
                <Route path="/admin" element={<Admin />} />
                <Route path="/admin/gis-editor" element={<GISEditor />} />
                <Route path="/api" element={<ApiMode />} />
                <Route path="/privacy" element={<Privacy />} />
                <Route path="/cookie" element={<CookiePolicy />} />
                <Route path="*" element={<NotFound />} />
              </Routes>
            </div>
            <Footer />
          </div>
        </BrowserRouter>
        </TooltipProvider>
      </UploadProvider>
    </QueryClientProvider>
  );
};

export default App;
