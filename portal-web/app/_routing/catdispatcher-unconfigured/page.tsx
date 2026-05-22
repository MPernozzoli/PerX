export default function CatDispatcherUnconfiguredPage() {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-white">
      <section className="mx-auto max-w-3xl">
        <p className="text-sm uppercase tracking-[0.18em] text-sky-300">CatDispatcher</p>
        <h1 className="mt-4 text-4xl font-semibold">Routing non configurato</h1>
        <p className="mt-4 text-slate-300">
          Imposta `CATDISPATCHER_ORIGIN` su Vercel oppure configura una route
          `catdispatcher` con `destination_url` dal pannello admin PerX.
        </p>
      </section>
    </main>
  );
}
