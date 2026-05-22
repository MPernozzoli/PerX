import { AdminDomainRoutes } from "@/components/admin-domain-routes";

export default function AdminGatewayPage() {
  return (
    <main className="min-h-screen bg-zinc-950 px-6 py-16 text-zinc-50">
      <section className="mx-auto max-w-6xl">
        <p className="text-sm uppercase tracking-[0.18em] text-cyan-300">PerX Admin</p>
        <h1 className="mt-4 text-4xl font-semibold">Pannello di controllo</h1>
        <p className="mt-4 text-zinc-300">
          Gestisci le route dominio per CatDispatcher, admin PerX e portali assicurati dei tenant.
        </p>
        <AdminDomainRoutes />
      </section>
    </main>
  );
}
