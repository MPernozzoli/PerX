"""Stati del tenant Chiari, unico elenco per cruscotto, Regia ed estensione."""
from __future__ import annotations

CHIARI_STATES: tuple[dict, ...] = (
    {
        "code": "ATTESA_SOPRALLUOGO",
        "label": "Attesa sopralluogo",
        "description": "Importato con Salesforce «Assegnato a sopralluoghista». Gli agenti non fanno la perizia.",
        "actor": "estensione",
        "is_meta": False,
        "sort_order": 10,
    },
    {
        "code": "DA_LAVORARE",
        "label": "Da lavorare",
        "description": "Sinistro nuovo, senza una stima salvata.",
        "actor": "regia",
        "is_meta": False,
        "sort_order": 20,
    },
    {
        "code": "IN_LAVORAZIONE",
        "label": "In lavorazione",
        "description": "Apertura in corso. Non si imposta e non si trascina.",
        "actor": "regia",
        "is_meta": True,
        "sort_order": 30,
    },
    {
        "code": "DA_CONTATTARE",
        "label": "Da contattare",
        "description": "Il perito deve chiamare. Compare in Per oggi.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 40,
    },
    {
        "code": "IN_ATTESA_DOC",
        "label": "Attesa documenti",
        "description": "Chiesti documenti, IBAN o chiarimenti.",
        "actor": "regia",
        "is_meta": False,
        "sort_order": 50,
    },
    {
        "code": "DAL_PERITO",
        "label": "Decide il perito",
        "description": "L'agente si è fermato: scostamento, negativa, polizza o beneficiario.",
        "actor": "regia",
        "is_meta": False,
        "sort_order": 60,
    },
    {
        "code": "ATTO_PRONTO",
        "label": "Atto pronto",
        "description": "Stima salvata: da qui si invia l'atto.",
        "actor": "regia",
        "is_meta": False,
        "sort_order": 70,
    },
    {
        "code": "ATTO_INVIATO",
        "label": "Atto inviato",
        "description": "Atto inviato, in attesa di firma.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 80,
    },
    {
        "code": "STIMA_DA_RIVEDERE",
        "label": "Stima da rivedere",
        "description": "Atto rifiutato o nuova documentazione sull'importo.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 90,
    },
    {
        "code": "DA_CHIUDERE",
        "label": "Da chiudere",
        "description": "Atto firmato, solleciti senza risposta, o negativa decisa.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 100,
    },
    {
        "code": "IN_CHIUSURA",
        "label": "In chiusura",
        "description": "Chiusura in corso. Non si imposta e non si trascina.",
        "actor": "regia",
        "is_meta": True,
        "sort_order": 110,
    },
    {
        "code": "CHIUSURA_DA_RIVEDERE",
        "label": "Chiusura da rivedere",
        "description": "La chiusura è stata rimandata indietro.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 120,
    },
    {
        "code": "CHIUSO",
        "label": "Chiuso",
        "description": "Consegna segreteria fatta.",
        "actor": "regia",
        "is_meta": False,
        "sort_order": 130,
    },
    {
        "code": "REVOCATO",
        "label": "Revocato",
        "description": "Incarico revocato o già seguito da un altro perito.",
        "actor": "perito",
        "is_meta": False,
        "sort_order": 140,
    },
)

# Stato Chiari → slug già usato da PerX (automazioni, filtri, contatori).
CHIARI_TO_PERX = {
    "ATTESA_SOPRALLUOGO": "sopralluogo",
    "DA_LAVORARE": "istruzione",
    "IN_LAVORAZIONE": "in_gestione",
    "DA_CONTATTARE": "primo_contatto",
    "IN_ATTESA_DOC": "in_attesa_documentale",
    "DAL_PERITO": "da_revisionare",
    "ATTO_PRONTO": "atto_da_inviare",
    "ATTO_INVIATO": "atto_inviato",
    "STIMA_DA_RIVEDERE": "da_revisionare",
    "DA_CHIUDERE": "da_chiudere_a_sistema",
    "IN_CHIUSURA": "da_chiudere_a_sistema",
    "CHIUSURA_DA_RIVEDERE": "da_revisionare",
    "CHIUSO": "chiusa",
    "REVOCATO": "revocata",
}


def perx_slug(chiari_code: str) -> str:
    return CHIARI_TO_PERX.get(chiari_code, "istruzione")
