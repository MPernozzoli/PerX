import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { DiagnosticProvider } from "./contexts/DiagnosticContext";
import App from "./App.tsx";
import "./index.css";

const queryClient = new QueryClient();

createRoot(document.getElementById("root")!).render(
  <QueryClientProvider client={queryClient}>
    <DiagnosticProvider>
      <App />
    </DiagnosticProvider>
  </QueryClientProvider>,
);
