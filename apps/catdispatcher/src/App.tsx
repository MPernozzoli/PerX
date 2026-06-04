"use client";

import { Toaster } from "@perx/ui/components/ui/toaster";
import { Toaster as Sonner } from "@perx/ui/components/ui/sonner";
import { TooltipProvider } from "@perx/ui/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { UploadProvider } from "@/contexts/UploadContext";
import UploadProgress from "@/components/UploadProgress";
import Footer from "@/components/Footer";
import Index from "./screens/Index";
import Login from "./screens/Login";
import Admin from "./screens/Admin";
import ApiMode from "./screens/ApiMode";
import GISEditor from "./screens/GISEditor";
import NotFound from "./screens/NotFound";
import Privacy from "./screens/Privacy";
import CookiePolicy from "./screens/CookiePolicy";
import SessionHeartbeat from "@/components/SessionHeartbeat";
import { DiagnosticProvider } from "@/contexts/DiagnosticContext";

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
        <DiagnosticProvider>
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
        </DiagnosticProvider>
      </UploadProvider>
    </QueryClientProvider>
  );
};

export default App;
