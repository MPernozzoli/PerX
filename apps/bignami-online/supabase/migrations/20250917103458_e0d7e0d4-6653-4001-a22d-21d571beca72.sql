-- Insert default coverages for existing policy editions that don't have one
INSERT INTO public.coverages (
  policy_edition_id,
  guarantee,
  overview_text,
  definitions,
  common_exclusions,
  common_interpretations,
  common_notes,
  value_type
)
SELECT 
  pe.id as policy_edition_id,
  'Fenomeno Elettrico' as guarantee,
  'Copertura per danni causati da fenomeno elettrico' as overview_text,
  ARRAY['Danni diretti causati da fenomeno elettrico', 'Sovratensioni e cortocircuiti'] as definitions,
  ARRAY['Danni causati da usura', 'Difetti di manutenzione'] as common_exclusions,
  ARRAY['Per fenomeno elettrico si intende...'] as common_interpretations,
  ARRAY['Copertura attiva 24h/24'] as common_notes,
  'valore_intero' as value_type
FROM public.policy_editions pe
LEFT JOIN public.coverages c ON c.policy_edition_id = pe.id
WHERE c.id IS NULL;