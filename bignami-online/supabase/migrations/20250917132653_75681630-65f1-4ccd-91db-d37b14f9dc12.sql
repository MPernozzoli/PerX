-- Pulire tutti i dati dalle tabelle mantenendo la struttura
DELETE FROM coverage_items;
DELETE FROM sections;
DELETE FROM common_limits;
DELETE FROM coverages;
DELETE FROM policy_editions;
DELETE FROM policies;
DELETE FROM user_policy_interactions;
DELETE FROM edit_history;
DELETE FROM comments;

-- Reset delle sequences se necessario
-- Non serve per UUID ma buona pratica per verificare